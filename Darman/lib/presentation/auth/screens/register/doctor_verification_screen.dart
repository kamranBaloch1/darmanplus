import 'package:darmaan/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:darmaan/widgets/auth_customer_care_button.dart';

class DoctorVerificationPendingScreen extends StatefulWidget {
  const DoctorVerificationPendingScreen({super.key});

  @override
  State<DoctorVerificationPendingScreen> createState() =>
      _DoctorVerificationPendingScreenState();
}

class _DoctorVerificationPendingScreenState
    extends State<DoctorVerificationPendingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _rotateController;
  late final AnimationController _entranceController;

  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;
  late final Animation<double> _hourglassFlip;

  @override
  void initState() {
    super.initState();

    // Breathing glow behind the icon badge
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseScale = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _pulseOpacity = Tween<double>(begin: 0.35, end: 0.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Hourglass flip, pauses, then flips again — like sand actually running
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();

    _hourglassFlip = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 3.1416)
            .chain(CurveTween(curve: Curves.easeInOutBack)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: ConstantTween(3.1416),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 3.1416, end: 6.2832)
            .chain(CurveTween(curve: Curves.easeInOutBack)),
        weight: 30,
      ),
    ]).animate(_rotateController);

    // Staggered entrance for content below the icon
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotateController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  Animation<Offset> _slideIn(double startInterval) {
    return Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Interval(startInterval, 1.0, curve: Curves.easeOutCubic),
      ),
    );
  }

  Animation<double> _fadeIn(double startInterval) {
    return CurvedAnimation(
      parent: _entranceController,
      curve: Interval(startInterval, 1.0, curve: Curves.easeOut),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFD),
      floatingActionButton: const AuthCustomerCareButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 20.h),
          child: Column(
            children: [
              const Spacer(),

              // Animated glow + rotating hourglass icon
              SizedBox(
                width: 110.w,
                height: 110.w,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _pulseScale.value,
                          child: Container(
                            width: 96.w,
                            height: 96.w,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.brand.withValues(
                                alpha: _pulseOpacity.value,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    Container(
                      width: 70.w,
                      height: 70.w,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.brand,
                            AppColors.brandDark,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(24.r),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.brand.withValues(alpha: 0.32),
                            blurRadius: 20.r,
                            offset: Offset(0, 10.h),
                          ),
                        ],
                      ),
                      child: AnimatedBuilder(
                        animation: _rotateController,
                        builder: (context, child) {
                          return Transform.rotate(
                            angle: _hourglassFlip.value,
                            child: child,
                          );
                        },
                        child: Icon(
                          Icons.hourglass_top_rounded,
                          size: 32.sp,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 30.h),

              FadeTransition(
                opacity: _fadeIn(0.0),
                child: SlideTransition(
                  position: _slideIn(0.0),
                  child: Text(
                    'Verification pending',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
              ),

              SizedBox(height: 12.h),

              FadeTransition(
                opacity: _fadeIn(0.1),
                child: SlideTransition(
                  position: _slideIn(0.1),
                  child: Text(
                    'Your documents have been submitted successfully. Our team will review them before activating your doctor profile.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 12.sp,
                      height: 1.55,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),

              SizedBox(height: 32.h),

              FadeTransition(
                opacity: _fadeIn(0.2),
                child: SlideTransition(
                  position: _slideIn(0.2),
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(18.w),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20.r),
                
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 14.r,
                          offset: Offset(0, 4.h),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _InfoRow(
                          icon: Icons.check_rounded,
                          title: 'Documents submitted',
                          iconColor: const Color(0xFF10B981),
                        ),

                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                          child: _Connector(),
                        ),

                        _InfoRow(
                          icon: Icons.search_rounded,
                          title: 'Admin review in progress',
                          iconColor: AppColors.brand,
                        ),

                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                          child: _Connector(),
                        ),

                        _InfoRow(
                          icon: Icons.notifications_none_rounded,
                          title: 'You\'ll be notified once verified',
                          iconColor: Colors.grey.shade400,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Connector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(left: 19.w),
        child: Container(
          width: 2,
          height: 14.h,
          color: AppColors.border,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color iconColor;

  const _InfoRow({
    required this.icon,
    required this.title,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40.w,
          height: 40.w,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12.r),
          ),
          child: Icon(
            icon,
            color: iconColor,
            size: 20.sp,
          ),
        ),

        SizedBox(width: 14.w),

        Expanded(
          child: Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 12.5.sp,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
