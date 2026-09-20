import 'dart:io';

import 'package:darmaan/core/theme/app_colors.dart';
import 'package:darmaan/presentation/auth/repository/register/doctor_repository.dart';
import 'package:darmaan/presentation/auth/screens/register/doctor_verification_screen.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:darmaan/core/utils/app_error_message.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

class DoctorDocumentScreen extends StatefulWidget {
  const DoctorDocumentScreen({super.key});

  @override
  State<DoctorDocumentScreen> createState() =>
      _DoctorDocumentScreenState();
}

class _DoctorDocumentScreenState extends State<DoctorDocumentScreen> {
  final DoctorRepository _doctorRepository = DoctorRepository();
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();

  bool isSubmitting = false;
  bool _isPickingPhoto = false;

  List<XFile> doctorDocuments = [];
  File? _profilePhoto;
  String? _nameError;
  String? _photoError;

  bool get hasDocument => doctorDocuments.isNotEmpty;
  bool get _hasPersonalDetails =>
      _nameController.text.trim().length >= 2 && _profilePhoto != null;
  bool get _canSubmit =>
      _hasPersonalDetails && hasDocument && !isSubmitting;

  static const XTypeGroup _pdfTypeGroup = XTypeGroup(
    label: 'PDF',
    extensions: ['pdf'],
    uniformTypeIdentifiers: ['com.adobe.pdf'], // iOS
  );

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() {
      if (!mounted) return;
      setState(() {
        if (_nameController.text.trim().length >= 2) _nameError = null;
      });
    });
  }

  Future<void> _pickProfilePhoto() async {
    if (_isPickingPhoto || isSubmitting) return;
    setState(() {
      _isPickingPhoto = true;
      _photoError = null;
    });

    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
        maxWidth: 2400,
        maxHeight: 2400,
      );
      if (picked == null) return;

      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 86,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop profile photo',
            toolbarColor: AppColors.brand,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            cropStyle: CropStyle.circle,
          ),
          IOSUiSettings(
            title: 'Crop profile photo',
            aspectRatioLockEnabled: true,
            cropStyle: CropStyle.circle,
          ),
        ],
      );

      if (cropped != null && mounted) {
        setState(() => _profilePhoto = File(cropped.path));
      }
    } catch (error) {
      if (mounted) {
        _showSnack(
          'Could not select profile photo: ${AppErrorMessage.from(error)}',
        );
      }
    } finally {
      if (mounted) setState(() => _isPickingPhoto = false);
    }
  }

  Future<void> _pickDocument() async {
    if (isSubmitting) return;

    try {
      final result = await openFiles(
        acceptedTypeGroups: [_pdfTypeGroup],
      );

      if (result.isNotEmpty) {
        setState(() => doctorDocuments = result);
      }
    } catch (e) {
      if (!mounted) return;

      _showSnack(AppErrorMessage.from(
        e,
        fallback: 'Could not select document. Please try again.',
      ));
    }
  }

  void _removeDocument(int index) {
    if (isSubmitting) return;

    setState(() {
      doctorDocuments.removeAt(index);
    });
  }

  Future<void> _submitDocuments() async {
    if (isSubmitting) return;

    final name = _nameController.text.trim();
    setState(() {
      _nameError = name.length < 2 ? 'Enter your full name' : null;
      _photoError = _profilePhoto == null ? 'Add a clear profile photo' : null;
    });
    if (!_hasPersonalDetails || doctorDocuments.isEmpty) {
      if (doctorDocuments.isEmpty) {
        _showSnack('Please upload at least one verification document.');
      }
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      isSubmitting = true;
    });

    try {
      await _doctorRepository.submitDoctorDocuments(
        doctorDocuments,
        name: name,
        profilePhoto: _profilePhoto!,
      );

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const DoctorVerificationPendingScreen(),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isSubmitting = false;
      });

      _showSnack(AppErrorMessage.from(e));
    }
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
        content: Text(message, style: GoogleFonts.outfit()),
      ),
    );
  }

  Widget _buildProfilePhoto() {
    return Column(
      children: [
        Semantics(
          button: true,
          label: _profilePhoto == null
              ? 'Add doctor profile photo'
              : 'Change doctor profile photo',
          child: InkWell(
            onTap: _isPickingPhoto || isSubmitting
                ? null
                : _pickProfilePhoto,
            customBorder: const CircleBorder(),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 104.w,
                  height: 104.w,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFEFF4FA),
                    border: Border.all(color: Colors.white, width: 4.w),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 20.r,
                        offset: Offset(0, 7.h),
                      ),
                    ],
                    image: _profilePhoto == null
                        ? null
                        : DecorationImage(
                            image: FileImage(_profilePhoto!),
                            fit: BoxFit.cover,
                          ),
                  ),
                  child: _profilePhoto != null
                      ? null
                      : _isPickingPhoto
                          ? Padding(
                              padding: EdgeInsets.all(39.r),
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.brand,
                              ),
                            )
                          : Icon(
                              Icons.person_rounded,
                              size: 44.sp,
                              color: AppColors.textSecondary,
                            ),
                ),
                Positioned(
                  right: 0,
                  bottom: 4.h,
                  child: Container(
                    width: 34.w,
                    height: 34.w,
                    decoration: BoxDecoration(
                      color: AppColors.brand,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3.w),
                    ),
                    child: Icon(
                      Icons.camera_alt_rounded,
                      size: 16.sp,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 10.h),
        Text(
          _profilePhoto == null ? 'Add profile photo' : 'Change photo',
          style: GoogleFonts.outfit(
            fontSize: 12.5.sp,
            fontWeight: FontWeight.w500,
            color: AppColors.brand,
          ),
        ),
      ],
    );
  }

  Widget _buildError(String message) => Text(
        message,
        style: GoogleFonts.outfit(
          fontSize: 11.5.sp,
          color: const Color(0xFFB42318),
        ),
      );

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFD),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24.w, 8.h, 24.w, 24.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: isSubmitting
                          ? null
                          : () {
                              if (Navigator.canPop(context)) {
                                Navigator.pop(context);
                              }
                            },
                      borderRadius: BorderRadius.circular(12.r),
                      child: Container(
                        padding: EdgeInsets.all(8.r),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 16.sp,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),

                    SizedBox(height: 28.h),

                    Text(
                      'Verify your profile',
                      style: GoogleFonts.outfit(
                        fontSize: 20.sp,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                        height: 1.2,
                        letterSpacing: -0.5,
                      ),
                    ),

                    SizedBox(height: 8.h),

                    Text(
                      'Add your professional identity and upload a medical license or certification for admin review.',
                      style: GoogleFonts.outfit(
                        fontSize: 12.5.sp,
                        height: 1.5,
                        color: AppColors.textSecondary,
                      ),
                    ),

                    SizedBox(height: 24.h),

                    Center(child: _buildProfilePhoto()),
                    if (_photoError != null) ...[
                      SizedBox(height: 8.h),
                      Center(child: _buildError(_photoError!)),
                    ],

                    SizedBox(height: 20.h),

                    TextField(
                      controller: _nameController,
                      focusNode: _nameFocus,
                      enabled: !isSubmitting,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      style: GoogleFonts.outfit(
                        fontSize: 14.sp,
                        color: AppColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Full name',
                        errorText: _nameError,
                        hintStyle: GoogleFonts.outfit(
                          color: AppColors.textSecondary,
                        ),
                        prefixIcon: Icon(
                          Icons.person_outline_rounded,
                          size: 20.sp,
                          color: AppColors.textSecondary,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14.w,
                          vertical: 15.h,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14.r),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14.r),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14.r),
                          borderSide: const BorderSide(
                            color:Color(0xFFE2E5E9),
                            width: 1.2,
                          ),
                        ),
                      ),
                    ),

                    SizedBox(height: 50.h),

                   Material(
  color: AppColors.brand.withValues(alpha: 0.06),
  borderRadius: BorderRadius.circular(14.r),
  child: InkWell(
    onTap: isSubmitting ? null : _pickDocument,
    borderRadius: BorderRadius.circular(14.r),
    child: Container(
      width: double.infinity,
      height: 54.h,
      padding: EdgeInsets.symmetric(horizontal: 14.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14.r),
       
      ),
      child: Row(
        children: [
          Container(
            width: 36.w,
            height: 36.w,
            decoration: BoxDecoration(
              color: AppColors.brand,
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(
              Icons.upload_file_rounded,
              size: 19.sp,
              color: Colors.white,
            ),
          ),

          SizedBox(width: 12.w),

          Expanded(
            child: Text(
              hasDocument ? 'Change Document' : 'Upload verification Document',
              style: GoogleFonts.outfit(
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),

          Icon(
            Icons.arrow_forward_ios_rounded,
            size: 15.sp,
            color: AppColors.brand,
          ),
        ],
      ),
    ),
  ),
),
                    if (doctorDocuments.isNotEmpty) ...[
                      SizedBox(height: 10.h),

                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: doctorDocuments.length,
                        separatorBuilder: (_, __) => SizedBox(height: 8.h),
                        itemBuilder: (context, index) {
                          final document = doctorDocuments[index];

                          return Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12.w,
                              vertical: 9.h,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 32.w,
                                  height: 32.w,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEE2E2),
                                    borderRadius: BorderRadius.circular(9.r),
                                  ),
                                  child: Icon(
                                    Icons.picture_as_pdf_rounded,
                                    color: const Color(0xFFDC2626),
                                    size: 17.sp,
                                  ),
                                ),

                                SizedBox(width: 12.w),

                                Expanded(
                                  child: Text(
                                    document.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.outfit(
                                      fontSize: 13.sp,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),

                                InkWell(
                                  onTap: isSubmitting
                                      ? null
                                      : () => _removeDocument(index),
                                  borderRadius: BorderRadius.circular(20.r),
                                  child: Container(
                                    padding: EdgeInsets.all(6.r),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF3F4F6),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: 15.sp,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Sticky bottom CTA
            Container(
              padding: EdgeInsets.fromLTRB(24.w, 16.h, 24.w, 16.h),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 20.r,
                    offset: Offset(0, -6.h),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  height: 56.h,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16.r),
                      gradient: _canSubmit
                          ? const LinearGradient(
                              colors: [
                                AppColors.brand,
                                AppColors.brandDark,
                              ],
                            )
                          : null,
                      boxShadow: _canSubmit
                          ? [
                              BoxShadow(
                                color: AppColors.brand.withValues(
                                  alpha: 0.35,
                                ),
                                blurRadius: 20.r,
                                offset: Offset(0, 10.h),
                              ),
                            ]
                          : [],
                    ),
                    child: ElevatedButton(
                      onPressed: _canSubmit ? _submitDocuments : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        disabledBackgroundColor: const Color(0xFFEEF1F5),
                        foregroundColor: Colors.white,
                        disabledForegroundColor: Colors.grey.shade400,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16.r),
                        ),
                      ),
                      child: isSubmitting
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 20.w,
                                  height: 20.w,
                                  child: const CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 12.w),
                                Text(
                                  'Submitting...',
                                  style: GoogleFonts.outfit(
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              'Submit for verification',
                              style: GoogleFonts.outfit(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w500,
                                color: _canSubmit
                                    ? Colors.white
                                    : Colors.grey.shade400,
                              ),
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
}
