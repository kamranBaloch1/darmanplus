import 'dart:async';

import 'package:darmaan/core/models/user_model.dart';
import 'package:darmaan/core/theme/app_colors.dart';
import 'package:darmaan/core/utils/app_error_message.dart';
import 'package:darmaan/core/utils/phone_number_formatter.dart';
import 'package:darmaan/presentation/auth/repository/login/auth_repository.dart';
import 'package:darmaan/presentation/auth/screens/login/splash_screen.dart';
import 'package:darmaan/presentation/home/account/account_screen.dart';
import 'package:darmaan/presentation/home/doctor/repository/doctor_profile_repository.dart';
import 'package:darmaan/presentation/home/doctor/screens/edit_doctor_profile_screen.dart';
import 'package:darmaan/presentation/home/doctor/screens/doctor_appointments_screen.dart';
import 'package:darmaan/presentation/home/patient/screens/doctor_reviews_screen.dart';
import 'package:darmaan/widgets/app_shimmer.dart';
import 'package:darmaan/widgets/app_icon.dart';
import 'package:darmaan/widgets/video_dilog.dart';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';

class DoctorProfileScreen extends StatefulWidget {
  const DoctorProfileScreen({super.key, this.onCompletionChanged});

  final ValueChanged<bool>? onCompletionChanged;

  @override
  State<DoctorProfileScreen> createState() => _DoctorProfileScreenState();
}

class _DoctorProfileScreenState extends State<DoctorProfileScreen> {
  final DoctorProfileRepository _repository = DoctorProfileRepository();
  final AuthRepository _loginRepository = AuthRepository();

  UserModel? _user;
  bool isLoading = true;
  String? error;
  bool _isLoggingOut = false;

