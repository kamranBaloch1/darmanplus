import 'dart:io';

import 'package:darmaan/core/constants/specializations.dart';
import 'package:darmaan/core/models/user_model.dart';
import 'package:darmaan/core/theme/app_colors.dart';
import 'package:darmaan/core/utils/app_error_message.dart';
import 'package:darmaan/presentation/home/doctor/repository/doctor_profile_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';
import 'package:cached_network_image/cached_network_image.dart';

class EditDoctorProfileScreen extends StatefulWidget {
  final UserModel currentUser;

  const EditDoctorProfileScreen({super.key, required this.currentUser});

  @override
  State<EditDoctorProfileScreen> createState() =>
      _EditDoctorProfileScreenState();
}

class _EditDoctorProfileScreenState extends State<EditDoctorProfileScreen> {
  final DoctorProfileRepository _repository = DoctorProfileRepository();

  late final TextEditingController _nameController;
  late final TextEditingController _feeController;
  late final TextEditingController _experienceController;

  String? _gender;
  String? _specialization;
  final List<String> _selectedQualifications = [];
  late final List<String> _qualificationOptions;
  late final List<DoctorSpecialization> _specializationOptions;

  File? _croppedPhoto;
  File? _pickedVideo;
  String? _pickedVideoName;

  bool isSaving = false;
  bool isCropping = false;
  bool _isCompressingVideo = false;
  double _compressionProgress = 0;
  Subscription? _compressionSubscription;

  static const Color _bg = Color(0xFFFAFBFD);

 @override
void initState() {
  super.initState();

  _compressionSubscription =
      VideoCompress.compressProgress$.subscribe((progress) {
    if (!mounted || !_isCompressingVideo) return;
    setState(() => _compressionProgress = progress.clamp(0, 100).toDouble());
  });

  _nameController = TextEditingController(
    text: widget.currentUser.name,
  );

  _feeController = TextEditingController(
    text: _initialFeeText(),
  );

  _experienceController = TextEditingController(
    text: widget.currentUser.experienceYears?.toString() ?? '',
  );

  _qualificationOptions = [
    'MBBS',
    'BDS',
    'DPT',
    'Pharm-D',
    'MD',
    'MS',
    'FCPS',
    'MCPS',
    'MRCP',
    'MRCS',
    'FRCS',
    'MPhil',
    'PhD',
    'MPH',
    'MSc',
  ];
  final currentTitle = widget.currentUser.title?.trim();
  if (currentTitle != null && currentTitle.isNotEmpty) {
    _selectedQualifications.addAll(
      currentTitle
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .take(2),
    );
    for (final qualification in _selectedQualifications) {
      if (!_qualificationOptions.contains(qualification)) {
        _qualificationOptions.add(qualification);
      }
    }
  }

  _gender = widget.currentUser.gender;

  _specializationOptions = List<DoctorSpecialization>.from(
    kDoctorSpecializations,
  );

  final currentSpecialization = widget.currentUser.specialization?.trim();

  if (currentSpecialization != null &&
      currentSpecialization.isNotEmpty) {
    _specialization = currentSpecialization;

    final specializationExists = _specializationOptions.any(
      (item) => item.name == currentSpecialization,
    );

    if (!specializationExists) {
      _specializationOptions.add(
        DoctorSpecialization(
          name: currentSpecialization,
          icon: Icons.medical_services_rounded,
        ),
      );
    }
  }
}


  String _initialFeeText() {
    final fee = widget.currentUser.consultationFee;
    if (fee == null || fee <= 0) return '';
    return fee % 1 == 0 ? fee.toStringAsFixed(0) : fee.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _compressionSubscription?.unsubscribe();
    if (_isCompressingVideo) VideoCompress.cancelCompression();
    VideoCompress.deleteAllCache();
    _nameController.dispose();
    _feeController.dispose();
    _experienceController.dispose();
    super.dispose();
  }

