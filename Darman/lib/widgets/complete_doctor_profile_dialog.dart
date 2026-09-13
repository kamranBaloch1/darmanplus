import 'package:flutter/material.dart';
import 'package:darmaan/widgets/app_icon.dart';
import 'package:google_fonts/google_fonts.dart';

Future<void> showCompleteDoctorProfileDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.50),
    builder: (dialogContext) => Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 25),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(
                color: Color(0xFFF2F4F6),
                shape: BoxShape.circle,
              ),
              child: const AppIcon(
                Icons.person_outline_rounded,
                size: 28,
                color: Color(0xFF344054),
              ),
            ),
            const SizedBox(height: 17),
            Text(
              'Complete your profile',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 19,
                fontWeight: FontWeight.w500,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              'Complete your profile to become visible to patients and go online.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 13.5,
                height: 1.5,
                color: const Color(0xFF344054),
              ),
            ),
            const SizedBox(height: 23),
            SizedBox(
              width: double.infinity,
              height: 47,
              child: FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                style: FilledButton.styleFrom(
                  elevation: 0,
                  backgroundColor: const Color(0xFFF2F4F6),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                child: Text(
                  'Complete profile',
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
    ),
  );
}