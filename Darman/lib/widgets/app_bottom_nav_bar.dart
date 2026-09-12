import 'package:darmaan/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
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

  const AppBottomNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
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
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Color(0xFFE9ECEF), width: 1),
            ),
          ),
          child: Row(
            children: List.generate(items.length, (index) {
              final item = items[index];
              final isActive = index == currentIndex;
              final color = isActive
                  ? AppColors.brand
                  : const Color(0xFF9299A3);

              return Expanded(
                child: Semantics(
                  button: true,
                  selected: isActive,
                  label: item.label,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => onTap(index),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isActive ? item.activeIcon : item.icon,
                            size: 22.sp,
                            color: color,
                          ),
                          SizedBox(height: 4.h),
                          Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              fontSize: 10.sp,
                              height: 1.1,
                              fontWeight: FontWeight.w500,
                              color: color,
                            ),
                          ),
                        ],
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