  Future<void> _pickAndCropPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
      maxWidth: 3000,
      maxHeight: 3000,
    );
    if (picked == null) return;

    setState(() {
      isCropping = true;
    });

    try {
      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressQuality: 85,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop photo',
            toolbarColor: AppColors.brand,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            cropStyle: CropStyle.circle,
          ),
          IOSUiSettings(
            title: 'Crop photo',
            aspectRatioLockEnabled: true,
            cropStyle: CropStyle.circle,
          ),
        ],
      );

      if (cropped != null) {
        setState(() {
          _croppedPhoto = File(cropped.path);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          isCropping = false;
        });
      }
    }
  }

  Future<void> _pickVideo() async {
    if (_isCompressingVideo || isSaving) return;
    final picked = await ImagePicker().pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 2),
    );
    if (picked == null) return;

    final source = File(picked.path);
    final sourceBytes = await source.length();
    if (sourceBytes > 150 * 1024 * 1024) {
      _showSnack('Please choose a video smaller than 150 MB');
      return;
    }

    setState(() {
      _pickedVideo = null;
      _pickedVideoName = null;
      _isCompressingVideo = true;
      _compressionProgress = 0;
    });

    try {
      await VideoCompress.deleteAllCache();
      File uploadVideo = source;

      // Some phones return perfectly valid videos whose codec is not handled by
      // video_compress. Compression is an optimisation, so it must never make a
      // gallery video impossible to select.
      try {
        final media = await VideoCompress.compressVideo(
          source.path,
          quality: VideoQuality.MediumQuality,
          deleteOrigin: false,
          includeAudio: true,
          frameRate: 30,
        );
        final compressed = media?.file;
        if (compressed != null && await compressed.exists()) {
          uploadVideo = compressed;
        }
      } catch (_) {
        uploadVideo = source;
      }

      final uploadBytes = await uploadVideo.length();
      if (uploadBytes > 150 * 1024 * 1024) {
        if (uploadVideo.path != source.path && await uploadVideo.exists()) {
          await uploadVideo.delete();
        }
        throw Exception(
          'Please choose a video smaller than 150 MB.',
        );
      }
      if (!mounted) return;
      setState(() {
        _pickedVideo = uploadVideo;
        _pickedVideoName =
            'Ready to upload • ${(uploadBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      });
    } catch (error) {
      if (mounted) {
        _showSnack(
          AppErrorMessage.from(error),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCompressingVideo = false;
          _compressionProgress = 0;
        });
      }
    }
  }

  Future<void> _save() async {
    if (isSaving || _isCompressingVideo) return;

    if (_nameController.text.trim().isEmpty) {
      _showSnack('Name cannot be empty');
      return;
    }

    double? parsedFee;
    final feeText = _feeController.text.trim();
    if (feeText.isNotEmpty) {
      parsedFee = double.tryParse(feeText);
      if (parsedFee == null || parsedFee <= 0) {
        _showSnack('Enter a valid consultation fee');
        return;
      }
    }

    if (_selectedQualifications.isEmpty) {
      _showSnack('Select at least one qualification');
      return;
    }

    final experience = int.tryParse(_experienceController.text.trim());
    if (experience == null || experience < 1 || experience > 70) {
      _showSnack('Enter valid experience between 1 and 70 years');
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      await _repository.updateProfile(
        name: _nameController.text,
        specialization: _specialization,
        title: _selectedQualifications.join(', '),
        experienceYears: experience,
        gender: _gender,
        consultationFee: parsedFee,
        profilePhoto: _croppedPhoto,
        introVideo: _pickedVideo,
      );

      if (_pickedVideo != null) {
        await VideoCompress.deleteAllCache();
      }

      if (!mounted) return;
      setState(() => isSaving = false);
      await _showProfileSavedDialog();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isSaving = false;
      });

      _showSnack(AppErrorMessage.from(e));
    }
  }

  Future<void> _showProfileSavedDialog() {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 28.w),
        child: Container(
          padding: EdgeInsets.fromLTRB(24.w, 26.h, 24.w, 20.h),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24.r),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A0F172A),
                blurRadius: 28,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68.r,
                height: 68.r,
                decoration: const BoxDecoration(
                  color: Color(0xFFEAF5FF),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_rounded,
                  color: AppColors.brand,
                  size: 38.r,
                ),
              ),
              SizedBox(height: 18.h),
              Text(
                'Profile updated',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 21.sp,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF111827),
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                'Your professional information has been saved successfully.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 14.sp,
                  height: 1.45,
                  color: const Color(0xFF667085),
                ),
              ),
              SizedBox(height: 22.h),
              SizedBox(
                width: double.infinity,
                height: 50.h,
                child: FilledButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                  ),
                  child: Text(
                    'Done',
                    style: GoogleFonts.outfit(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.black87,
        margin: EdgeInsets.all(16.r),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.r),
        ),
        content: Text(message, style: GoogleFonts.outfit(fontSize: 13.sp)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: true,
        leading: Padding(
          padding: EdgeInsets.only(left: 12.w),
          child: InkWell(
            onTap: isSaving ? null : () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(12.r),
            child: Container(
              padding: EdgeInsets.all(9.r),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F6F8),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 15.sp,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
        title: Text(
          'Edit profile',
          style: GoogleFonts.outfit(
            fontSize: 17.sp,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 24.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Patients see this before booking with you.',
                      style: GoogleFonts.outfit(
                        fontSize: 13.sp,
                        color: AppColors.textSecondary,
                      ),
                    ),

                    SizedBox(height: 24.h),

                    // Photo picker with crop
                    Center(
                      child: GestureDetector(
                        onTap: isCropping ? null : _pickAndCropPhoto,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 100.w,
                              height: 100.w,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.brand.withValues(
                                  alpha: 0.08,
                                ),
                                image: _croppedPhoto != null
                                    ? DecorationImage(
                                        image: FileImage(_croppedPhoto!),
                                        fit: BoxFit.cover,
                                      )
                                    : (widget.currentUser.profileImage !=
                                            null
                                        ? DecorationImage(
                                            image: CachedNetworkImageProvider(
                                              widget.currentUser.profileImage!,
                                            ),
                                            fit: BoxFit.cover,
                                          )
                                        : null),
                              ),
                              child: isCropping
                                  ? const Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.brand,
                                      ),
                                    )
                                  : (_croppedPhoto == null &&
                                        widget.currentUser.profileImage ==
                                            null
                                    ? Icon(
                                        Icons.person_rounded,
                                        size: 40.sp,
                                        color: AppColors.brand,
                                      )
                                    : null),
                            ),
                            Positioned(
                              right: -2.w,
                              bottom: -2.w,
                              child: Container(
                                padding: EdgeInsets.all(7.r),
                                decoration: BoxDecoration(
                                  color: AppColors.brand,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.15,
                                      ),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.camera_alt_rounded,
                                  size: 13.sp,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    SizedBox(height: 10.h),

                    Center(
                      child: Text(
                        'Tap to change and crop photo',
                        style: GoogleFonts.outfit(
                          fontSize: 12.sp,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),

                    SizedBox(height: 24.h),

                    _SectionCard(
                      children: [
                        _FieldLabel('Full name'),
                        SizedBox(height: 8.h),
                        _TextField(
                          controller: _nameController,
                          hint: 'e.g. Dr. Sarah Ahmed',
                        ),

                        SizedBox(height: 18.h),

                        _FieldLabel('Consultation fee'),
                        SizedBox(height: 8.h),
                        _TextField(
                          controller: _feeController,
                          hint: 'e.g. 1500',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d{0,2}'),
                            ),
                          ],
                          prefixText: 'Rs. ',
                        ),

                        SizedBox(height: 18.h),

                        _FieldLabel('Specialization'),
                        SizedBox(height: 8.h),
                        _SpecializationDropdown(
                          value: _specialization,
                          options: _specializationOptions,
                          onChanged: (value) =>
                              setState(() => _specialization = value),
                        ),

                        SizedBox(height: 18.h),

                        _FieldLabel('Qualifications *'),
                        SizedBox(height: 8.h),
                        _QualificationsPicker(
                          values: _selectedQualifications,
                          options: _qualificationOptions,
                          onChanged: (values) => setState(() {
                            _selectedQualifications
                              ..clear()
                              ..addAll(values.take(2));
                            for (final qualification in values) {
                              if (!_qualificationOptions
                                  .contains(qualification)) {
                                _qualificationOptions.add(qualification);
                              }
                            }
                          }),
                        ),

                        SizedBox(height: 18.h),

                        _FieldLabel('Experience (years) *'),
                        SizedBox(height: 8.h),
                        _TextField(
                          controller: _experienceController,
                          hint: 'e.g. 5',
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(2),
                          ],
                          suffixText: 'years',
                        ),

                        SizedBox(height: 18.h),

                        _FieldLabel('Gender'),
                        SizedBox(height: 8.h),
                        Row(
                          children: [
                            _GenderChip(
                              label: 'Male',
                              isSelected: _gender == 'male',
                              onTap: () => setState(() => _gender = 'male'),
                            ),
                            SizedBox(width: 10.w),
                            _GenderChip(
                              label: 'Female',
                              isSelected: _gender == 'female',
                              onTap: () => setState(() => _gender = 'female'),
                            ),
                           
                          ],
                        ),
                      ],
                    ),

                    SizedBox(height: 14.h),

                    _SectionCard(
                      children: [
                        _FieldLabel('Intro video'),
                        SizedBox(height: 4.h),
                        Text(
                          'A short clip helps patients feel confident booking with you.',
                          style: GoogleFonts.outfit(
                            fontSize: 12.sp,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        SizedBox(height: 12.h),
                        InkWell(
                          onTap: _isCompressingVideo ? null : _pickVideo,
                          borderRadius: BorderRadius.circular(14.r),
                          child: Container(
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(
                              horizontal: 14.w,
                              vertical: 14.h,
                            ),
                            decoration: BoxDecoration(
                              color: _bg,
                              borderRadius: BorderRadius.circular(14.r),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40.w,
                                  height: 40.w,
                                  decoration: BoxDecoration(
                                    color: AppColors.brand.withValues(
                                      alpha: 0.08,
                                    ),
                                    borderRadius: BorderRadius.circular(12.r),
                                  ),
                                  child: _isCompressingVideo
                                      ? Padding(
                                          padding: EdgeInsets.all(10.w),
                                          child: CircularProgressIndicator(
                                            value: _compressionProgress > 0
                                                ? _compressionProgress / 100
                                                : null,
                                            strokeWidth: 2.2,
                                            color: AppColors.brand,
                                          ),
                                        )
                                      : Icon(
                                          _pickedVideo != null
                                              ? Icons.check_circle_rounded
                                              : Icons.videocam_outlined,
                                          color: AppColors.brand,
                                          size: 20.sp,
                                        ),
                                ),
                                SizedBox(width: 12.w),
                                Expanded(
                                  child: Text(
                                    _isCompressingVideo
                                        ? 'Compressing video… ${_compressionProgress.round()}%'
                                        : _pickedVideoName ??
                                        (widget.currentUser.introVideoUrl !=
                                                null
                                            ? 'Video already uploaded — tap to replace'
                                            : 'Tap to upload a short video'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.outfit(
                                      fontSize: 13.sp,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 18.sp,
                                  color: Colors.grey.shade400,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Sticky save button
            Container(
              padding: EdgeInsets.fromLTRB(20.w, 14.h, 20.w, 14.h),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 20,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52.h,
                child: ElevatedButton(
                  onPressed:
                      isSaving || _isCompressingVideo ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15.r),
                    ),
                  ),
                  child: isSaving
                      ? SizedBox(
                          width: 20.w,
                          height: 20.w,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Save changes',
                          style: GoogleFonts.outfit(
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final List<Widget> children;

  const _SectionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.outfit(
        fontSize: 12.5.sp,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class _QualificationsPicker extends StatelessWidget {
  final List<String> values;
  final List<String> options;
  final ValueChanged<List<String>> onChanged;

  const _QualificationsPicker({
    required this.values,
    required this.options,
    required this.onChanged,
  });

  Future<void> _openPicker(BuildContext context) async {
    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .42),
      builder: (_) => _QualificationsSearchSheet(
        options: options,
        selectedValues: values,
      ),
    );
    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = values.isNotEmpty;
    return Material(
      color: const Color(0xFFFAFBFD),
      borderRadius: BorderRadius.circular(13.r),
      child: InkWell(
        onTap: () => _openPicker(context),
        borderRadius: BorderRadius.circular(13.r),
        child: Container(
          constraints: BoxConstraints(minHeight: 52.h),
          padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: 10.h),
          child: Row(
            children: [
              Container(
                width: 32.w,
                height: 32.w,
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(9.r),
                ),
                child: Icon(
                  Icons.workspace_premium_rounded,
                  size: 18.sp,
                  color: AppColors.brand,
                ),
              ),
              SizedBox(width: 11.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      hasValue
                          ? values.join(', ')
                          : 'Select qualifications',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 13.5.sp,
                        color: hasValue
                            ? AppColors.textPrimary
                            : Colors.grey.shade400,
                      ),
                    ),
                    if (values.length > 1) ...[
                      SizedBox(height: 2.h),
                      Text(
                        '${values.length} qualifications selected',
                        style: GoogleFonts.outfit(
                          fontSize: 10.5.sp,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 21.sp,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QualificationsSearchSheet extends StatefulWidget {
  final List<String> options;
  final List<String> selectedValues;

  const _QualificationsSearchSheet({
    required this.options,
    required this.selectedValues,
  });

  @override
  State<_QualificationsSearchSheet> createState() =>
      _QualificationsSearchSheetState();
}

class _QualificationsSearchSheetState
    extends State<_QualificationsSearchSheet> {
  final TextEditingController _searchController = TextEditingController();
  late final Set<String> _selected;
  late final List<String> _options;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = {...widget.selectedValues};
    _options = [...widget.options];
  }

  List<String> get _filteredOptions {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _options;
    return _options
        .where((option) => option.toLowerCase().contains(query))
        .toList();
  }

  bool get _canAddCustom {
    final query = _query.trim();
    return query.length >= 2 &&
        !_options.any(
          (option) => option.toLowerCase() == query.toLowerCase(),
        ) &&
        !_selected.any(
          (option) => option.toLowerCase() == query.toLowerCase(),
        );
  }

  void _toggle(String qualification) {
    if (_selected.contains(qualification)) {
      setState(() => _selected.remove(qualification));
      return;
    }
    if (_selected.length >= 2) {
      _showLimitMessage();
      return;
    }
    setState(() {
      _selected.add(qualification);
    });
  }

  void _addCustom() {
    final qualification = _query.trim();
    if (!_canAddCustom) return;
    if (_selected.length >= 2) {
      _showLimitMessage();
      return;
    }
    setState(() {
      _options.add(qualification);
      _selected.add(qualification);
      _searchController.clear();
      _query = '';
    });
  }

  void _showLimitMessage() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'You can select up to 2 qualifications.',
            style: GoogleFonts.outfit(),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF20252B),
        ),
      );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = _filteredOptions;
    return FractionallySizedBox(
      heightFactor: .82,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26.r)),
        ),
        child: Column(
          children: [
            SizedBox(height: 10.h),
            Container(
              width: 42.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: const Color(0xFFD7DCE3),
                borderRadius: BorderRadius.circular(20.r),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 12.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Select qualifications',
                          style: GoogleFonts.outfit(
                            fontSize: 20.sp,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (_selected.isNotEmpty)
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 9.w,
                            vertical: 4.h,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.brand.withValues(alpha: .09),
                            borderRadius: BorderRadius.circular(20.r),
                          ),
                          child: Text(
                            '${_selected.length} selected',
                            style: GoogleFonts.outfit(
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w500,
                              color: AppColors.brand,
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: 5.h),
                  Text(
                    'Choose up to 2, or type a specific qualification.',
                    style: GoogleFonts.outfit(
                      fontSize: 12.5.sp,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  SizedBox(height: 15.h),
                  TextField(
                    controller: _searchController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (value) => setState(() => _query = value),
                    style: GoogleFonts.outfit(
                      fontSize: 14.sp,
                      color: AppColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search or add qualification',
                      hintStyle: GoogleFonts.outfit(
                        color: AppColors.textSecondary,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: AppColors.textSecondary,
                        size: 21.sp,
                      ),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                              icon: Icon(
                                Icons.close_rounded,
                                size: 19.sp,
                                color: AppColors.textSecondary,
                              ),
                            ),
                      filled: true,
                      fillColor: const Color(0xFFF5F7FA),
                      contentPadding: EdgeInsets.symmetric(vertical: 14.h),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14.r),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14.r),
                        borderSide: const BorderSide(
                          color: AppColors.brand,
                          width: 1.3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 12.h),
                children: [
                  if (_canAddCustom)
                    _qualificationTile(
                      label: 'Add “${_query.trim()}”',
                      selected: false,
                      icon: Icons.add_rounded,
                      onTap: _addCustom,
                    ),
                  ...results.map(
                    (qualification) => _qualificationTile(
                      label: qualification,
                      selected: _selected.contains(qualification),
                      icon: Icons.school_outlined,
                      onTap: () => _toggle(qualification),
                    ),
                  ),
                  if (results.isEmpty && !_canAddCustom)
                    Padding(
                      padding: EdgeInsets.only(top: 50.h),
                      child: Center(
                        child: Text(
                          'No qualification found',
                          style: GoogleFonts.outfit(
                            fontSize: 14.sp,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 16.h),
              decoration: const BoxDecoration(color: Colors.white),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  height: 50.h,
                  child: FilledButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => Navigator.pop(context, _selected.toList()),
                    style: FilledButton.styleFrom(
                      elevation: 0,
                      backgroundColor: AppColors.brand,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.r),
                      ),
                    ),
                    child: Text(
                      _selected.isEmpty
                          ? 'Select qualifications'
                          : 'Done (${_selected.length})',
                      style: GoogleFonts.outfit(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _qualificationTile({
    required String label,
    required bool selected,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: 3.h),
      child: Material(
        color: selected
            ? AppColors.brand.withValues(alpha: .08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(13.r),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13.r),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 11.h),
            child: Row(
              children: [
                Container(
                  width: 36.w,
                  height: 36.w,
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(icon, size: 18.sp, color: AppColors.brand),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.outfit(
                      fontSize: 13.5.sp,
                      fontWeight:
                          selected ? FontWeight.w500 : FontWeight.w400,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20.sp,
                  color: selected
                      ? AppColors.brand
                      : const Color(0xFFCBD2DC),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SpecializationDropdown extends StatelessWidget {
  final String? value;
  final List<DoctorSpecialization> options;
  final ValueChanged<String?> onChanged;

  const _SpecializationDropdown({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  DoctorSpecialization? get _selectedOption {
    for (final option in options) {
      if (option.name == value) return option;
    }
    return null;
  }

  Future<void> _openPicker(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .42),
      builder: (_) => _SpecializationSearchSheet(
        options: options,
        selectedValue: value,
      ),
    );
    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedOption;
    return Material(
      color: const Color(0xFFFAFBFD),
      borderRadius: BorderRadius.circular(13.r),
      child: InkWell(
        onTap: () => _openPicker(context),
        borderRadius: BorderRadius.circular(13.r),
        child: Container(
          height: 52.h,
          padding: EdgeInsets.symmetric(horizontal: 13.w),
          child: Row(
            children: [
              Container(
                width: 32.w,
                height: 32.w,
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(9.r),
                ),
                child: Icon(
                  selected?.icon ?? Icons.medical_services_outlined,
                  size: 17.sp,
                  color: AppColors.brand,
                ),
              ),
              SizedBox(width: 11.w),
              Expanded(
                child: Text(
                  selected?.name ?? 'Search specialization',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 13.5.sp,
                    color: selected == null
                        ? Colors.grey.shade400
                        : AppColors.textPrimary,
                  ),
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 21.sp,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpecializationSearchSheet extends StatefulWidget {
  final List<DoctorSpecialization> options;
  final String? selectedValue;

  const _SpecializationSearchSheet({
    required this.options,
    required this.selectedValue,
  });

  @override
  State<_SpecializationSearchSheet> createState() =>
      _SpecializationSearchSheetState();
}

class _SpecializationSearchSheetState
    extends State<_SpecializationSearchSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  List<DoctorSpecialization> get _filteredOptions {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.options;
    return widget.options
        .where((option) => option.name.toLowerCase().contains(query))
        .toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = _filteredOptions;
    return FractionallySizedBox(
      heightFactor: .84,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26.r)),
        ),
        child: Column(
          children: [
            SizedBox(height: 10.h),
            Container(
              width: 42.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: const Color(0xFFD7DCE3),
                borderRadius: BorderRadius.circular(20.r),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 14.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose specialization',
                    style: GoogleFonts.outfit(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    'Search and select your primary medical field.',
                    style: GoogleFonts.outfit(
                      fontSize: 12.5.sp,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  SizedBox(height: 16.h),
                  TextField(
                    controller: _searchController,
                    autofocus: true,
                    onChanged: (value) => setState(() => _query = value),
                    style: GoogleFonts.outfit(
                      fontSize: 14.sp,
                      color: AppColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search specialization',
                      hintStyle: GoogleFonts.outfit(
                        color: AppColors.textSecondary,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: AppColors.textSecondary,
                        size: 21.sp,
                      ),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                              icon: Icon(
                                Icons.close_rounded,
                                size: 19.sp,
                                color: AppColors.textSecondary,
                              ),
                            ),
                      filled: true,
                      fillColor: const Color(0xFFF5F7FA),
                      contentPadding: EdgeInsets.symmetric(vertical: 14.h),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14.r),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14.r),
                        borderSide: const BorderSide(
                          color: AppColors.brand,
                          width: 1.3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: results.isEmpty
                  ? Center(
                      child: Text(
                        'No specialization found',
                        style: GoogleFonts.outfit(
                          fontSize: 14.sp,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  : ListView.separated(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 18.h),
                      itemCount: results.length,
                      separatorBuilder: (_, __) => SizedBox(height: 3.h),
                      itemBuilder: (context, index) {
                        final option = results[index];
                        final selected = option.name == widget.selectedValue;
                        return Material(
                          color: selected
                              ? AppColors.brand.withValues(alpha: .08)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14.r),
                          child: InkWell(
                            onTap: () => Navigator.pop(context, option.name),
                            borderRadius: BorderRadius.circular(14.r),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 12.w,
                                vertical: 11.h,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38.w,
                                    height: 38.w,
                                    decoration: BoxDecoration(
                                      color: AppColors.brand
                                          .withValues(alpha: .09),
                                      borderRadius: BorderRadius.circular(11.r),
                                    ),
                                    child: Icon(
                                      option.icon,
                                      size: 19.sp,
                                      color: AppColors.brand,
                                    ),
                                  ),
                                  SizedBox(width: 12.w),
                                  Expanded(
                                    child: Text(
                                      option.name,
                                      style: GoogleFonts.outfit(
                                        fontSize: 13.5.sp,
                                        fontWeight: selected
                                            ? FontWeight.w500
                                            : FontWeight.w400,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  if (selected)
                                    Icon(
                                      Icons.check_circle_rounded,
                                      size: 20.sp,
                                      color: AppColors.brand,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? prefixText;
  final String? suffixText;

  const _TextField({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
    this.prefixText,
    this.suffixText,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: GoogleFonts.outfit(fontSize: 13.5.sp, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.outfit(
          fontSize: 13.sp,
          color: Colors.grey.shade400,
        ),
        prefixText: prefixText,
        suffixText: suffixText,
        suffixStyle: GoogleFonts.outfit(
          fontSize: 12.5.sp,
          color: AppColors.textSecondary,
        ),
        prefixStyle: GoogleFonts.outfit(
          fontSize: 13.5.sp,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
        filled: true,
        fillColor: const Color(0xFFFAFBFD),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14.w,
          vertical: 13.h,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13.r),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13.r),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13.r),
          borderSide: const BorderSide(color: AppColors.brand, width: 1.6),
        ),
      ),
    );
  }
}

class _GenderChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _GenderChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12.r),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(vertical: 12.h),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.brand.withValues(alpha: 0.1)
                : const Color(0xFFFAFBFD),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
              color: isSelected ? AppColors.brand : Colors.transparent,
              width: 1.4,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
              color: isSelected ? AppColors.brand : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
