import 'package:cached_network_image/cached_network_image.dart';
import 'package:darmaan/core/models/booking_model.dart';
import 'package:darmaan/core/models/user_model.dart';
import 'package:darmaan/core/theme/app_colors.dart';
import 'package:darmaan/widgets/app_icon.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// A quiet discovery row. Profile and consultation actions remain separate.
class PatientDoctorListTile extends StatelessWidget {
  const PatientDoctorListTile({
    super.key,
    required this.doctor,
    required this.onTap,
    required this.onTapPhoto,
    this.appointmentStatus,
    this.followUpDate,
  });

  final UserModel doctor;
  final VoidCallback onTap;
  final VoidCallback onTapPhoto;
  final BookingStatus? appointmentStatus;
  final DateTime? followUpDate;

  @override
  Widget build(BuildContext context) {
    final image = doctor.profileImage?.trim();
    final specialty = doctor.specialization?.trim() ?? '';
    final availability = doctor.isAvailable ? 'Online' : 'Offline';
    final isFollowUp =
        appointmentStatus == BookingStatus.completed && followUpDate != null;
    final appointmentLabel = isFollowUp
        ? 'Follow-up'
        : switch (appointmentStatus) {
            BookingStatus.pending => 'Pending',
            BookingStatus.accepted => 'Accepted',
            BookingStatus.inProgress => 'In progress',
            _ => null,
          };
    final appointmentColor = isFollowUp
        ? const Color(0xFF175CD3)
        : appointmentStatus == BookingStatus.inProgress
        ? const Color(0xFF1570EF)
        : appointmentStatus == BookingStatus.accepted
        ? const Color(0xFF16834A)
        : const Color(0xFFB26A00);
    final appointmentBackground = isFollowUp
        ? const Color(0xFFEAF3FF)
        : appointmentStatus == BookingStatus.inProgress
        ? const Color(0xFFEFF6FF)
        : appointmentStatus == BookingStatus.accepted
        ? const Color(0xFFEDF8F1)
        : const Color(0xFFFFF6E8);

    const fallbackAvatar = Center(
      child: AppIcon(Icons.person_rounded, size: 27, color: AppColors.brand),
    );
    const loadingAvatar = ColoredBox(color: Color(0xFFE9EDF2));

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          child: Row(
            children: [
              Semantics(
                label: '${doctor.name}, $availability',
                child: Tooltip(
                  message: availability,
                  child: Stack(
                    children: [
                      Semantics(
                        label: 'View doctor profile or introduction',
                        child: Material(
                          color: const Color(0xFFE7EFFB),
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: onTapPhoto,
                            customBorder: const CircleBorder(),
                            child: SizedBox.square(
                              dimension: 56,
                              child: image != null && image.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: image,
                                      fit: BoxFit.cover,
                                      fadeOutDuration: Duration.zero,
                                      fadeInDuration: const Duration(
                                        milliseconds: 140,
                                      ),
                                      placeholder: (_, _) => loadingAvatar,
                                      errorWidget: (_, _, _) => fallbackAvatar,
                                    )
                                  : fallbackAvatar,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 1,
                        child: IgnorePointer(
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: doctor.isAvailable
                                  ? const Color(0xFF20C86B)
                                  : const Color(0xFF9AA3AE),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            doctor.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              height: 1.25,
                              color: const Color(0xFF202A36),
                            ),
                          ),
                        ),
                        if (doctor.isDoctorVerified) ...[
                          const SizedBox(width: 5),
                          const Tooltip(
                            message: 'Verified doctor',
                            child: AppIcon(
                              Icons.verified_rounded,
                              size: 14,
                              color: AppColors.brand,
                              semanticLabel: 'Verified doctor',
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (specialty.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        specialty,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          height: 1.3,
                          color: const Color(0xFF737C88),
                        ),
                      ),
                    ],
                    // Keep actionable booking information without squeezing names.
                    if (appointmentLabel != null) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: appointmentBackground,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              appointmentLabel,
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: appointmentColor,
                              ),
                            ),
                          ),
                          if (isFollowUp)
                            Text(
                              DateFormat('d MMM yyyy').format(followUpDate!),
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                color: const Color(0xFF667085),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}