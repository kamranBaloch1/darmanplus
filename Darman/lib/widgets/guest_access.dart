import 'package:darmaan/core/theme/app_colors.dart';
import 'package:darmaan/presentation/auth/screens/login/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

void openLogin(BuildContext context) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
}

Future<void> showLoginRequiredDialog(
  BuildContext context, {
  String title = 'Login required',
  String message = 'Please login to continue.',
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .35),
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(22.w, 24.h, 22.w, 20.h),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .08),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              //
              // ICON
              //
              Container(
                width: 54.w,
                height: 54.w,
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(17.r),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 25.sp,
                  color: AppColors.brand,
                ),
              ),

              SizedBox(height: 20.h),

              //
              // TITLE
              //
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 19.sp,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),

              SizedBox(height: 8.h),

              //
              // MESSAGE
              //
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.w),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 13.sp,
                    height: 1.45,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),

              SizedBox(height: 26.h),

              //
              // LOGIN BUTTON
              //
              SizedBox(
                width: double.infinity,
                height: 50.h,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    openLogin(context);
                  },
                  style: FilledButton.styleFrom(
                    elevation: 0,
                    backgroundColor: const Color(0xFFF1F2F4),
                    foregroundColor: Colors.black87,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                  child: Text(
                    'Login',
                    style: GoogleFonts.outfit(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),

              SizedBox(height: 8.h),

              //
              // NOT NOW
              //
              SizedBox(
                width: double.infinity,
                height: 44.h,
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                  child: Text(
                    'Not now',
                    style: GoogleFonts.outfit(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class GuestAccessView extends StatelessWidget {
  const GuestAccessView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF7F8FA),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 32.h),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 66.w,
                  height: 66.w,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20.r),
                    border: Border.all(color: const Color(0xFFE9EBEF)),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 28.sp, color: AppColors.brand),
                ),

                SizedBox(height: 24.h),

                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 21.sp,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),

                SizedBox(height: 8.h),

                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 13.5.sp,
                      height: 1.5,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),

                SizedBox(height: 26.h),

                SizedBox(
                  width: 155.w,
                  height: 44.h,
                  child: FilledButton(
                    onPressed: () => openLogin(context),
                    style: FilledButton.styleFrom(
                      elevation: 0,
                      backgroundColor: const Color(0xFFF1F2F4),
                      foregroundColor: Colors.black87,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    child: Text(
                      'Login',
                      style: GoogleFonts.outfit(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
