import 'package:darmaan/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:darmaan/widgets/app_icon.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

class NavBarItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const NavBarItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

class AppBottomNavBar extends StatelessWidget {
  final List<NavBarItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool showShadow;

  const AppBottomNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.showShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.zero,
        child: Container(
          height: 64.h,
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
        decoration: BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.only(
    topLeft: Radius.circular(28.r),
    topRight: Radius.circular(28.r),
  ),
  boxShadow: [
    BoxShadow(
      color: const Color(0xFF1B2633).withValues(alpha: 0.07),
      blurRadius: 18.r,
      spreadRadius: 0,
      offset: Offset(0, -3.h),
    ),
  ],
),
       
          child: Row(
            children: List.generate(items.length, (index) {
              final item = items[index];
              final isActive = index == currentIndex;

              return Expanded(
                child: Semantics(
                  button: true,
                  selected: isActive,
                  label: item.label,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => onTap(index),
                      borderRadius: BorderRadius.circular(17.r),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(17.r),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedScale(
                              scale: isActive ? 1.08 : 1,
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutBack,
                              child: AppIcon(
                                isActive ? item.activeIcon : item.icon,
                                size: 21.5.sp,
                                emphasized: isActive,
                                color: isActive
                                    ? AppColors.brand
                                    : const Color(0xFF9299A3),
                              ),
                            ),
                            SizedBox(height: 3.h),
                            AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 200),
                              style: GoogleFonts.outfit(
                                fontSize: 10.5.sp,
                                height: 1.1,
                                fontWeight: isActive
                                    ? FontWeight.w500
                                    : FontWeight.w500,
                                color: isActive
                                    ? AppColors.brand
                                    : const Color(0xFF9299A3),
                              ),
                              child: Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}