  static const Color _bg = Color(0xFFFAFBFD);
  static const Color _success = Color(0xFF10B981);

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      final user = await _repository.getDoctorProfile();
      if (!mounted) return;
      setState(() {
        _user = user;
        isLoading = false;
      });
      widget.onCompletionChanged?.call(
        user.isProfileCompleted && user.doctorProfileCompletion >= 1,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = AppErrorMessage.from(e);
        isLoading = false;
      });
    }
  }

  Future<void> _goToEdit() async {
    if (_user == null) return;

    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditDoctorProfileScreen(currentUser: _user!),
      ),
    );

    if (updated == true) {
      _loadProfile();
    }
  }

  void _openReviews() {
    if (_user == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DoctorReviewsScreen(doctor: _user!)),
    );
  }

  void _openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const DoctorAppointmentsScreen(
          historyOnly: true,
          showBackButton: true,
        ),
      ),
    );
  }

  void _openAccount() {
    final user = _user;
    if (user == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AccountScreen(
          user: user,
          onLogout: _logout,
          isLoggingOut: _isLoggingOut,
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

  void _showProfilePhoto(String imageUrl) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (dialogContext) => Dialog(
        elevation: 0,
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 40.h),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20.r),
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.contain,
                    errorWidget: (_, _, _) => const SizedBox(
                      width: 240,
                      height: 240,
                      child: AppIcon(
                        Icons.broken_image_outlined,
                        color: Colors.white70,
                        size: 44,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(dialogContext),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
              ),
              icon: const AppIcon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }

  void _openIntroVideo(String url) {
    showDoctorIntroDialog(
      context,
      url: url,
      doctorName: _user?.name ?? 'Doctor',
      doctor: _user,
    );
  }

  Future<void> _openDocument(String path) async {
    final String url;
    try {
      url = _repository.getDocumentPublicUrl(path);
    } catch (e) {
      _showSnack('Could not open document');
      debugPrint('Failed to resolve public URL for $path: $e');
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      _showSnack('Invalid document link');
      debugPrint('Document open failed — bad URL: $url');
      return;
    }

    try {
      final canOpenExternally = await canLaunchUrl(uri);
      if (canOpenExternally) {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return;
      }

      final launchedInApp = await launchUrl(
        uri,
        mode: LaunchMode.inAppBrowserView,
      );
      if (!launchedInApp) {
        _showSnack('Could not open document');
        debugPrint('All launch modes failed for: $url');
      }
    } catch (e) {
      _showSnack('Could not open document');
      debugPrint('Document open threw: $e');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.outfit(fontSize: 13.sp)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.black87,
      ),
    );
  }

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .52),
      builder: (dialogContext) => Dialog(
        elevation: 0,
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Container(
          padding: EdgeInsets.fromLTRB(22.w, 25.h, 22.w, 18.h),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22.r),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58.w,
                height: 58.w,
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F4F6),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFE6E9ED)),
                ),
                child: const AppIcon(
                  Icons.logout_rounded,
                  color: Color(0xFF344054),
                  size: 27,
                ),
              ),
              SizedBox(height: 17.h),
              Text(
                'Sign out?',
                style: GoogleFonts.outfit(
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                'You can sign back in anytime to manage appointments, messages, and your profile.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 13.sp,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
              SizedBox(height: 22.h),
              SizedBox(
                width: double.infinity,
                height: 47.h,
                child: FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  style: FilledButton.styleFrom(
                    elevation: 0,
                    backgroundColor: const Color(0xFFF2F4F6),
                    foregroundColor: AppColors.textPrimary,
                    disabledBackgroundColor: const Color(0xFFF2F4F6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13.r),
                    ),
                  ),
                  child: Text(
                    'Sign out',
                    style: GoogleFonts.outfit(
                      fontSize: 13.5.sp,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 6.h),
              SizedBox(
                width: double.infinity,
                height: 42.h,
                child: TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(
                    'Stay signed in',
                    style: GoogleFonts.outfit(
                      fontSize: 13.sp,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isLoggingOut = true);
    try {
      await _loginRepository.logout();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const SplashScreen()),
        (_) => false,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoggingOut = false);
      _showSnack(AppErrorMessage.from(error));
    }
  }

  String _formatFee(double fee) {
    return fee % 1 == 0 ? fee.toStringAsFixed(0) : fee.toStringAsFixed(2);
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: true,
      title: Text(
        'My profile',
        style: GoogleFonts.outfit(
          fontSize: 17.sp,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: _buildAppBar(),
        body: const AppProfileShimmer(),
      );
    }

    if (error != null || _user == null) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: _buildAppBar(),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  Icons.wifi_off_rounded,
                  size: 32.sp,
                  color: Colors.grey.shade400,
                ),
                SizedBox(height: 12.h),
                Text(
                  error ?? 'Could not load profile',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(color: AppColors.textSecondary),
                ),
                SizedBox(height: 16.h),
                ElevatedButton(
                  onPressed: _loadProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: EdgeInsets.symmetric(
                      horizontal: 24.w,
                      vertical: 12.h,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                  child: Text(
                    'Retry',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final user = _user!;
    final completion = user.doctorProfileCompletion;
    final completionPercent = (completion * 100).round();
    final isComplete = completion >= 1.0;
    final hasFee = user.consultationFee != null && user.consultationFee! > 0;

    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        color: AppColors.brand,
        onRefresh: _loadProfile,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: SizedBox(height: 0.h)),

            SliverToBoxAdapter(
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: EdgeInsets.only(right: 20.w, bottom: 4.h),
                  child: IconButton(
                    tooltip: 'Edit profile',
                    onPressed: _goToEdit,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.textPrimary,
                    ),
                    icon: AppIcon(Icons.edit_rounded, size: 18.sp),
                  ),
                ),
              ),
            ),

            // Avatar (with an edit badge tucked into its bottom-right corner)
            SliverToBoxAdapter(
              child: Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 95.w,
                      height: 95.w,
                      padding: EdgeInsets.all(3.r),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.brand, width: 2),
                      ),
                      child: GestureDetector(
                        onTap: user.profileImage == null
                            ? null
                            : () => _showProfilePhoto(user.profileImage!),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.brand.withValues(alpha: 0.08),
                            image: user.profileImage != null
                                ? DecorationImage(
                                    image: CachedNetworkImageProvider(
                                      user.profileImage!,
                                    ),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: user.profileImage == null
                              ? AppIcon(
                                  Icons.person_rounded,
                                  size: 36.sp,
                                  color: AppColors.brand,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(child: SizedBox(height: 14.h)),

            // Name, specialization, fee, verified badge
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            user.name,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              fontSize: 18.sp,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (user.isDoctorVerified) ...[
                          SizedBox(width: 5.w),
                          AppIcon(
                            Icons.verified_rounded,
                            size: 16.sp,
                            color: AppColors.brand,
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: 3.h),
                    Text(
                      user.specialization ?? 'Specialization not set',
                      style: GoogleFonts.outfit(
                        fontSize: 13.sp,
                        color: user.specialization != null
                            ? AppColors.textSecondary
                            : Colors.grey.shade400,
                      ),
                    ),

                    if (user.phone?.trim().isNotEmpty == true) ...[
                      SizedBox(height: 9.h),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 11.w,
                          vertical: 6.h,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F3F5),
                          borderRadius: BorderRadius.circular(20.r),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppIcon(
                              Icons.phone_outlined,
                              size: 13.sp,
                              color: AppColors.textSecondary,
                            ),
                            SizedBox(width: 6.w),
                            Text(
                              formatLocalPhoneNumber(user.phone),
                              style: GoogleFonts.outfit(
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            SizedBox(width: 5.w),
                            AppIcon(
                              Icons.verified_rounded,
                              size: 13.sp,
                              color: AppColors.brand,
                            ),
                          ],
                        ),
                      ),
                    ],

                    SizedBox(height: 6.h),

                    // Consultation fee — plain text, no card chrome.
                    GestureDetector(
                      onTap: hasFee ? null : _goToEdit,
                      child: Text(
                        hasFee
                            ? 'Rs. ${_formatFee(user.consultationFee!)} per consultation'
                            : 'Consultation fee not set',
                        style: GoogleFonts.outfit(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w500,
                          color: hasFee
                              ? AppColors.textPrimary
                              : Colors.grey.shade400,
                        ),
                      ),
                    ),

                    SizedBox(height: 20.h),

                    // Completion card
                    _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  AppIcon(
                                    isComplete
                                        ? Icons.task_alt_rounded
                                        : Icons.pending_actions_rounded,
                                    size: 16.sp,
                                    color: isComplete
                                        ? AppColors.brand
                                        : _success,
                                  ),
                                  SizedBox(width: 8.w),
                                  Text(
                                    isComplete
                                        ? 'Profile complete'
                                        : 'Profile completion',
                                    style: GoogleFonts.outfit(
                                      fontSize: 13.5.sp,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                '$completionPercent%',
                                style: GoogleFonts.outfit(
                                  fontSize: 13.5.sp,
                                  fontWeight: FontWeight.w500,
                                  color: isComplete
                                      ? AppColors.brand
                                      : _success,
                                ),
                              ),
                            ],
                          ),

                          SizedBox(height: 12.h),

                          ClipRRect(
                            borderRadius: BorderRadius.circular(10.r),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: completion),
                              duration: const Duration(milliseconds: 800),
                              curve: Curves.easeOutCubic,
                              builder: (context, value, _) {
                                return LinearProgressIndicator(
                                  value: value,
                                  minHeight: 7.h,
                                  backgroundColor: const Color(0xFFEEF1F5),
                                  valueColor: AlwaysStoppedAnimation(
                                    isComplete ? AppColors.brand : _success,
                                  ),
                                );
                              },
                            ),
                          ),

                          if (!isComplete) ...[
                            SizedBox(height: 14.h),
                            Wrap(
                              spacing: 8.w,
                              runSpacing: 8.h,
                              children: [
                                _ChecklistChip(
                                  label: 'Photo',
                                  isDone: user.profileImage != null,
                                ),
                                _ChecklistChip(
                                  label: 'Specialization',
                                  isDone:
                                      user.specialization != null &&
                                      user.specialization!.isNotEmpty,
                                ),
                                _ChecklistChip(
                                  label: 'Title',
                                  isDone:
                                      user.title != null &&
                                      user.title!.trim().isNotEmpty,
                                ),
                                _ChecklistChip(
                                  label: 'Experience',
                                  isDone:
                                      user.experienceYears != null &&
                                      user.experienceYears! > 0,
                                ),
                                _ChecklistChip(
                                  label: 'Gender',
                                  isDone:
                                      user.gender != null &&
                                      user.gender!.isNotEmpty,
                                ),
                                _ChecklistChip(
                                  label: 'Consultation fee',
                                  isDone: hasFee,
                                ),
                              ],
                            ),
                            SizedBox(height: 14.h),
                            SizedBox(
                              width: double.infinity,
                              height: 46.h,
                              child: ElevatedButton(
                                onPressed: _goToEdit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.brand,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(13.r),
                                  ),
                                ),
                                child: Text(
                                  'Complete your profile',
                                  style: GoogleFonts.outfit(
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    SizedBox(height: 12.h),

                    if (user.introVideoUrl != null) ...[
                      SizedBox(height: 12.h),
                      _Card(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16.w,
                          vertical: 14.h,
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14.r),
                          onTap: () => _openIntroVideo(user.introVideoUrl!),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'introduction',
                                  style: GoogleFonts.outfit(
                                    fontSize: 13.5.sp,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              Container(
                                width: 34.w,
                                height: 34.w,
                                decoration: BoxDecoration(
                                  color: AppColors.brand,
                                  shape: BoxShape.circle,
                                ),
                                child: AppIcon(
                                  Icons.play_arrow_rounded,
                                  size: 19.sp,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    SizedBox(height: 12.h),

                    _Card(
                      padding: EdgeInsets.zero,
                      child: InkWell(
                        onTap: _openReviews,
                        borderRadius: BorderRadius.circular(18.r),
                        child: Padding(
                          padding: EdgeInsets.all(16.w),
                          child: Row(
                            children: [
                              Container(
                                width: 42.w,
                                height: 42.w,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF7DF),
                                  borderRadius: BorderRadius.circular(12.r),
                                ),
                                child: AppIcon(
                                  Icons.star_rounded,
                                  color: const Color(0xFFFFB300),
                                  size: 21.sp,
                                ),
                              ),
                              SizedBox(width: 12.w),
                              Expanded(
                                child: Text(
                                  'Patient reviews',
                                  style: GoogleFonts.outfit(
                                    fontSize: 13.5.sp,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              AppIcon(
                                Icons.chevron_right_rounded,
                                color: Colors.grey.shade400,
                                size: 20.sp,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    SizedBox(height: 12.h),

                    _Card(
                      padding: EdgeInsets.zero,
                      child: InkWell(
                        onTap: _openHistory,
                        borderRadius: BorderRadius.circular(18.r),
                        child: Padding(
                          padding: EdgeInsets.all(16.w),
                          child: Row(
                            children: [
                              Container(
                                width: 42.w,
                                height: 42.w,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAF3FF),
                                  borderRadius: BorderRadius.circular(12.r),
                                ),
                                child: AppIcon(
                                  Icons.history_rounded,
                                  color: AppColors.brand,
                                  size: 21.sp,
                                ),
                              ),
                              SizedBox(width: 12.w),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Consultation history',
                                      style: GoogleFonts.outfit(
                                        fontSize: 13.5.sp,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    SizedBox(height: 2.h),
                                    Text(
                                      'Completed and cancelled consultations',
                                      style: GoogleFonts.outfit(
                                        fontSize: 10.5.sp,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              AppIcon(
                                Icons.chevron_right_rounded,
                                color: Colors.grey.shade400,
                                size: 20.sp,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    SizedBox(height: 12.h),

                    _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Verification documents',
                            style: GoogleFonts.outfit(
                              fontSize: 13.5.sp,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          SizedBox(height: 12.h),
                          if (user.doctorDocuments.isEmpty)
                            Text(
                              'No documents uploaded',
                              style: GoogleFonts.outfit(
                                fontSize: 12.5.sp,
                                color: AppColors.textSecondary,
                              ),
                            )
                          else
                            ...user.doctorDocuments.asMap().entries.map((
                              entry,
                            ) {
                              final isLast =
                                  entry.key == user.doctorDocuments.length - 1;

                              return Padding(
                                padding: EdgeInsets.only(
                                  bottom: isLast ? 0 : 10.h,
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12.r),
                                  onTap: () => _openDocument(entry.value),
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      vertical: 4.h,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 34.w,
                                          height: 34.w,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFEF2F2),
                                            borderRadius: BorderRadius.circular(
                                              10.r,
                                            ),
                                          ),
                                          child: AppIcon(
                                            Icons.picture_as_pdf_rounded,
                                            color: const Color(0xFFEF4444),
                                            size: 16.sp,
                                          ),
                                        ),
                                        SizedBox(width: 12.w),
                                        Expanded(
                                          child: Text(
                                            'Document ${entry.key + 1}',
                                            style: GoogleFonts.outfit(
                                              fontSize: 12.5.sp,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                        ),
                                        AppIcon(
                                          user.isDoctorVerified
                                              ? Icons.verified_rounded
                                              : Icons.hourglass_top_rounded,
                                          size: 17.sp,
                                          color: user.isDoctorVerified
                                              ? _success
                                              : const Color(0xFFF59E0B),
                                        ),
                                        SizedBox(width: 8.w),
                                        AppIcon(
                                          Icons.chevron_right_rounded,
                                          size: 18.sp,
                                          color: Colors.grey.shade400,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                        ],
                      ),
                    ),

                    SizedBox(height: 12.h),

                    _buildSupportCard(),

                    SizedBox(height: 12.h),

                    _buildAccountCard(),

                    SizedBox(height: 28.h),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountCard() {
    return _Card(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: _openAccount,
        borderRadius: BorderRadius.circular(18.r),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 15.h),
          child: Row(
            children: [
              Container(
                width: 38.w,
                height: 38.w,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F4F7),
                  borderRadius: BorderRadius.circular(11.r),
                ),
                child: const AppIcon(
                  Icons.manage_accounts_outlined,
                  color: AppColors.textSecondary,
                  size: 19,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Account settings',
                      style: GoogleFonts.outfit(
                        fontSize: 13.5.sp,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      'Manage or delete your account',
                      style: GoogleFonts.outfit(
                        fontSize: 10.5.sp,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              AppIcon(
                Icons.chevron_right_rounded,
                size: 20.sp,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSupportCard() {
    return _Card(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: _openWhatsAppSupport,
        borderRadius: BorderRadius.circular(18.r),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 15.h),
          child: Row(
            children: [
              Container(
                width: 38.w,
                height: 38.w,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F4F7),
                  borderRadius: BorderRadius.circular(11.r),
                ),
                child: const AppIcon(
                  Icons.support_agent_rounded,
                  color: AppColors.textSecondary,
                  size: 19,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Customer support',
                      style: GoogleFonts.outfit(
                        fontSize: 13.5.sp,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      'Chat with Darman on WhatsApp',
                      style: GoogleFonts.outfit(
                        fontSize: 10.5.sp,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              AppIcon(
                Icons.open_in_new_rounded,
                size: 18.sp,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;

  const _Card({required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? EdgeInsets.all(16.w),
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
      child: child,
    );
  }
}

class _ChecklistChip extends StatelessWidget {
  final String label;
  final bool isDone;

  const _ChecklistChip({required this.label, required this.isDone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: isDone
            ? const Color(0xFF10B981).withValues(alpha: 0.08)
            : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(
            isDone ? Icons.check_rounded : Icons.circle_outlined,
            size: 12.sp,
            color: isDone ? const Color(0xFF10B981) : Colors.grey.shade400,
          ),
          SizedBox(width: 4.w),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 11.sp,
              fontWeight: FontWeight.w500,
              color: isDone ? const Color(0xFF059669) : Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}

/// A polished, fullscreen-feeling modal video player with professional
/// controls: scrubber, elapsed/remaining time, play/pause, mute, and a
/// 10-second skip forward/back. Sizes itself to the video's real aspect
/// ratio, capped so it always fits comfortably on screen.
class _VideoPlayerDialog extends StatefulWidget {
  final String videoUrl;

  const _VideoPlayerDialog({required this.videoUrl});

  @override
  State<_VideoPlayerDialog> createState() => _VideoPlayerDialogState();
}

class _VideoPlayerDialogState extends State<_VideoPlayerDialog> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _showControls = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final uri = Uri.tryParse(widget.videoUrl.trim());
    if (uri == null || !uri.hasScheme) {
      if (mounted) setState(() => _hasError = true);
      return;
    }

    VideoPlayerController? candidate;
    try {
      candidate = VideoPlayerController.networkUrl(uri);
      candidate.addListener(_onTick);
      await candidate.initialize().timeout(const Duration(seconds: 25));
      await candidate.play();
      if (!mounted) {
        await candidate.dispose();
        return;
      }
      setState(() {
        _controller = candidate;
        _isInitialized = true;
        _hasError = false;
      });
      _scheduleHide();
      candidate = null;
    } catch (_) {
      candidate?.removeListener(_onTick);
      await candidate?.dispose();
      if (!mounted) return;
      setState(() => _hasError = true);
    }
  }

  void _onTick() {
    final controller = _controller;
    if (controller?.value.hasError == true && !_hasError && mounted) {
      setState(() => _hasError = true);
      return;
    }
    if (mounted) setState(() {});
  }

  void _scheduleHide() {
    final controller = _controller;
    if (controller == null) return;
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (controller.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHide();
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null || !_isInitialized || _hasError) return;
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
        _hideTimer?.cancel();
      } else {
        controller.play();
        _scheduleHide();
      }
      _showControls = true;
    });
  }

  void _seekBy(Duration offset) {
    final controller = _controller;
    if (controller == null || !_isInitialized || _hasError) return;
    final target = controller.value.position + offset;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > controller.value.duration
              ? controller.value.duration
              : target);
    controller.seekTo(clamped);
    _scheduleHide();
  }

  void _toggleMute() {
    final controller = _controller;
    if (controller == null || !_isInitialized || _hasError) return;
    setState(() {
      controller.setVolume(controller.value.volume == 0 ? 1 : 0);
    });
  }

  Future<void> _retryVideo() async {
    final previous = _controller;
    setState(() {
      _controller = null;
      _hasError = false;
      _isInitialized = false;
    });
    previous?.removeListener(_onTick);
    await previous?.dispose();
    await _initialize();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = d.inHours;
    return hours > 0 ? '$hours:$minutes:$seconds' : '${d.inMinutes}:$seconds';
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final maxWidth = screenSize.width - 32.w;
    final maxHeight = screenSize.height * 0.75;

    double boxWidth = maxWidth;
    double boxHeight = maxWidth * 9 / 16;

    if (_isInitialized) {
      final aspect = _controller?.value.aspectRatio ?? 0;
      if (aspect > 0) {
        boxHeight = boxWidth / aspect;
        if (boxHeight > maxHeight) {
          boxHeight = maxHeight;
          boxWidth = boxHeight * aspect;
        }
      }
    }

    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 24.h),
        child: _buildSafeShell(boxWidth, boxHeight),
      ),
    );
  }

  Widget _buildSafeShell(double boxWidth, double boxHeight) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20.r),
          child: Container(
            width: boxWidth,
            height: boxHeight,
            color: Colors.black,
            child: _buildContent(),
          ),
        ),
        Positioned(
          top: -14.h,
          right: -6.w,
          child: InkWell(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(20.r),
            child: Container(
              width: 34.w,
              height: 34.w,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: AppIcon(
                Icons.close_rounded,
                size: 19.sp,
                color: Colors.black87,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              Icons.videocam_off_rounded,
              color: Colors.white70,
              size: 30.sp,
            ),
            SizedBox(height: 8.h),
            Text(
              "Couldn't load video",
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 13.sp),
            ),
            SizedBox(height: 10.h),
            TextButton.icon(
              onPressed: _retryVideo,
              icon: const AppIcon(Icons.refresh_rounded, size: 17),
              label: Text('Try again', style: GoogleFonts.outfit()),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
            ),
          ],
        ),
      );
    }

    final controller = _controller;
    if (!_isInitialized || controller == null) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );
    }

    final position = controller.value.position;
    final duration = controller.value.duration;
    final isMuted = controller.value.volume == 0;

    return GestureDetector(
      onTap: _toggleControls,
      child: Stack(
        alignment: Alignment.center,
        fit: StackFit.expand,
        children: [
          VideoPlayer(controller),

          AnimatedOpacity(
            opacity: _showControls ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_showControls,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.35),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.55),
                    ],
                    stops: const [0, 0.25, 0.6, 1],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Top bar
                    Padding(
                      padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 0),
                      child: Row(
                        children: [
                          Text(
                            'introduction',
                            style: GoogleFonts.outfit(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Center transport controls
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _TransportButton(
                          icon: Icons.replay_10_rounded,
                          size: 26.sp,
                          onTap: () => _seekBy(const Duration(seconds: -10)),
                        ),
                        SizedBox(width: 28.w),
                        _TransportButton(
                          icon: controller.value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 34.sp,
                          large: true,
                          onTap: _togglePlay,
                        ),
                        SizedBox(width: 28.w),
                        _TransportButton(
                          icon: Icons.forward_10_rounded,
                          size: 26.sp,
                          onTap: () => _seekBy(const Duration(seconds: 10)),
                        ),
                      ],
                    ),

                    // Bottom bar: scrubber + time + mute
                    Padding(
                      padding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 10.h),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 2.5,
                              thumbShape: RoundSliderThumbShape(
                                enabledThumbRadius: 6.r,
                              ),
                              overlayShape: RoundSliderOverlayShape(
                                overlayRadius: 12.r,
                              ),
                              activeTrackColor: AppColors.brand,
                              inactiveTrackColor: Colors.white.withValues(
                                alpha: 0.25,
                              ),
                              thumbColor: AppColors.brand,
                              overlayColor: AppColors.brand.withValues(
                                alpha: 0.2,
                              ),
                            ),
                            child: Slider(
                              min: 0,
                              max: duration.inMilliseconds.toDouble() > 0
                                  ? duration.inMilliseconds.toDouble()
                                  : 1,
                              value: position.inMilliseconds
                                  .clamp(0, duration.inMilliseconds)
                                  .toDouble(),
                              onChanged: (v) {
                                controller.seekTo(
                                  Duration(milliseconds: v.round()),
                                );
                                _scheduleHide();
                              },
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                _formatDuration(position),
                                style: GoogleFonts.outfit(
                                  fontSize: 11.sp,
                                  color: Colors.white.withValues(alpha: 0.9),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _formatDuration(duration),
                                style: GoogleFonts.outfit(
                                  fontSize: 11.sp,
                                  color: Colors.white.withValues(alpha: 0.9),
                                ),
                              ),
                              SizedBox(width: 12.w),
                              InkWell(
                                onTap: _toggleMute,
                                borderRadius: BorderRadius.circular(16.r),
                                child: Padding(
                                  padding: EdgeInsets.all(4.r),
                                  child: AppIcon(
                                    isMuted
                                        ? Icons.volume_off_rounded
                                        : Icons.volume_up_rounded,
                                    size: 18.sp,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransportButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final bool large;
  final VoidCallback onTap;

  const _TransportButton({
    required this.icon,
    required this.size,
    required this.onTap,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final boxSize = (large ? 56 : 40).w;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30.r),
      child: Container(
        width: boxSize,
        height: boxSize,
        decoration: BoxDecoration(
          color: large
              ? Colors.white.withValues(alpha: 0.95)
              : Colors.white.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: AppIcon(
          icon,
          size: size,
          color: large ? AppColors.brand : Colors.white,
        ),
      ),
    );
  }
}
