import 'dart:io';

import 'package:darmaan/core/constants/images.dart';
import 'package:darmaan/core/theme/app_colors.dart';
import 'package:darmaan/core/utils/app_error_message.dart';
import 'package:darmaan/core/utils/auth_navigator.dart';
import 'package:darmaan/presentation/home/patient/repository/patient_repository.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PatientProfileSetupScreen extends StatefulWidget {
  const PatientProfileSetupScreen({super.key});

  @override
  State<PatientProfileSetupScreen> createState() =>
      _PatientProfileSetupScreenState();
}

class _PatientProfileSetupScreenState extends State<PatientProfileSetupScreen> {
  final PatientRepository _repository = PatientRepository();
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();

  File? _photo;
  String? _existingPhotoUrl;
  String? _gender;
  bool _pickingPhoto = false;
  bool _saving = false;
  String? _nameError;
  String? _photoError;
  String? _genderError;

  bool get _isValid =>
      _nameController.text.trim().length >= 2 &&
      (_photo != null || _existingPhotoUrl?.trim().isNotEmpty == true) &&
      _gender != null;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() {
      if (!mounted) return;
      setState(() {
        if (_nameController.text.trim().length >= 2) _nameError = null;
      });
    });
    _loadExistingProfile();
  }

  Future<void> _loadExistingProfile() async {
    try {
      final patient = await _repository.getPatientProfile();
      if (!mounted) return;
      setState(() {
        if (patient.name.trim().toLowerCase() != 'user') {
          _nameController.text = patient.name.trim();
        }
        final savedGender = patient.gender?.trim();
        _gender = savedGender == null || savedGender.isEmpty
            ? null
            : '${savedGender[0].toUpperCase()}'
                '${savedGender.substring(1).toLowerCase()}';
        _existingPhotoUrl = patient.profileImage;
      });
    } catch (_) {
      // A new patient starts with an intentionally empty form.
    }
  }

  Future<void> _pickPhoto() async {
    if (_pickingPhoto || _saving) return;
    setState(() {
      _pickingPhoto = true;
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
        compressQuality: 85,
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
        setState(() => _photo = File(cropped.path));
      }
    } catch (error) {
      if (mounted) _showError(AppErrorMessage.from(error));
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameController.text.trim();
    setState(() {
      _nameError = name.length < 2 ? 'Enter your full name' : null;
      _photoError = _photo == null &&
              _existingPhotoUrl?.trim().isNotEmpty != true
          ? 'Add a profile photo'
          : null;
      _genderError = _gender == null ? 'Select your gender' : null;
    });
    if (!_isValid) return;

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      final authUser = Supabase.instance.client.auth.currentUser;
      final verifiedPhone = (authUser?.phone ??
              authUser?.userMetadata?['verified_phone']?.toString())
          ?.trim();
      await _repository.updatePatientProfile(
        name: name,
        phone: verifiedPhone,
        gender: _gender,
        profilePhoto: _photo,
      );
      if (!mounted) return;
      await AuthNavigator.goToCorrectScreen(context);
    } catch (error) {
      if (!mounted) return;
      _showError(AppErrorMessage.from(error));
      setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF20252B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                        
                          const SizedBox(height: 30),
                          Text(
                            'Complete your profile',
                            style: GoogleFonts.outfit(
                              fontSize: 22,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -.5,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        
                          const SizedBox(height: 28),
                          Center(child: _buildPhoto()),
                          if (_photoError != null) ...[
                            const SizedBox(height: 8),
                            Center(child: _errorText(_photoError!)),
                          ],
                          const SizedBox(height: 30),
                          _label('Full name'),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _nameController,
                            focusNode: _nameFocus,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.done,
                            style: GoogleFonts.outfit(
                              fontSize: 14.5,
                              color: AppColors.textPrimary,
                            ),
                            decoration: _inputDecoration(
                              hint: 'Enter your full name',
                              icon: Icons.person_outline_rounded,
                              error: _nameError,
                            ),
                          ),
                          const SizedBox(height: 22),
                          _label('Gender'),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(child: _genderOption('Male')),
                              const SizedBox(width: 10),
                              Expanded(child: _genderOption('Female')),
                            
                            ],
                          ),
                          if (_genderError != null) ...[
                            const SizedBox(height: 8),
                            _errorText(_genderError!),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        elevation: 0,
                        backgroundColor: AppColors.brand,
                        disabledBackgroundColor:
                            AppColors.brand.withValues(alpha: .55),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Save and continue',
                              style: GoogleFonts.outfit(
                                fontSize: 14,
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
      ),
    );
  }

  Widget _buildPhoto() {
    return Semantics(
      button: true,
      label: 'Choose profile photo',
      child: InkWell(
        onTap: _pickingPhoto ? null : _pickPhoto,
        customBorder: const CircleBorder(),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFEFF4FA),
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .08),
                    blurRadius: 20,
                    offset: const Offset(0, 7),
                  ),
                ],
                image: _photo != null
                    ? DecorationImage(image: FileImage(_photo!), fit: BoxFit.cover)
                    : _existingPhotoUrl?.trim().isNotEmpty == true
                        ? DecorationImage(
                            image: NetworkImage(_existingPhotoUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
              ),
              child: _photo != null ||
                      _existingPhotoUrl?.trim().isNotEmpty == true
                  ? null
                  : _pickingPhoto
                      ? const Padding(
                          padding: EdgeInsets.all(42),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.person_rounded,
                          size: 48, color: AppColors.textSecondary),
            ),
            Positioned(
              right: 1,
              bottom: 5,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.brand,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: const Icon(Icons.camera_alt_rounded,
                    size: 16, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _genderOption(String value) {
    final selected = _gender == value;
    return Material(
      color: selected
          ? AppColors.brand.withValues(alpha: .09)
          : Colors.white,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: _saving
            ? null
            : () => setState(() {
                  _gender = value;
                  _genderError = null;
                }),
        borderRadius: BorderRadius.circular(13),
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected ? AppColors.brand : AppColors.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w500 : FontWeight.w500,
              color: selected ? AppColors.brand : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: GoogleFonts.outfit(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
      );

  Widget _errorText(String text) => Text(
        text,
        style: GoogleFonts.outfit(
          fontSize: 11.5,
          color: const Color(0xFFB42318),
        ),
      );

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    String? error,
  }) {
    return InputDecoration(
      hintText: hint,
      errorText: error,
      hintStyle: GoogleFonts.outfit(color: AppColors.textSecondary),
      prefixIcon: Icon(icon, size: 20, color: AppColors.textSecondary),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.brand, width: 1.4),
      ),
    );
  }
}
