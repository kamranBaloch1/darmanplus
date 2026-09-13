import 'dart:io';
import 'package:darmaan/core/models/user_model.dart';
import 'package:darmaan/core/theme/app_colors.dart';
import 'package:darmaan/presentation/home/account/account_screen.dart';
import 'package:darmaan/presentation/home/patient/repository/patient_repository.dart';
import 'package:darmaan/presentation/home/patient/screens/patient_appointment_history_screen.dart';
import 'package:flutter/material.dart';
import 'package:darmaan/widgets/app_icon.dart';
import 'package:darmaan/core/utils/app_error_message.dart';
import 'package:darmaan/core/utils/phone_number_formatter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:darmaan/widgets/app_shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';


class PatientProfileScreen extends StatefulWidget {
  const PatientProfileScreen({
    super.key,
    required this.onLogout,
    required this.isLoggingOut,
    this.refreshToken = 0,
  });

  final Future<void> Function() onLogout;
  final bool isLoggingOut;
  final int refreshToken;

  @override
  State<PatientProfileScreen> createState() => _PatientProfileScreenState();
}

class _PatientProfileScreenState extends State<PatientProfileScreen> {
  final PatientRepository _repository = PatientRepository();
  UserModel? _patient;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PatientProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final patient = await _repository.getPatientProfile();
      if (!mounted) return;
      setState(() {
        _patient = patient;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = AppErrorMessage.from(error);
        _loading = false;
      });
    }
  }

  Future<void> _edit() async {
    final patient = _patient;
    if (patient == null) return;
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) =>
          _EditPatientSheet(patient: patient, repository: _repository),
    );
    if (updated == true) await _load();
  }

  void _openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PatientAppointmentHistoryScreen()),
    );
  }

  void _openAccount() {
    final patient = _patient;
    if (patient == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AccountScreen(
          user: patient,
          onLogout: widget.onLogout,
          isLoggingOut: widget.isLoggingOut,
        ),
      ),
    );
  }

  Future<void> _openWhatsAppSupport() async {
    const phoneNumber = '923335540708';
    final messenger = ScaffoldMessenger.of(context);
    try {
      final opened = await launchUrl(
        Uri.parse('https://wa.me/$phoneNumber'),
        mode: LaunchMode.externalApplication,
      );
      if (opened) return;
    } catch (_) {}
    if (mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Unable to open WhatsApp.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor:  Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: Text(
          'My profile',
          style: GoogleFonts.outfit(
            fontSize: 20,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.4,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: _loading
          ? const _ProfileLoading()
          : _error != null
          ? _ProfileError(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.brand,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  _header(_patient!),
                  const SizedBox(height: 20),
                  _section(
                    title: 'Account',
                    children: [
                      _ActionTile(
                        icon: Icons.history_rounded,
                        title: 'Consultation history',
                        subtitle: 'Completed and cancelled appointments',
                        onTap: _openHistory,
                      ),
                      _ActionTile(
                        icon: Icons.support_agent_rounded,
                        title: 'Customer support',
                        subtitle: 'Chat with Darman on WhatsApp',
                        onTap: _openWhatsAppSupport,
                      ),
                      _ActionTile(
                        icon: Icons.manage_accounts_outlined,
                        title: 'Account settings',
                        subtitle: 'Manage or delete your account',
                        onTap: _openAccount,
                        isLast: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      'Darman · Patient account',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: AppColors.textSecondary.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _header(UserModel patient) {
    final hasImage = patient.profileImage?.trim().isNotEmpty == true;
    final hasPhone = patient.phone?.trim().isNotEmpty == true;
    final phone = formatLocalPhoneNumber(patient.phone);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 12, right: 12),
              child: IconButton(
                tooltip: 'Edit profile',
                onPressed: _edit,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFF1F3F5),
                  foregroundColor: AppColors.textPrimary,
                ),
                icon: const AppIcon(Icons.edit_rounded, size: 18),
              ),
            ),
          ),
          const SizedBox(height: 2),
          GestureDetector(
            onTap: hasImage ? () => _showProfilePhoto(patient.profileImage!) : null,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE7E9EC)),
              ),
              child: CircleAvatar(
                radius: 50,
                backgroundColor: const Color(0xFFF1F3F5),
                backgroundImage: hasImage
                    ? CachedNetworkImageProvider(patient.profileImage!)
                    : null,
                child: hasImage
                    ? null
                    : Text(
                        patient.name.trim().isEmpty
                            ? 'P'
                            : patient.name.trim()[0].toUpperCase(),
                        style: GoogleFonts.outfit(
                          fontSize: 26,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
            child: Column(
              children: [
                Text(
                  patient.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 18.5,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.3,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (hasPhone) const SizedBox(height: 14),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (hasPhone)
                      _HeaderDetailChip(
                        icon: Icons.phone_outlined,
                        value: phone,
                        verified: true,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showProfilePhoto(String imageUrl) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (dialogContext) => Dialog(
        elevation: 0,
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.contain,
                    progressIndicatorBuilder: (_, __, ___) => const SizedBox(
                            width: 220,
                            height: 220,
                            child: Center(
                              child: CircularProgressIndicator(color: Colors.white),
                            ),
                          ),
                    errorWidget: (_, _, _) => const SizedBox(
                      width: 240,
                      height: 240,
                      child: Center(
                        child: AppIcon(
                          Icons.broken_image_outlined,
                          size: 44,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: IconButton(
                onPressed: () => Navigator.pop(dialogContext),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.55),
                  foregroundColor: Colors.white,
                ),
                icon: const AppIcon(Icons.close_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section({String? title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
            child: Text(
              title.toUpperCase(),
              style: GoogleFonts.outfit(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.4,
                color: AppColors.textSecondary.withValues(alpha: 0.75),
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}

/// A compact verified-phone chip shown in the profile header.
class _HeaderDetailChip extends StatelessWidget {
  const _HeaderDetailChip({
    required this.icon,
    required this.value,
    this.verified = false,
  });

  final IconData icon;
  final String value;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7F9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(icon, size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (verified) ...[
            const SizedBox(width: 5),
            const AppIcon(
              Icons.verified_rounded,
              size: 13,
              color: Color(0xFF18A957),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
    this.isLast = false,
    this.trailing,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool destructive;
  final bool isLast;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: destructive
                        ? const Color(0xFFFFF0EE)
                        : const Color(0xFFF1F4F7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: AppIcon(
                    icon,
                    size: 17,
                    color: destructive
                        ? const Color(0xFFB42318)
                        : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.outfit(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: destructive
                              ? const Color(0xFFB42318)
                              : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 10.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                trailing ??
                    AppIcon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: AppColors.textSecondary.withValues(alpha: 0.55),
                    ),
              ],
            ),
          ),
        ),
      ),
      if (!isLast)
        const Padding(
          padding: EdgeInsets.only(left: 62),
          child: Divider(height: 1, color: Color(0xFFF0F1F3)),
        ),
    ],
  );
}

class _ProfileLoading extends StatelessWidget {
  const _ProfileLoading();

  @override
  Widget build(BuildContext context) {
    Widget block({double height = 16, double width = double.infinity}) {
      return Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: const Color(0xFFEDEFF2),
          borderRadius: BorderRadius.circular(8),
        ),
      );
    }

    return AppShimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 32,
                backgroundColor: Color(0xFFEDEFF2),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    block(height: 15, width: 140),
                    const SizedBox(height: 8),
                    block(height: 12, width: 100),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
          height: 200,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        ],
      ),
    );
  }
}

class _EditPatientSheet extends StatefulWidget {
  const _EditPatientSheet({required this.patient, required this.repository});
  final UserModel patient;
  final PatientRepository repository;

  @override
  State<_EditPatientSheet> createState() => _EditPatientSheetState();
}

class _EditPatientSheetState extends State<_EditPatientSheet> {
  late final TextEditingController _name;
  String? _gender;
  DateTime? _dateOfBirth;
  File? _croppedPhoto;
  bool _saving = false;
  bool _cropping = false;

  static const _genders= ['Male', 'Female'];

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.patient.name);
    _gender = widget.patient.gender;
    _dateOfBirth = widget.patient.dateOfBirth;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.repository.updatePatientProfile(
        name: _name.text,
        phone: widget.patient.phone,
        gender: _gender,
        dateOfBirth: _dateOfBirth,
        profilePhoto: _croppedPhoto,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppErrorMessage.from(error)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFB42318),
        ),
      );
      setState(() => _saving = false);
    }
  }

  Future<void> _pickAndCropPhoto() async {
    if (_cropping || _saving) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
      maxWidth: 2400,
      maxHeight: 2400,
    );
    if (picked == null || !mounted) return;
    setState(() => _cropping = true);
    try {
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
        setState(() => _croppedPhoto = File(cropped.path));
      }
    } finally {
      if (mounted) setState(() => _cropping = false);
    }
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.outfit(
        fontSize: 13,
        color: AppColors.textSecondary,
      ),
      prefixIcon: AppIcon(icon, size: 19, color: AppColors.textSecondary),
      filled: true,
      fillColor: const Color(0xFFF6F7F9),
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.brand, width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD8DBDF),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Edit personal details',
                style: GoogleFonts.outfit(
                  fontSize: 19,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.3,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Keep your information accurate and up to date.',
                style: GoogleFonts.outfit(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: GestureDetector(
                  onTap: _pickAndCropPhoto,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFE1E4E8)),
                        ),
                        child: CircleAvatar(
                          radius: 42,
                          backgroundColor: const Color(0xFFF1F3F5),
                          backgroundImage: _croppedPhoto != null
                              ? FileImage(_croppedPhoto!)
                              : widget.patient.profileImage?.trim().isNotEmpty == true
                                  ? CachedNetworkImageProvider(
                                      widget.patient.profileImage!,
                                    )
                                  : null,
                          child: _cropping
                              ? const CircularProgressIndicator(strokeWidth: 2)
                              : (_croppedPhoto == null &&
                                      widget.patient.profileImage?.trim().isNotEmpty != true)
                                  ? AppIcon(Icons.person_rounded,
                                      size: 34, color: AppColors.textSecondary)
                                  : null,
                        ),
                      ),
                      Positioned(
                        right: -3,
                        bottom: 1,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: AppColors.brand,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const AppIcon(Icons.photo_camera_rounded,
                            size: 15, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
             
              const SizedBox(height: 14),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                style: GoogleFonts.outfit(fontSize: 14, color: Colors.black),
                decoration: _decoration(
                  'Full name',
                  Icons.person_outline_rounded,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Gender',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: _genders.map((value) {
                  final selected = _gender == value;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: value == _genders.last ? 0 : 8,
                      ),
                      child: GestureDetector(
                        onTap: () => setState(() => _gender = value),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.brand.withValues(alpha: 0.1)
                                : const Color(0xFFF6F7F9),
                            borderRadius: BorderRadius.circular(12),
                           
                          ),
                          child: Text(
                            value,
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: selected
                                  ? AppColors.brand
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    builder: (context, child) {
                      final theme = Theme.of(context);
                      return Theme(
                        data: theme.copyWith(
                          colorScheme: theme.colorScheme.copyWith(
                            primary: AppColors.brand,
                            onPrimary: Colors.white,
                            onSurface: Colors.black,
                          ),
                        ),
                        child: child!,
                      );
                    },
                    initialDate: _dateOfBirth ?? DateTime(2000),
                    firstDate: DateTime(1900),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null && mounted) {
                    setState(() => _dateOfBirth = picked);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 15,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F7F9),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      AppIcon(
                        Icons.cake_outlined,
                        size: 19,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _dateOfBirth == null
                            ? 'Date of birth'
                            : DateFormat('dd MMM yyyy').format(_dateOfBirth!),
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          color: _dateOfBirth == null
                              ? AppColors.textSecondary
                              : Colors.black,
                        ),
                      ),
                      const Spacer(),
                      AppIcon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: AppColors.textSecondary.withValues(alpha: 0.6),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    elevation: 0,
                 backgroundColor: const Color(0xFFF2F4F6),
                    disabledBackgroundColor: AppColors.brand.withValues(
                      alpha: 0.5,
                    ),
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
                          'Save changes',
                          style: GoogleFonts.outfit(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.black
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
}

class _ProfileError extends StatelessWidget {
  const _ProfileError({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: Color(0xFFF1F4F7),
              shape: BoxShape.circle,
            ),
            child: AppIcon(
              Icons.person_off_outlined,
              size: 32,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Couldn\u2019t load your profile',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 12.5,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 44,
            child: FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                elevation: 0,
                backgroundColor: AppColors.brand,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Try again',
                style: GoogleFonts.outfit(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
