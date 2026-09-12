import 'package:darmaan/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.brand,
        brightness: Brightness.light,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      fontFamily: GoogleFonts.outfit().fontFamily,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
    final textTheme = GoogleFonts.outfitTextTheme(base.textTheme).apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );

    return base.copyWith(
      textTheme: textTheme,
      primaryTextTheme: GoogleFonts.outfitTextTheme(base.primaryTextTheme),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: .5,
        centerTitle: false,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.white,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 19.sp,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: GoogleFonts.outfit(
          fontSize: 14.sp,
          color: AppColors.textSecondary,
        ),
        labelStyle: GoogleFonts.outfit(
          fontSize: 13.sp,
          color: AppColors.textSecondary,
        ),
        errorStyle: GoogleFonts.outfit(
          fontSize: 11.5.sp,
          color: const Color(0xFFB42318),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          textStyle: GoogleFonts.outfit(
            fontSize: 14.sp,
            fontWeight: FontWeight.w500,
          ),
          minimumSize: Size(48.w, 48.h),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14.r),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          textStyle: GoogleFonts.outfit(
            fontSize: 14.sp,
            fontWeight: FontWeight.w500,
          ),
          minimumSize: Size(48.w, 48.h),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14.r),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: GoogleFonts.outfit(
            fontSize: 13.5.sp,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22.r),
        ),
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 19.sp,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
        contentTextStyle: GoogleFonts.outfit(
          fontSize: 13.5.sp,
          height: 1.45,
          color: AppColors.textSecondary,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF20252B),
        contentTextStyle: GoogleFonts.outfit(
          fontSize: 13.sp,
          color: Colors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.r),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        labelTextStyle: WidgetStatePropertyAll(
          GoogleFonts.outfit(fontSize: 11.sp, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
