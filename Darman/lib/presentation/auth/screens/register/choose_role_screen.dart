import 'package:darmaan/core/models/user_model.dart';
import 'package:darmaan/core/helpers/push_notification_service.dart';
import 'package:darmaan/core/theme/app_colors.dart';
import 'package:darmaan/presentation/auth/repository/register/user_repository.dart';
import 'package:darmaan/presentation/auth/screens/register/patient_profile_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:darmaan/core/utils/app_error_message.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import 'doctor_document_screen.dart';

class ChooseRoleScreen extends StatefulWidget {
  const ChooseRoleScreen({super.key});

  @override
  State<ChooseRoleScreen> createState() => _ChooseRoleScreenState();
}

class _ChooseRoleScreenState extends State<ChooseRoleScreen> {
  final UserRepository _userRepository = UserRepository();

  UserRole? selectedRole;

  bool isLoading = false;

  Future<void> _continue() async {
    if (selectedRole == null || isLoading) {
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      await _userRepository.createUser(
        role: selectedRole!,
      );

      try {
        await PushNotificationService.instance.activateForSignedInUser();
      } catch (_) {
        // Registration is retried by AuthNavigator on the next authenticated launch.
      }

      if (!mounted) return;

      if (selectedRole == UserRole.patient) {
        // A new patient completes their identity before entering the app.
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => const PatientProfileSetupScreen(),
          ),
          (route) => false,
        );
      } else {
        // Doctor goes to document upload
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const DoctorDocumentScreen(),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.black87,
          margin: EdgeInsets.all(16.r),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
          content: Text(
            AppErrorMessage.from(e),
            style: GoogleFonts.outfit(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24.w, 32.h, 24.w, 20.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 30.h),

                    Padding(
                      padding: const EdgeInsets.only(left: 20),
                      child: Text(
                        'How will you use Darman?',
                        style: GoogleFonts.outfit(
                          fontSize: 20.sp,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                          height: 1.2,
                          letterSpacing: -0.6,
                        ),
                      ),
                    ),

                    SizedBox(height: 32.h),

                    _RoleCard(
                      title: 'I am a Patient',
                      icon: Icons.person_rounded,
                      badgeColors: const [
                        Color(0xFF34D399),
                        Color(0xFF10B981),
                      ],
                      isSelected: selectedRole == UserRole.patient,
                      onTap: isLoading
                          ? () {}
                          : () {
                              setState(() {
                                selectedRole = UserRole.patient;
                              });
                            },
                    ),

                    SizedBox(height: 16.h),

                    _RoleCard(
                      title: 'I am a Doctor',
                      icon: Icons.local_hospital_rounded,
                      badgeColors: const [
                        AppColors.brand,
                        AppColors.brandDark,
                      ],
                      isSelected: selectedRole == UserRole.doctor,
                      onTap: isLoading
                          ? () {}
                          : () {
                              setState(() {
                                selectedRole = UserRole.doctor;
                              });
                            },
                    ),

                    SizedBox(height: 8.h),
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
                  child: ElevatedButton(
                    onPressed:
                        selectedRole == null || isLoading
                            ? null
                            : _continue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      disabledBackgroundColor: const Color(0xFFEEF1F5),
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.grey.shade400,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16.r),
                      ),
                    ),
                    child: isLoading
                        ? SizedBox(
                            width: 22.w,
                            height: 22.w,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Continue',
                                style: GoogleFonts.outfit(
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.2,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 8.w),
                              Icon(Icons.arrow_forward_rounded, size: 20.sp),
                            ],
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

class _RoleCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Color> badgeColors;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.title,
    required this.icon,
    required this.badgeColors,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22.r),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 18.h),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22.r),
         
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.035),
              blurRadius: 14.r,
              offset: Offset(0, 4.h),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40.w,
              height: 40.w,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: badgeColors,
                ),
                borderRadius: BorderRadius.circular(15.r),
                boxShadow: [
                  BoxShadow(
                    color: badgeColors.last.withValues(alpha: 0.28),
                    blurRadius: 14.r,
                    offset: Offset(0, 6.h),
                  ),
                ],
              ),
              child: Icon(
                icon,
                size: 22.sp,
                color: Colors.white,
              ),
            ),

            SizedBox(width: 16.w),

            Expanded(
              child: Text(
                title,
                style: GoogleFonts.outfit(
                  fontSize: 14.5.sp,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ),

            SizedBox(width: 10.w),

            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22.w,
              height: 22.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? AppColors.brand : Colors.transparent,
                border: Border.all(
                  color: isSelected ? AppColors.brand : Colors.grey.shade300,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Icon(
                      Icons.check_rounded,
                      size: 14.sp,
                      color: Colors.white,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
