import 'package:darmaan/core/models/booking_model.dart';
import 'package:darmaan/core/models/user_model.dart';
import 'package:darmaan/core/theme/app_colors.dart';
import 'package:darmaan/presentation/home/chat/chat_room.dart';
import 'package:darmaan/presentation/home/patient/repository/patient_repository.dart';
import 'package:darmaan/presentation/home/patient/screens/doctor_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:darmaan/widgets/app_icon.dart';
import 'package:darmaan/core/utils/app_error_message.dart';
import 'package:darmaan/widgets/unread_message_badge.dart';
import 'package:darmaan/widgets/app_shimmer.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';

class PatientAppointmentsScreen extends StatefulWidget {
  const PatientAppointmentsScreen({
    super.key,
    this.refreshToken = 0,
  });

  final int refreshToken;

  @override
  State<PatientAppointmentsScreen> createState() =>
      _PatientAppointmentsScreenState();
}

class _PatientAppointmentsScreenState
    extends State<PatientAppointmentsScreen> {
  final PatientRepository _patientRepository = PatientRepository();

  bool _isLoading = true;
  String? _error;

  List<BookingModel> _bookings = [];
  Map<String, UserModel> _doctorsById = {};

  final Set<String> _cancellingIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PatientAppointmentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final bookings =
          await _patientRepository.getPatientBookings();

      final doctorIds = bookings
          .map((booking) => booking.doctorId)
          .toSet()
          .toList();

      final doctors =
          await _patientRepository.getDoctorsByIds(doctorIds);

      if (!mounted) return;

      setState(() {
        _bookings = bookings;
        _doctorsById = doctors;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = _readableError(e);
        _isLoading = false;
      });
    }
  }

  List<BookingModel> get _upcomingBookings {
    final bookings = _bookings.where((booking) {
      return booking.status == BookingStatus.pending ||
          booking.status == BookingStatus.accepted ||
          booking.status == BookingStatus.inProgress ||
          booking.hasUpcomingFollowUp;
    }).toList();

    bookings.sort((a, b) {
      if (a.hasUpcomingFollowUp != b.hasUpcomingFollowUp) {
        return a.hasUpcomingFollowUp ? -1 : 1;
      }
      return b.createdAt.compareTo(a.createdAt);
    });

    return bookings;
  }

  Future<void> _cancelBooking(
    BookingModel booking,
  ) async {
    final doctor = _doctorsById[booking.doctorId];

    final confirmed =
        await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (sheetContext) {
        return _CancelAppointmentSheet(
          doctorName:
              doctor?.name ?? 'this doctor',
          onKeep: () {
            Navigator.of(sheetContext).pop(false);
          },
          onCancel: () {
            Navigator.of(sheetContext).pop(true);
          },
        );
      },
    );

    if (confirmed != true) return;

    setState(() {
      _cancellingIds.add(booking.id);
    });

    try {
      await _patientRepository.cancelPendingBooking(
        booking.id,
        reason: 'Cancelled by patient',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          _buildSnackBar(
            text:
                'Your appointment with ${doctor?.name ?? 'the doctor'} has been cancelled.',
          ),
        );

      await _load();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          _buildSnackBar(
            text: _readableError(e),
            isError: true,
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _cancellingIds.remove(booking.id);
        });
      }
    }
  }

  void _openChat(BookingModel booking) {
    final doctor =
        _doctorsById[booking.doctorId];

    if (doctor == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          bookingId: booking.id,
          peerName: doctor.name,
          peerAvatarUrl: doctor.profileImage,
          peerSubtitle: [doctor.specialization, doctor.title]
              .whereType<String>()
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .join(' | '),
          peerVerified: doctor.isDoctorVerified,
          onPeerTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DoctorDetailsScreen(doctor: doctor),
              ),
            );
          },
        ),
      ),
    );
  }

  void _openDoctor(BookingModel booking) {
    final doctor =
        _doctorsById[booking.doctorId];

    if (doctor == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          _buildSnackBar(
            text:
                'This doctor profile is no longer available.',
          ),
        );

      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            DoctorDetailsScreen(
          doctor: doctor,
        ),
      ),
    );
  }

  SnackBar _buildSnackBar({
    required String text,
    bool isError = false,
  }) {
    return SnackBar(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: isError
          ? const Color(0xFF3E1D1D)
          : const Color(0xFF20242A),
      margin:
          const EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16,
      ),
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(12),
      ),
      content: Text(
        text,
        style: GoogleFonts.outfit(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
      ),
    );
  }

  String _readableError(Object error) {
    return AppErrorMessage.from(error);
  }

  @override
  Widget build(BuildContext context) {
    final bookings = _upcomingBookings;

    return Scaffold(
      backgroundColor:
          const Color(0xFFFAFAFB),
      appBar: AppBar(
        backgroundColor:
            const Color(0xFFFAFAFB),
        surfaceTintColor:
            Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        title: Text(
          'Appointments',
          style: GoogleFonts.outfit(
            fontSize: 21,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
            letterSpacing: -0.4,
          ),
        ),
      ),
      body: _isLoading
          ? const _LoadingState()
          : _error != null
              ? _ErrorState(
                  message: _error!,
                  onRetry: _load,
                )
              : bookings.isEmpty
                  ? _EmptyState(
                      onRefresh: _load,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color:
                          AppColors.brand,
                      backgroundColor:
                          Colors.white,
                      child:
                          ListView.builder(
                        physics:
                            const AlwaysScrollableScrollPhysics(),
                        padding:
                            const EdgeInsets.fromLTRB(
                          16,
                          8,
                          16,
                          32,
                        ),
                        itemCount:
                            bookings.length,
                        itemBuilder:
                            (context, index) {
                          final booking =
                              bookings[
                                  index];

                          return Padding(
                            padding:
                                const EdgeInsets.only(
                              bottom: 12,
                            ),
                            child:
                                _AppointmentCard(
                              booking:
                                  booking,
                              doctor:
                                  _doctorsById[
                                      booking
                                          .doctorId],
                              isCancelling:
                                  _cancellingIds
                                      .contains(
                                booking.id,
                              ),
                              onTap: () =>
                                  _openDoctor(
                                booking,
                              ),
                              onCancel: () =>
                                  _cancelBooking(
                                booking,
                              ),
                              onMessage: () =>
                                  _openChat(
                                booking,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

// =============================================================================
// APPOINTMENT CARD
// =============================================================================

class _AppointmentCard
    extends StatelessWidget {
  final BookingModel booking;
  final UserModel? doctor;

  final bool isCancelling;

  final VoidCallback onTap;
  final VoidCallback onCancel;
  final VoidCallback onMessage;

  const _AppointmentCard({
    required this.booking,
    required this.doctor,
    required this.isCancelling,
    required this.onTap,
    required this.onCancel,
    required this.onMessage,
  });

  bool get _hasImage {
    final image = doctor?.profileImage;

    return image != null &&
        image.trim().isNotEmpty;
  }

  bool get _canCancel =>
      booking.status == BookingStatus.pending;

  String get _doctorSubtitle {
    final specialization = doctor?.specialization?.trim() ?? '';
    final title = doctor?.title?.trim() ?? '';
    if (specialization.isNotEmpty && title.isNotEmpty) {
      return '$specialization | $title';
    }
    if (specialization.isNotEmpty) return specialization;
    if (title.isNotEmpty) return title;
    return 'General consultation';
  }

  bool get _canMessage =>
      booking.status ==
          BookingStatus.accepted ||
      booking.status ==
          BookingStatus.inProgress ||
      booking.isFollowUpOpen;

  String get _statusText {
    if (booking.hasScheduledFollowUp) return 'Follow-up';
    switch (booking.status) {
      case BookingStatus.pending:
        return 'Waiting';

      case BookingStatus.accepted:
        return 'In consultation';

      case BookingStatus.inProgress:
        return 'In consultation';

      case BookingStatus.completed:
        return 'Completed';

      case BookingStatus.cancelled:
        return 'Cancelled';
    }
  }

  IconData get _statusIcon {
    if (booking.hasScheduledFollowUp) return Icons.event_repeat_rounded;
    switch (booking.status) {
      case BookingStatus.pending:
        return Icons.schedule_rounded;

      case BookingStatus.accepted:
        return Icons
            .check_circle_outline_rounded;

      case BookingStatus.inProgress:
        return Icons.videocam_outlined;

      case BookingStatus.completed:
        return Icons
            .check_circle_outline_rounded;

      case BookingStatus.cancelled:
        return Icons.close_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius:
          BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius:
            BorderRadius.circular(18),
        child: Container(
          padding:
              const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular(18),
           
          ),
          child: Column(
            children: [
              _buildDoctor(),

              const SizedBox(height: 17),

              Container(
                height: 1,
                color:
                    const Color(0xFFF0F1F3),
              ),

              const SizedBox(height: 15),

              _buildDetails(),

              if (_canCancel ||
                  _canMessage) ...[
                const SizedBox(height: 17),

                _buildAction(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Doctor
  // ---------------------------------------------------------------------------

 Widget _buildDoctor() {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CircleAvatar(
        radius: 25,
        backgroundColor: const Color(0xFFF1F3F5),
        backgroundImage: _hasImage
            ? CachedNetworkImageProvider(doctor!.profileImage!)
            : null,
        child: _hasImage
            ? null
            : AppIcon(
                Icons.person_rounded,
                size: 23,
                color: AppColors.textSecondary,
              ),
      ),

      const SizedBox(width: 13),

      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      doctor?.name ?? 'Doctor unavailable',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 15.5,
                        height: 1.2,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.15,
                      ),
                    ),
                  ),

                  if (doctor?.isDoctorVerified == true) ...[
                    const SizedBox(width: 5),

                    AppIcon(
                      Icons.verified_rounded,
                      size: 16,
                      color: AppColors.brand,
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 4),

              Text(
                _doctorSubtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  fontSize: 12.5,
                  height: 1.3,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),

      const SizedBox(width: 10),

      _Status(
        text: _statusText,
        icon: _statusIcon,
      ),
    ],
  );
}

  // ---------------------------------------------------------------------------
  // Appointment details
  //
  // Intentionally minimal.
  // Date on left, fee on right.
  // No fee icon, no card inside card, no colored fee box.
  // ---------------------------------------------------------------------------

  Widget _buildDetails() {
    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                _formatDateTime(
                  booking.createdAt,
                ),
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style:
                    GoogleFonts.outfit(
                  fontSize: 13.5,
                  fontWeight:
                      FontWeight.w500,
                  color:
                      AppColors.textPrimary,
                  letterSpacing: -0.1,
                ),
              ),

              const SizedBox(height: 3),

              Text(
                'Requested',
                style:
                    GoogleFonts.outfit(
                  fontSize: 11.5,
                  fontWeight:
                      FontWeight.w400,
                  color: AppColors
                      .textSecondary,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 20),

        Column(
          crossAxisAlignment:
              CrossAxisAlignment.end,
          children: [
            Text(
              'Rs. ${_formatFee(booking.consultationFee)}',
              style: GoogleFonts.outfit(
                fontSize: 15,
                height: 1.1,
                fontWeight:
                    FontWeight.w500,
                color:
                    AppColors.textPrimary,
                letterSpacing: -0.2,
              ),
            ),

            const SizedBox(height: 3),

            Text(
              'Consultation fee',
              style: GoogleFonts.outfit(
                fontSize: 11.5,
                fontWeight:
                    FontWeight.w400,
                color: AppColors
                    .textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Action
  // ---------------------------------------------------------------------------

  Widget _buildAction() {
    if (_canMessage && _canCancel) {
      return Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 44,
              child: TextButton(
                onPressed: isCancelling ? null : onCancel,
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFF1F3F5),
                  foregroundColor: const Color(0xFFB42318),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: isCancelling
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Cancel'),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 44,
              child: FilledButton.icon(
                onPressed: onMessage,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: UnreadMessageBadge(
                  bookingId: booking.id,
                  isDoctor: false,
                  child: const AppIcon(
                    Icons.chat_bubble_outline_rounded,
                    size: 16,
                  ),
                ),
                label: const Text('Message'),
              ),
            ),
          ),
        ],
      );
    }

    if (_canMessage) {
      return SizedBox(
        width: double.infinity,
        height: 44,
        child: FilledButton(
          onPressed: onMessage,
          style: FilledButton.styleFrom(
            elevation: 0,
            backgroundColor:
                AppColors.brand,
            foregroundColor:
                Colors.white,
            padding:
                const EdgeInsets.symmetric(
              horizontal: 16,
            ),
            shape:
                RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(
                12,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment:
                MainAxisAlignment.center,
            mainAxisSize:
                MainAxisSize.min,
            children: [
              UnreadMessageBadge(
                bookingId: booking.id,
                isDoctor: false,
                child: const AppIcon(
                  Icons.chat_bubble_outline_rounded,
                  size: 17,
                ),
              ),

              const SizedBox(width: 8),

              Text(
                'Message doctor',
                style:
                    GoogleFonts.outfit(
                  fontSize: 13.5,
                  fontWeight:
                      FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_canCancel) {
      return Align(
        alignment:
            Alignment.centerRight,
        child: TextButton(
          onPressed: isCancelling
              ? null
              : onCancel,
          style: TextButton.styleFrom(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 2,
              vertical: 4,
            ),
            minimumSize: Size.zero,
            tapTargetSize:
                MaterialTapTargetSize
                    .shrinkWrap,
            foregroundColor:
                const Color(0xFFB42318),
          ),
          child: isCancelling
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child:
                      CircularProgressIndicator(
                    strokeWidth: 1.8,
                  ),
                )
              : Text(
                  'Cancel appointment',
                  style:
                      GoogleFonts.outfit(
                    fontSize: 12.5,
                    fontWeight:
                        FontWeight.w500,
                  ),
                ),
        ),
      );
    }



    return const SizedBox.shrink();
  }

  // ---------------------------------------------------------------------------
  // Formatting
  // ---------------------------------------------------------------------------

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _formatDateTime(
    DateTime dateTime,
  ) {
    final local =
        dateTime.toLocal();

    final month =
        _months[local.month - 1];

    final hour =
        local.hour % 12 == 0
            ? 12
            : local.hour % 12;

    final minute = local.minute
        .toString()
        .padLeft(2, '0');

    final period =
        local.hour >= 12
            ? 'PM'
            : 'AM';

    return '$month ${local.day} · $hour:$minute $period';
  }

  String _formatFee(double fee) {
    final value =
        fee.toStringAsFixed(0);

    final reversed =
        value.split('').reversed.toList();

    final result = <String>[];

    for (int i = 0;
        i < reversed.length;
        i++) {
      if (i > 0 && i % 3 == 0) {
        result.add(',');
      }

      result.add(reversed[i]);
    }

    return result.reversed.join();
  }
}

// =============================================================================
// STATUS
// =============================================================================

class _Status extends StatelessWidget {
  final String text;
  final IconData icon;

  const _Status({
    required this.text,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color:
            AppColors.brand.withValues(
          alpha: 0.07,
        ),
        borderRadius:
            BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          AppIcon(
            icon,
            size: 12.5,
            color: AppColors.brand,
          ),

          const SizedBox(width: 5),

          Text(
            text,
            style: GoogleFonts.outfit(
              fontSize: 11,
              height: 1,
              fontWeight:
                  FontWeight.w500,
              color:
                  AppColors.brand,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// EMPTY STATE
// =============================================================================

class _EmptyState
    extends StatelessWidget {
  final Future<void> Function()
      onRefresh;

  const _EmptyState({
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.brand,
      child: ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        padding:
            const EdgeInsets.symmetric(
          horizontal: 36,
        ),
        children: [
          SizedBox(
            height:
                MediaQuery.sizeOf(
                      context,
                    ).height *
                    0.18,
          ),

          Center(
            child: Container(
              width: 52,
              height: 52,
              decoration:
                  BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.brand
                    .withValues(
                  alpha: 0.07,
                ),
              ),
              child: AppIcon(
                Icons
                    .calendar_today_outlined,
                size: 22,
                color:
                    AppColors.brand,
              ),
            ),
          ),

          const SizedBox(height: 19),

          Text(
            'No appointments yet',
            textAlign:
                TextAlign.center,
            style:
                GoogleFonts.outfit(
              fontSize: 17,
              fontWeight:
                  FontWeight.w500,
              color:
                  AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),

          const SizedBox(height: 7),

          Text(
            'Your upcoming doctor consultations will appear here.',
            textAlign:
                TextAlign.center,
            style:
                GoogleFonts.outfit(
              fontSize: 13,
              height: 1.5,
              fontWeight:
                  FontWeight.w400,
              color: AppColors
                  .textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// LOADING
// =============================================================================

class _LoadingState
    extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const AppListShimmer(itemCount: 5, horizontalPadding: 16);
  }
}

// =============================================================================
// ERROR
// =============================================================================

class _ErrorState
    extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 36,
        ),
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            AppIcon(
              Icons
                  .error_outline_rounded,
              size: 28,
              color: AppColors
                  .textSecondary
                  .withValues(
                alpha: 0.55,
              ),
            ),

            const SizedBox(height: 15),

            Text(
              'Couldn’t load appointments',
              textAlign:
                  TextAlign.center,
              style:
                  GoogleFonts.outfit(
                fontSize: 16,
                fontWeight:
                    FontWeight.w500,
                color: AppColors
                    .textPrimary,
              ),
            ),

            const SizedBox(height: 7),

            Text(
              message,
              textAlign:
                  TextAlign.center,
              style:
                  GoogleFonts.outfit(
                fontSize: 13,
                height: 1.5,
                color: AppColors
                    .textSecondary,
              ),
            ),

            const SizedBox(height: 17),

            TextButton(
              onPressed: onRetry,
              child: Text(
                'Try again',
                style:
                    GoogleFonts.outfit(
                  fontSize: 13.5,
                  fontWeight:
                      FontWeight.w500,
                  color:
                      AppColors.brand,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// CANCEL SHEET
// =============================================================================

class _CancelAppointmentSheet
    extends StatelessWidget {
  final String doctorName;
  final VoidCallback onKeep;
  final VoidCallback onCancel;

  const _CancelAppointmentSheet({
    required this.doctorName,
    required this.onKeep,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20,
      ),
      decoration:
          const BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration:
                BoxDecoration(
              color:
                  const Color(
                0xFFD9DCE1,
              ),
              borderRadius:
                  BorderRadius.circular(
                100,
              ),
            ),
          ),

          const SizedBox(height: 25),

          Text(
            'Cancel appointment?',
            textAlign:
                TextAlign.center,
            style:
                GoogleFonts.outfit(
              fontSize: 18,
              fontWeight:
                  FontWeight.w500,
              color:
                  AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'Your request with $doctorName will be cancelled. Any reserved consultation fee will be returned to your wallet.',
            textAlign:
                TextAlign.center,
            style:
                GoogleFonts.outfit(
              fontSize: 13,
              height: 1.5,
              fontWeight:
                  FontWeight.w400,
              color: AppColors
                  .textSecondary,
            ),
          ),

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton(
              onPressed: onKeep,
              style:
                  FilledButton.styleFrom(
                elevation: 0,
                backgroundColor:
                    AppColors.brand,
                foregroundColor:
                    Colors.white,
                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(
                    12,
                  ),
                ),
              ),
              child: Text(
                'Keep appointment',
                style:
                    GoogleFonts.outfit(
                  fontSize: 13.5,
                  fontWeight:
                      FontWeight.w500,
                ),
              ),
            ),
          ),

          const SizedBox(height: 4),

          SizedBox(
            width: double.infinity,
            height: 42,
            child: TextButton(
              onPressed: onCancel,
              style:
                  TextButton.styleFrom(
                foregroundColor:
                    const Color(
                  0xFFB42318,
                ),
              ),
              child: Text(
                'Cancel appointment',
                style:
                    GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight:
                      FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
