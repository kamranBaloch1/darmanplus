import 'dart:async';

import 'package:darmaan/core/models/booking_model.dart';
import 'package:darmaan/core/models/consultation_review_model.dart';
import 'package:darmaan/core/models/doctor_review_summary_model.dart';
import 'package:darmaan/core/models/user_model.dart';
import 'package:darmaan/core/theme/app_colors.dart';
import 'package:darmaan/core/utils/app_error_message.dart';
import 'package:darmaan/presentation/home/patient/repository/patient_repository.dart';
import 'package:darmaan/presentation/home/patient/screens/doctor_reviews_screen.dart';
import 'package:darmaan/presentation/home/chat/chat_room.dart';
import 'package:darmaan/presentation/home/patient/screens/patient_consultation_request_screen.dart';
import 'package:darmaan/widgets/video_dilog.dart';
import 'package:darmaan/widgets/unread_message_badge.dart';
import 'package:darmaan/widgets/app_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:darmaan/widgets/app_icon.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class DoctorDetailsScreen extends StatefulWidget {
  final UserModel doctor;

  const DoctorDetailsScreen({super.key, required this.doctor});

  @override
  State<DoctorDetailsScreen> createState() => _DoctorDetailsScreenState();
}

class _DoctorDetailsScreenState extends State<DoctorDetailsScreen>
    with WidgetsBindingObserver {
  static const _cancellationDelay = Duration(minutes: 30);

  final PatientRepository _patientRepository = PatientRepository();
  Timer? _cancellationTimer;
  DateTime? _serverTimeAtSync;
  final Stopwatch _timeSinceServerSync = Stopwatch();

  bool _isBooking = false;
  bool _isCancelling = false;
  bool _isCheckingBooking = true;

  BookingModel? _activeBooking;
  BookingModel? _activePaidBooking;
  List<BookingModel> _activeFollowUps = const [];

  UserModel get doctor => widget.doctor;

  bool get _hasImage =>
      doctor.profileImage != null && doctor.profileImage!.trim().isNotEmpty;

  bool get _hasVideo =>
      doctor.introVideoUrl != null && doctor.introVideoUrl!.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadActiveBooking();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_activeBooking?.status == BookingStatus.pending) {
        _syncCancellationClock();
      } else if (_activeBooking?.hasScheduledFollowUp == true) {
        _loadActiveBooking();
      }
    }
  }

  DateTime? get _estimatedServerNow {
    final synced = _serverTimeAtSync;
    return synced == null ? null : synced.add(_timeSinceServerSync.elapsed);
  }

  Duration? get _cancellationRemaining {
    final booking = _activeBooking;
    final serverNow = _estimatedServerNow;
    if (booking?.status != BookingStatus.pending || serverNow == null) {
      return null;
    }
    final remaining = booking!.createdAt
        .add(_cancellationDelay)
        .difference(serverNow);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool get _canCancelPending =>
      _activeBooking?.status == BookingStatus.pending &&
      _cancellationRemaining == Duration.zero;

  String _formatCancellationRemaining(Duration? remaining) {
    if (remaining == null) return 'Syncing...';
    final totalSeconds = (remaining.inMilliseconds + 999) ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _syncCancellationClock() async {
    try {
      final serverNow = await _patientRepository.getConsultationServerTime();
      if (!mounted) return;
      _serverTimeAtSync = serverNow;
      _timeSinceServerSync
        ..reset()
        ..start();
      _startCancellationTimer();
      setState(() {});
    } catch (_) {
      if (!mounted || _activeBooking?.status != BookingStatus.pending) return;
      _cancellationTimer?.cancel();
      _cancellationTimer = Timer(
        const Duration(seconds: 10),
        _syncCancellationClock,
      );
    }
  }

  void _startCancellationTimer() {
    _cancellationTimer?.cancel();
    _cancellationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _activeBooking?.status != BookingStatus.pending) {
        timer.cancel();
        return;
      }
      setState(() {});
      if (timer.tick % 60 == 0) _syncCancellationClock();
    });
  }

  // ===========================================================================
  // ACTIVE BOOKING
  // ===========================================================================

  Future<void> _loadActiveBooking() async {
    try {
      final followUps = await _patientRepository.getActiveFollowUpsForDoctor(
        doctorId: doctor.uid,
      );
      final paidBooking = await _patientRepository.getActiveStandardBooking(
        doctorId: doctor.uid,
      );
      final booking = followUps.isNotEmpty ? followUps.first : paidBooking;

      if (!mounted) return;

      setState(() {
        _activeBooking = booking;
        _activePaidBooking = paidBooking;
        _activeFollowUps = followUps;
        _isCheckingBooking = false;
      });
      if (booking?.status == BookingStatus.pending) {
        await _syncCancellationClock();
      } else {
        _cancellationTimer?.cancel();
        _serverTimeAtSync = null;
        _timeSinceServerSync
          ..stop()
          ..reset();
      }
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isCheckingBooking = false;
      });
    }
  }

  Future<void> _openChat(BookingModel booking) async {
    final subtitle = [doctor.specialization, doctor.title]
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(' | ');
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          bookingId: booking.id,
          peerName: doctor.name,
          peerAvatarUrl: doctor.profileImage,
          peerSubtitle: subtitle.isEmpty ? 'Doctor' : subtitle,
          peerVerified: doctor.isDoctorVerified,
        ),
      ),
    );
    if (mounted) await _loadActiveBooking();
  }

  // ===========================================================================
  // BOOK CONSULTATION
  // ===========================================================================

  Future<void> _bookAppointment() async {
    if (_isBooking) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PatientConsultationRequestScreen(doctor: doctor),
      ),
    );
    if (mounted) _loadActiveBooking();
  }

  Future<void> _bookNewConsultation() async {
    if (_isBooking) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PatientConsultationRequestScreen(
          doctor: doctor,
          startNewConsultation: true,
        ),
      ),
    );
    if (mounted) _loadActiveBooking();
  }

  Future<void> _openPaidConsultation(BookingModel booking) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PatientConsultationRequestScreen(
          doctor: doctor,
          initialBooking: booking,
        ),
      ),
    );
    if (mounted) _loadActiveBooking();
  }

  Future<void> _openFollowUpChat() async {
    if (_activeFollowUps.isEmpty) return;
    BookingModel? selected;
    if (_activeFollowUps.length == 1) {
      selected = _activeFollowUps.first;
    } else {
      selected = await showModalBottomSheet<BookingModel>(
        context: context,
        backgroundColor: Colors.transparent,
        useSafeArea: true,
        builder: (sheetContext) => Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD7DBE0),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Choose a follow-up chat',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Each follow-up belongs to a different consultation.',
                style: GoogleFonts.outfit(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              ..._activeFollowUps.map(
                (followUp) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: const Color(0xFFF6F7F9),
                    borderRadius: BorderRadius.circular(14),
                    child: ListTile(
                      onTap: () => Navigator.pop(sheetContext, followUp),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      leading: const AppIcon(
                        Icons.event_repeat_rounded,
                        color: AppColors.brand,
                      ),
                      title: Text(
                        DateFormat('d MMMM yyyy').format(followUp.followUpDate!),
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        followUp.isFollowUpOpen
                            ? 'Chat is open'
                            : 'View only until this date',
                        style: GoogleFonts.outfit(fontSize: 11.5),
                      ),
                      trailing: const AppIcon(Icons.chevron_right_rounded),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (selected != null && mounted) await _openChat(selected);
  }

  // ===========================================================================
  // CANCEL
  // ===========================================================================

  Future<void> _cancelAppointment() async {
    final booking = _activeBooking;

    if (booking == null || _isCancelling || !_canCancelPending) return;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (sheetContext) {
        return _CancelSheet(
          doctorName: doctor.name,
          onKeep: () {
            Navigator.pop(sheetContext, false);
          },
          onCancel: () {
            Navigator.pop(sheetContext, true);
          },
        );
      },
    );

    if (confirmed != true) return;

    HapticFeedback.mediumImpact();

    setState(() {
      _isCancelling = true;
    });

    try {
      await _patientRepository.cancelPendingBooking(
        booking.id,
        reason: 'Cancelled by patient',
      );

      if (!mounted) return;

      setState(() {
        _activeBooking = null;
      });

      _cancellationTimer?.cancel();
      _serverTimeAtSync = null;
      _timeSinceServerSync
        ..stop()
        ..reset();

      _showSnack('Appointment cancelled');
    } catch (e) {
      if (!mounted) return;

      _showSnack(_readableError(e), isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isCancelling = false;
        });
      }
    }
  }

  // ===========================================================================
  // SUCCESS DIALOG
  // ===========================================================================

  Future<void> _showBookingSuccessDialog() {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.50),
      builder: (dialogContext) {
        return Dialog(
          elevation: 0,
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 30, 24, 22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: 0.09),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: AppColors.brand,
                        shape: BoxShape.circle,
                      ),
                      child: const AppIcon(
                        Icons.check_rounded,
                        size: 29,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 22),

                Text(
                  'Request sent',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.4,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  'Your consultation request with ${doctor.name} has been sent successfully.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    height: 1.5,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  'We’ll let you know when the doctor accepts.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 12.5,
                    height: 1.45,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                ),

                const SizedBox(height: 26),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                    },
                    style: FilledButton.styleFrom(
                      elevation: 0,
                      backgroundColor: AppColors.brand,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    child: Text(
                      'Done',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
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

  // ===========================================================================
  // LOW BALANCE DIALOG
  // ===========================================================================

 Future<void> _showLowBalanceDialog({
  required double shortfall,
}) {
  final fee = doctor.consultationFee;

  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.50),
    builder: (dialogContext) {
      return Dialog(
        elevation: 0,
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon with "add" badge
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF2F2F3),
                      shape: BoxShape.circle,
                    ),
                    child: const AppIcon(
                      Icons.account_balance_wallet_rounded,
                      size: 28,
                      color: Color(0xFF6B6D76), // medium grey, not black
                    ),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: const Color(0xFF9B9DA5), // muted grey badge
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                      ),
                      child: const AppIcon(
                        Icons.add_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              Text(
                'Top up to continue',
                style: GoogleFonts.outfit(
                  fontSize: 19,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.3,
                  color: const Color(0xFF1C1C1E), // near-black, not pure black
                ),
              ),

              const SizedBox(height: 4),

              if (fee != null && fee > 0)
                Text(
                  'Consultation fee is Rs. ${_formatAmount(fee)}',
                  style: GoogleFonts.outfit(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF9B9DA5),
                  ),
                ),

              const SizedBox(height: 20),

              // Single amount focus block
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7F8),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Text(
                      'ADD AT LEAST',
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.8,
                        color: const Color(0xFF9B9DA5),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Rs. ${_formatAmount(shortfall)}',
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.4,
                        color: const Color(0xFF1C1C1E),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFE2E2E4)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF6B6D76),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                 Expanded(
  flex: 2,
  child: SizedBox(
    height: 48,
    child: FilledButton(
      onPressed: () {
        Navigator.pop(dialogContext);
        // TODO: navigate to add-funds flow
      },
      style: FilledButton.styleFrom(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        side: const BorderSide(color: Color(0xFFE2E2E4), width: 1.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
        ),
      ),
      child: Text(
        'Add Funds',
        style: GoogleFonts.outfit(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
  ),
),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
 
  // ===========================================================================
  // PROFILE PHOTO DIALOG
  // ===========================================================================

  void _showProfilePhoto() {
    if (!_hasImage) return;

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.90),
      builder: (dialogContext) {
        return Dialog(
          elevation: 0,
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 46,
          ),
          child: Stack(
            alignment: Alignment.topRight,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: CachedNetworkImage(
                    imageUrl: doctor.profileImage!,
                    width: double.infinity,
                    fit: BoxFit.contain,
                    errorWidget: (_, _, _) {
                      return Container(
                        height: 380,
                        color: const Color(0xFF202124),
                        alignment: Alignment.center,
                        child: const AppIcon(
                          Icons.person_rounded,
                          size: 72,
                          color: Colors.white54,
                        ),
                      );
                    },
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(10),
                child: Material(
                  color: Colors.black.withValues(alpha: 0.52),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      Navigator.pop(dialogContext);
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(9),
                      child: AppIcon(
                        Icons.close_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  double? _extractWalletShortfall(String message) {
    final match = RegExp(
      r'Add Rs\.?\s*([\d,]+(?:\.\d+)?)\s*more',
      caseSensitive: false,
    ).firstMatch(message);

    if (match == null) return null;

    final value = match.group(1)?.replaceAll(',', '');

    return double.tryParse(value ?? '');
  }

  String _readableError(Object error) {
    return AppErrorMessage.from(error);
  }

  String _formatAmount(double amount) {
    final value = amount.toStringAsFixed(0);

    return value.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]},',
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          elevation: 0,
          backgroundColor: isError
              ? const Color(0xFF3C2020)
              : const Color(0xFF22252A),
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: Text(
            message,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ),
      );
  }

  // ===========================================================================
  // SCREEN
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),

      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 56,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: IconButton(
            onPressed: () {
              Navigator.pop(context);
            },
            icon: const AppIcon(Icons.arrow_back_rounded, size: 23),
            color: AppColors.textPrimary,
          ),
        ),
        titleSpacing: 2,
        title: Text(
          'Doctor profile',
          style: GoogleFonts.outfit(
            fontSize: 17,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
      ),

      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 28),
        child: Column(
          children: [
            _DoctorHero(
              doctor: doctor,
              onPhotoTap: _showProfilePhoto,
              onVideoTap: _hasVideo
                  ? () {
                      showDoctorVideoDialog(context, doctor);
                    }
                  : null,
            ),

            const SizedBox(height: 14),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _DarmaanVerification(isVerified: doctor.isDoctorVerified),

                  const SizedBox(height: 14),

                  _PatientReviewsSection(doctor: doctor),
                ],
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),

      bottomNavigationBar: _buildBottomAction(),
    );
  }

  // ===========================================================================
  // BOTTOM ACTION
  // ===========================================================================

  Widget _buildBottomAction() {
    if (_isCheckingBooking) {
      return const _BottomShell(
        child: SizedBox(
          height: 50,
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    final booking = _activeBooking;

    // Pending
    if (booking != null && booking.status == BookingStatus.pending) {
      return _BottomShell(
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.brand.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: AppIcon(
                      Icons.schedule_rounded,
                      size: 19,
                      color: AppColors.brand,
                    ),
                  ),

                  const SizedBox(width: 11),

                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Request sent',
                          style: GoogleFonts.outfit(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),

                        const SizedBox(height: 2),

                        Text(
                          'Waiting for doctor',
                          style: GoogleFonts.outfit(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            if (_canCancelPending)
              SizedBox(
                height: 40,
                child: FilledButton(
                  onPressed: _isCancelling ? null : _cancelAppointment,
                  style: FilledButton.styleFrom(
                    elevation: 0,
                    backgroundColor: const Color(0xFFF2F4F6),
                    foregroundColor: AppColors.textPrimary,
                    disabledBackgroundColor: const Color(0xFFF2F4F6),
                    disabledForegroundColor: AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  child: _isCancelling
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 1.8),
                        )
                      : Text(
                          'Cancel',
                          style: GoogleFonts.outfit(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
              )
            else
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 11),
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      Icons.timer_outlined,
                      size: 16,
                      color: AppColors.brand,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _cancellationRemaining == null
                          ? 'Syncing...'
                          : 'Cancel in ${_formatCancellationRemaining(_cancellationRemaining)}',
                      style: GoogleFonts.outfit(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.brand,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    // Accepted
    if (booking != null && booking.status == BookingStatus.accepted) {
      return _ActiveBookingBar(
        bookingId: booking.id,
        icon: Icons.check_circle_outline_rounded,
        title: 'Appointment confirmed',
        subtitle: 'The doctor accepted your request',
        onMessage: () => _openChat(booking),
      );
    }

    // In progress
    if (booking != null && booking.status == BookingStatus.inProgress) {
      return _ActiveBookingBar(
        bookingId: booking.id,
        icon: Icons.videocam_outlined,
        title: 'Consultation in progress',
        subtitle: 'Your consultation has started',
        onMessage: () => _openChat(booking),
      );
    }

    if (booking?.hasUpcomingFollowUp == true) {
      final date = booking!.followUpDate!;
      final paidBooking = _activePaidBooking;
      final multipleFollowUps = _activeFollowUps.length > 1;
      return _FollowUpActionBar(
        bookingId: booking.id,
        title: multipleFollowUps
            ? '${_activeFollowUps.length} follow-ups'
            : booking.isFollowUpOpen
            ? 'Follow-up open'
            : 'Follow-up ${DateFormat('d MMM yyyy').format(date)}',
        subtitle: multipleFollowUps
            ? 'Choose the chat by follow-up date'
            : booking.isFollowUpOpen
            ? 'Free follow-up chat is available'
            : 'Chat unlocks on the follow-up date',
        chatLabel: multipleFollowUps
            ? 'View chats'
            : booking.isFollowUpOpen
                ? 'Message'
                : 'View chat',
        onMessage: _openFollowUpChat,
        bookingLabel: paidBooking == null
            ? (doctor.isAvailable ? 'Request new' : 'Doctor offline')
            : paidBooking.status == BookingStatus.pending
                ? 'View request'
                : 'View consult',
        onBookNew: paidBooking != null
            ? () => _openPaidConsultation(paidBooking)
            : doctor.isAvailable
                ? _bookNewConsultation
                : null,
      );
    }

    // Normal state
    return _BottomShell(
      child: Row(
        children: [
          Expanded(child: _Fee(fee: doctor.consultationFee)),

          const SizedBox(width: 18),

          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: doctor.isAvailable && !_isBooking
                  ? _bookAppointment
                  : null,
              style: FilledButton.styleFrom(
                elevation: 0,
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE3E5E8),
                disabledForegroundColor: const Color(0xFF9398A0),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              child: _isBooking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      doctor.isAvailable ? 'Book consultation' : 'Doctor offline',
                      style: GoogleFonts.outfit(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancellationTimer?.cancel();
    _timeSinceServerSync.stop();
    super.dispose();
  }
}

// =============================================================================
// DOCTOR HERO
// =============================================================================

class _DoctorHero extends StatelessWidget {
  final UserModel doctor;
  final VoidCallback onPhotoTap;
  final VoidCallback? onVideoTap;

  const _DoctorHero({
    required this.doctor,
    required this.onPhotoTap,
    required this.onVideoTap,
  });

  bool get _hasImage =>
      doctor.profileImage != null && doctor.profileImage!.trim().isNotEmpty;

  bool _hasText(String? value) {
    return value != null && value.trim().isNotEmpty;
  }

  String get _doctorSubtitle {
    final specialization = _hasText(doctor.specialization)
        ? doctor.specialization!.trim()
        : null;

    final title = _hasText(doctor.title) ? doctor.title!.trim() : null;

    if (specialization != null && title != null) {
      return '$specialization  |  $title';
    }

    if (specialization != null) {
      return specialization;
    }

    if (title != null) {
      return title;
    }

    return 'Doctor';
  }

  String? get _genderLabel {
    final value = doctor.gender?.trim();
    if (value == null || value.isEmpty) return null;
    return '${value[0].toUpperCase()}${value.substring(1).toLowerCase()}';
  }

  String get _rating {
    final rating = (doctor.doctorRating as num?)?.toDouble() ?? 0;

    if (rating > 0) {
      return rating.toStringAsFixed(1);
    }

    return '0.0';
  }

  String get _experience {
    if (doctor.experienceYears == null) {
      return 'New';
    }

    return '${doctor.experienceYears} yrs';
  }

  String get _consultations {
    final count = doctor.doctorCompletedConsultationCount;

    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }

    return '$count';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 25, 22, 22),
            child: Column(
              children: [
                // -------------------------------------------------------------
                // PHOTO
                // -------------------------------------------------------------
                GestureDetector(
                  onTap: onPhotoTap,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 110,
                    height: 110,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFE5E8EC)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.055),
                          blurRadius: 20,
                          offset: const Offset(0, 7),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Container(
                        color: const Color(0xFFF0F2F4),
                        child: _hasImage
                            ? CachedNetworkImage(
                                imageUrl: doctor.profileImage!,
                                fit: BoxFit.cover,
                                errorWidget: (_, _, _) {
                                  return AppIcon(
                                    Icons.person_rounded,
                                    size: 46,
                                    color: AppColors.textSecondary,
                                  );
                                },
                              )
                            : AppIcon(
                                Icons.person_rounded,
                                size: 46,
                                color: AppColors.textSecondary,
                              ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                // -------------------------------------------------------------
                // NAME + VERIFIED
                // -------------------------------------------------------------
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        doctor.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          height: 1.15,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.45,
                        ),
                      ),
                    ),

                    if (doctor.isDoctorVerified) ...[
                      const SizedBox(width: 6),

                      AppIcon(
                        Icons.verified_rounded,
                        size: 19,
                        color: AppColors.brand,
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 6),

                // -------------------------------------------------------------
                // SPECIALIZATION | TITLE
                // -------------------------------------------------------------
                Text(
                  _doctorSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                ),

                if (_genderLabel != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F5F7),
                      borderRadius: BorderRadius.circular(20),
                      
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon(
                          Icons.person_outline_rounded,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _genderLabel!,
                          style: GoogleFonts.outfit(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 13),

                // -------------------------------------------------------------
                // AVAILABILITY
                // -------------------------------------------------------------
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: doctor.isAvailable
                            ? const Color(0xFF18A957)
                            : const Color(0xFFA7ACB4),
                        shape: BoxShape.circle,
                      ),
                    ),

                    const SizedBox(width: 7),

                    Text(
                      doctor.isAvailable
                          ? 'Available now'
                          : 'Currently unavailable',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: doctor.isAvailable
                            ? const Color(0xFF16894A)
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // -------------------------------------------------------------
                // STATS
                // -------------------------------------------------------------
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F8FA),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _HeroStat(
                          value: _rating,
                          label: 'Rating',
                          icon: Icons.star_rounded,
                          iconColor: const Color(0xFFFFB400),
                        ),
                      ),

                      const _HeroDivider(),

                      Expanded(
                        child: _HeroStat(
                          value: _experience,
                          label: 'Experience',
                        ),
                      ),

                      const _HeroDivider(),

                      Expanded(
                        child: _HeroStat(
                          value: _consultations,
                          label: 'Consultations',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // -------------------------------------------------------------------
          // INTRO VIDEO
          //
          // Deliberately kept away from the edges.
          // -------------------------------------------------------------------
          if (onVideoTap != null)
            Positioned(
              top: 24,
              right: 24,
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onVideoTap,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.brand,
                      border: Border.all(color: const Color(0xFFE2E5E9)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.045),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: AppIcon(
                      Icons.play_arrow_rounded,
                      size: 25,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// HERO STATS
// =============================================================================

class _HeroStat extends StatelessWidget {
  final String value;
  final String label;
  final IconData? icon;
  final Color? iconColor;

  const _HeroStat({
    required this.value,
    required this.label,
    this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              AppIcon(icon, size: 16, color: iconColor ?? AppColors.brand),

              const SizedBox(width: 4),
            ],

            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.15,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 4),

        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 10.5,
            fontWeight: FontWeight.w400,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _HeroDivider extends StatelessWidget {
  const _HeroDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 34, color: const Color(0xFFE3E5E8));
  }
}

// =============================================================================
// DARMAAN VERIFICATION
// =============================================================================

class _DarmaanVerification extends StatelessWidget {
  final bool isVerified;

  const _DarmaanVerification({required this.isVerified});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(13),
            ),
            child: AppIcon(
              Icons.verified_user_outlined,
              size: 20,
              color: AppColors.brand,
            ),
          ),

          const SizedBox(width: 13),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Darman verification',
                  style: GoogleFonts.outfit(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  isVerified
                      ? 'Identity and credentials verified'
                      : 'Verification pending',
                  style: GoogleFonts.outfit(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          if (isVerified)
            AppIcon(Icons.verified_rounded, size: 18, color: AppColors.brand),
        ],
      ),
    );
  }
}

// =============================================================================
// PATIENT REVIEWS
//
// Dummy data for UI development.
// Later, replace _dummyReviews with your real Supabase reviews.
// =============================================================================

class _PatientReviewsSection extends StatefulWidget {
  const _PatientReviewsSection({required this.doctor});
  final UserModel doctor;

  @override
  State<_PatientReviewsSection> createState() => _PatientReviewsSectionState();
}

class _PatientReviewsSectionState extends State<_PatientReviewsSection> {
  final _repository = PatientRepository();
  late final Future<
    ({DoctorReviewSummaryModel summary, List<ConsultationReviewModel> reviews})
  >
  _data = _load();

  Future<
    ({DoctorReviewSummaryModel summary, List<ConsultationReviewModel> reviews})
  >
  _load() async {
    final results = await Future.wait([
      _repository.getDoctorReviewSummary(widget.doctor.uid),
      _repository.getDoctorReviews(widget.doctor.uid, limit: 15),
    ]);
    return (
      summary: results[0] as DoctorReviewSummaryModel,
      reviews: results[1] as List<ConsultationReviewModel>,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<
      ({
        DoctorReviewSummaryModel summary,
        List<ConsultationReviewModel> reviews,
      })
    >(
      future: _data,
      builder: (context, snapshot) {
        final reviews =
            (snapshot.data?.reviews ?? const <ConsultationReviewModel>[])
                .map(
                  (review) => _ReviewData(
                    name: review.patientName,
                    rating: review.rating,
                    text: review.review ?? 'No written comment.',
                    time: DateFormat(
                      'd MMM yyyy',
                    ).format(review.createdAt.toLocal()),
                  ),
                )
                .toList();
        final summary = snapshot.data?.summary;
        final rating = summary?.averageRating ?? 0;

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ===================================================================
              // HEADER
              // ===================================================================
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                child: Text(
                  'Patient reviews',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
              ),

              // ===================================================================
              // RATING SUMMARY
              // ===================================================================
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 17,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // -----------------------------------------------------------
                      // SCORE
                      // -----------------------------------------------------------
                      SizedBox(
                        width: 88,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  rating.toStringAsFixed(1),
                                  style: GoogleFonts.outfit(
                                    fontSize: 28,
                                    height: 1,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textPrimary,
                                    letterSpacing: -0.8,
                                  ),
                                ),

                                const SizedBox(width: 5),

                                const AppIcon(
                                  Icons.star_rounded,
                                  size: 20,
                                  color: Color(0xFFFFB400),
                                ),
                              ],
                            ),

                            const SizedBox(height: 7),

                            Text(
                              '${summary?.reviewCount ?? 0} reviews',
                              style: GoogleFonts.outfit(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w400,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),

                      Container(
                        width: 1,
                        height: 62,
                        margin: const EdgeInsets.symmetric(horizontal: 15),
                        color: const Color(0xFFE4E6E9),
                      ),

                      // -----------------------------------------------------------
                      // DISTRIBUTION
                      // -----------------------------------------------------------
                      Expanded(
                        child: Column(
                          children: [
                            for (var stars = 5; stars >= 1; stars--) ...[
                              _RatingBar(
                                stars: stars,
                                value: summary?.fractionFor(stars) ?? 0,
                              ),
                              if (stars != 1) const SizedBox(height: 7),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const Divider(height: 1, thickness: 1, color: Color(0xFFF0F1F3)),

              // ===================================================================
              // REVIEWS
              // ===================================================================
              if (snapshot.connectionState != ConnectionState.done)
                const AppSectionShimmer(height: 190)
              else if (reviews.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No reviews yet.',style: TextStyle(color: Colors.black,fontSize: 13),)),
                ),
              for (int index = 0; index < reviews.length; index++) ...[
                _ReviewItem(review: reviews[index]),

                if (index != reviews.length - 1)
                  const Padding(
                    padding: EdgeInsets.only(left: 64, right: 18),
                    child: Divider(
                      height: 1,
                      thickness: 1,
                      color: Color(0xFFF1F2F4),
                    ),
                  ),
              ],

              // ===================================================================
              // VIEW ALL
              // ===================================================================
              if ((summary?.reviewCount ?? 0) > 0) ...[
              const Divider(height: 1, thickness: 1, color: Color(0xFFF0F1F3)),

              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                DoctorReviewsScreen(doctor: widget.doctor),
                          ),
                        ),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 15,
                    ),
                    child: Row(
                      children: [
                        Text(
                          'View all reviews',
                          style: GoogleFonts.outfit(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.black,
                          ),
                        ),

                        const Spacer(),

                        AppIcon(
                          Icons.arrow_forward_rounded,
                          size: 17,
                          color: Colors.black,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// =============================================================================
// RATING BAR
// =============================================================================

class _RatingBar extends StatelessWidget {
  final int stars;
  final double value;

  const _RatingBar({required this.stars, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 13,
          child: Text(
            '$stars',
            style: GoogleFonts.outfit(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ),

        const SizedBox(width: 4),

        const AppIcon(Icons.star_rounded, size: 11, color: Color(0xFFFFB400)),

        const SizedBox(width: 7),

        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                Container(height: 5, color: const Color(0xFFE5E7EA)),

                FractionallySizedBox(
                  widthFactor: value,
                  child: Container(
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB400),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// REVIEW DATA
// =============================================================================

class _ReviewData {
  final String name;
  final int rating;
  final String text;
  final String time;

  const _ReviewData({
    required this.name,
    required this.rating,
    required this.text,
    required this.time,
  });
}

// =============================================================================
// REVIEW ITEM
// =============================================================================

class _ReviewItem extends StatelessWidget {
  final _ReviewData review;

  const _ReviewItem({required this.review});

  String get _initial {
    final name = review.name.trim();

    if (name.isEmpty) {
      return '?';
    }

    return name.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 17),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ===================================================================
          // AVATAR
          // ===================================================================
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F3F5),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE7E9EC)),
            ),
            alignment: Alignment.center,
            child: Text(
              _initial,
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),

          const SizedBox(width: 11),

          // ===================================================================
          // CONTENT
          // ===================================================================
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // -------------------------------------------------------------
                // NAME + TIME
                // -------------------------------------------------------------
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        review.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),

                    const SizedBox(width: 10),

                    Text(
                      review.time,
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 4),

                // -------------------------------------------------------------
                // VERIFIED PATIENT
                // -------------------------------------------------------------
                Row(
                  children: [
                    AppIcon(
                      Icons.check_circle_rounded,
                      size: 13,
                      color: AppColors.brand,
                    ),

                    const SizedBox(width: 4),

                    Text(
                      'Verified patient',
                      style: GoogleFonts.outfit(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // -------------------------------------------------------------
                // STAR RATING
                // -------------------------------------------------------------
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(5, (index) {
                    return Padding(
                      padding: EdgeInsets.only(right: index == 4 ? 0 : 2),
                      child: AppIcon(
                        Icons.star_rounded,
                        size: 14,
                        color: index < review.rating
                            ? const Color(0xFFFFB400)
                            : const Color(0xFFE2E4E7),
                      ),
                    );
                  }),
                ),

                const SizedBox(height: 9),

                // -------------------------------------------------------------
                // REVIEW TEXT
                // -------------------------------------------------------------
                Text(
                  review.text,
                  style: GoogleFonts.outfit(
                    fontSize: 12.2,
                    height: 1.52,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF50565F),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// BOTTOM SHELL
// =============================================================================

class _BottomShell extends StatelessWidget {
  final Widget child;

  const _BottomShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE8EAEE))),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(18, 11, 18, 11),
        child: child,
      ),
    );
  }
}

// =============================================================================
// CONSULTATION FEE
// =============================================================================

class _Fee extends StatelessWidget {
  final double? fee;

  const _Fee({required this.fee});

  @override
  Widget build(BuildContext context) {
    final hasFee = fee != null && fee! > 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Consultation fee',
          style: GoogleFonts.outfit(
            fontSize: 10.5,
            fontWeight: FontWeight.w400,
            color: AppColors.textSecondary,
          ),
        ),

        const SizedBox(height: 2),

        Text(
          hasFee ? 'Rs. ${_formatFee(fee!)}' : 'Not listed',
          style: GoogleFonts.outfit(
            fontSize: 17,
            height: 1.15,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
            letterSpacing: -0.25,
          ),
        ),
      ],
    );
  }

  String _formatFee(double amount) {
    final value = amount.toStringAsFixed(0);

    return value.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]},',
    );
  }
}

// =============================================================================
// ACTIVE BOOKING BAR
// =============================================================================

class _FollowUpActionBar extends StatelessWidget {
  const _FollowUpActionBar({
    required this.bookingId,
    required this.title,
    required this.subtitle,
    required this.chatLabel,
    required this.bookingLabel,
    required this.onMessage,
    required this.onBookNew,
  });

  final String bookingId;
  final String title;
  final String subtitle;
  final String chatLabel;
  final String bookingLabel;
  final VoidCallback onMessage;
  final VoidCallback? onBookNew;

  @override
  Widget build(BuildContext context) {
    return _BottomShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const AppIcon(
                  Icons.event_repeat_rounded,
                  size: 19,
                  color: Color(0xFF175CD3),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: FilledButton.icon(
                    onPressed: onMessage,
                    icon: UnreadMessageBadge(
                      bookingId: bookingId,
                      isDoctor: false,
                      child: const AppIcon(
                        Icons.chat_bubble_outline_rounded,
                        size: 16,
                      ),
                    ),
                    label: Text(chatLabel),
                    style: FilledButton.styleFrom(
                      elevation: 0,
                      backgroundColor: const Color(0xFFF2F4F6),
                      foregroundColor: AppColors.textPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: FilledButton(
                    onPressed: onBookNew,
                    style: FilledButton.styleFrom(
                      elevation: 0,
                      backgroundColor: AppColors.brand,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFE3E5E8),
                      disabledForegroundColor: const Color(0xFF9398A0),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                    child: Text(
                      bookingLabel,
                      style: GoogleFonts.outfit(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActiveBookingBar extends StatelessWidget {
  final String bookingId;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onMessage;

  const _ActiveBookingBar({
    required this.bookingId,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    return _BottomShell(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: AppIcon(icon, size: 19, color: AppColors.brand),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),

                const SizedBox(height: 2),

                Text(
                  subtitle,
                  style: GoogleFonts.outfit(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 40,
            child: FilledButton.icon(
              onPressed: onMessage,
              icon: UnreadMessageBadge(
                bookingId: bookingId,
                isDoctor: false,
                child: const AppIcon(
                  Icons.chat_bubble_outline_rounded,
                  size: 17,
                ),
              ),
              label: const Text('Message'),
              style: FilledButton.styleFrom(
                elevation: 0,
                backgroundColor: const Color(0xFFF2F4F6),
                foregroundColor: AppColors.textPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// CANCEL BOTTOM SHEET
// =============================================================================

class _CancelSheet extends StatelessWidget {
  final String doctorName;
  final VoidCallback onKeep;
  final VoidCallback onCancel;

  const _CancelSheet({
    required this.doctorName,
    required this.onKeep,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFDADDE1),
              borderRadius: BorderRadius.circular(100),
            ),
          ),

          const SizedBox(height: 24),

          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Color(0xFFFDF2F2),
              shape: BoxShape.circle,
            ),
            child: const AppIcon(
              Icons.event_busy_outlined,
              size: 21,
              color: Color(0xFFB42318),
            ),
          ),

          const SizedBox(height: 16),

          Text(
            'Cancel appointment?',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'Your request with $doctorName will be cancelled. Any reserved consultation fee will return to your wallet.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 13,
              height: 1.5,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
            ),
          ),

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 47,
            child: FilledButton(
              onPressed: onKeep,
              style: FilledButton.styleFrom(
                elevation: 0,
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Keep appointment',
                style: GoogleFonts.outfit(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          const SizedBox(height: 5),

          SizedBox(
            width: double.infinity,
            height: 43,
            child: TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFB42318),
              ),
              child: Text(
                'Yes, cancel',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
