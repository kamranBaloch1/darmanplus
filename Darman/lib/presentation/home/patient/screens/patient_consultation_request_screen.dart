import 'dart:async';

import 'package:darmaan/core/models/booking_model.dart';
import 'package:darmaan/core/models/user_model.dart';
import 'package:darmaan/core/theme/app_colors.dart';
import 'package:darmaan/presentation/home/chat/chat_room.dart';
import 'package:darmaan/presentation/home/patient/repository/patient_repository.dart';
import 'package:darmaan/presentation/home/patient/screens/doctor_details_screen.dart';
import 'package:darmaan/widgets/guest_access.dart';
import 'package:darmaan/widgets/app_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

class PatientConsultationRequestScreen extends StatefulWidget {
  const PatientConsultationRequestScreen({
    super.key,
    required this.doctor,
    this.startNewConsultation = false,
    this.initialBooking,
  });

  final UserModel doctor;
  final bool startNewConsultation;
  final BookingModel? initialBooking;

  @override
  State<PatientConsultationRequestScreen> createState() =>
      _PatientConsultationRequestScreenState();
}

class _PatientConsultationRequestScreenState
    extends State<PatientConsultationRequestScreen> with WidgetsBindingObserver {
  static const _patientCancellationDelay = Duration(minutes: 30);

  final PatientRepository _repository = PatientRepository();
  StreamSubscription<BookingModel>? _bookingSubscription;
  Timer? _countdownTimer;
  DateTime? _serverTimeAtSync;
  final Stopwatch _timeSinceServerSync = Stopwatch();

  BookingModel? _booking;
  UserModel? _patient;
  bool _loading = true;
  bool _requesting = false;
  bool _cancelling = false;
  String? _error;

  UserModel get doctor => widget.doctor;
  bool get _isGuest => Supabase.instance.client.auth.currentUser == null;
  bool get _isPending => _booking?.status == BookingStatus.pending;
  bool get _chatUnlocked =>
      _booking?.status == BookingStatus.accepted ||
      _booking?.status == BookingStatus.inProgress ||
      _booking?.isFollowUpOpen == true;

  String get _subtitle {
    final values = [doctor.specialization, doctor.title]
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    return values.isEmpty ? 'Doctor' : values.join(' | ');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isPending) {
      _syncServerClock();
    }
  }

  DateTime? get _estimatedServerNow {
    final synced = _serverTimeAtSync;
    return synced == null ? null : synced.add(_timeSinceServerSync.elapsed);
  }

  Duration? get _cancellationRemaining {
    final booking = _booking;
    final serverNow = _estimatedServerNow;
    if (booking == null || !_isPending || serverNow == null) return null;
    final remaining = booking.createdAt
        .add(_patientCancellationDelay)
        .difference(serverNow);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool get _canCancelPendingRequest =>
      _isPending && _cancellationRemaining == Duration.zero;

  Future<void> _syncServerClock() async {
    try {
      final serverNow = await _repository.getConsultationServerTime();
      if (!mounted) return;
      _serverTimeAtSync = serverNow;
      _timeSinceServerSync
        ..reset()
        ..start();
      _startCountdown();
      setState(() {});
    } catch (error) {
      if (mounted && _isPending) _show(_message(error));
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    if (!_isPending) return;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !_isPending) {
        timer.cancel();
        return;
      }
      setState(() {});
      if (timer.tick % 60 == 0) _syncServerClock();
    });
  }

  Future<void> _load() async {
    try {
      final booking = widget.initialBooking ??
          (widget.startNewConsultation
              ? null
              : await _repository.getActiveBooking(doctorId: doctor.uid));
      UserModel? patient;
      if (!_isGuest) patient = await _repository.getPatientProfile();
      if (!mounted) return;
      setState(() {
        _booking = booking;
        _patient = patient;
        _loading = false;
      });
      if (booking != null) {
        _watch(booking.id);
        if (booking.status == BookingStatus.pending) await _syncServerClock();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _message(error);
      });
    }
  }

  void _watch(String bookingId) {
    _bookingSubscription?.cancel();
    _bookingSubscription = _repository.watchBooking(bookingId).listen(
      (booking) {
        if (!mounted) return;
        setState(() => _booking = booking);
      },
      onError: (Object error) {
        if (mounted) _show(_message(error));
      },
    );
  }

  Future<void> _requestConsultation() async {
    if (_requesting) return;
    if (_isGuest) {
      await showLoginRequiredDialog(
        context,
        title: 'Login to request a consultation',
        message: 'Please login before sending a consultation request to ${doctor.name}.',
      );
      return;
    }

    final displayedFee = doctor.consultationFee ?? 0;
    final displayedBalance = _patient?.walletBalance;
    if (displayedBalance != null && displayedBalance < displayedFee) {
      await _showLowBalanceDialog(
        requiredAmount: displayedFee,
        availableBalance: displayedBalance,
        shortfall: displayedFee - displayedBalance,
      );
      return;
    }

    setState(() => _requesting = true);
    try {
      final booking = await _repository.createBooking(doctorId: doctor.uid);
      if (!mounted) return;
      setState(() => _booking = booking);
      _watch(booking.id);
      await _syncServerClock();
    } catch (error) {
      if (!mounted) return;
      if (error is InsufficientWalletBalanceException) {
        setState(() => _requesting = false);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        await _showLowBalanceDialog(
          requiredAmount: error.requiredAmount,
          availableBalance: error.availableBalance,
          shortfall: error.shortfall,
        );
      } else {
        _show(_message(error));
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _showLowBalanceDialog({
    required double requiredAmount,
    required double availableBalance,
    required double shortfall,
  }) async {
    if (!mounted) return;
    final money = NumberFormat('#,##0.##');
    final safeRequired = requiredAmount.isFinite ? requiredAmount : 0.0;
    final safeAvailable = availableBalance.isFinite ? availableBalance : 0.0;
    final safeShortfall = shortfall.isFinite && shortfall > 0
        ? shortfall
        : (safeRequired - safeAvailable).clamp(0.0, double.infinity).toDouble();

    await showDialog<void>(
      context: context,
      useRootNavigator: false,
      barrierColor: Colors.black.withValues(alpha: 0.48),
      builder: (dialogContext) => Dialog(
        elevation: 0,
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 27, 22, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: AppColors.brand,
                  size: 27,
                ),
              ),
              const SizedBox(height: 17),
              Text(
                'Insufficient wallet balance',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 19,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'Add funds to your wallet before requesting this consultation.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F8FA),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  children: [
                    _BalanceDialogRow(
                      label: 'Consultation fee',
                      value: 'Rs. ${money.format(safeRequired)}',
                    ),
                    const Divider(height: 22, color: Color(0xFFE7EAEE)),
                    _BalanceDialogRow(
                      label: 'Wallet balance',
                      value: 'Rs. ${money.format(safeAvailable)}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.055),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Column(
                  children: [
                    Text(
                      'AMOUNT NEEDED',
                      style: GoogleFonts.outfit(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.8,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Rs. ${money.format(safeShortfall)}',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  style: FilledButton.styleFrom(
                    elevation: 0,
                    backgroundColor: const Color(0xFFF2F4F6),
                    foregroundColor: AppColors.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: Text(
                    'Got it',
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

 // Drop-in replacement for _cancelRequest(). Assumes the surrounding class
// already has: _booking, _cancelling, doctor, _repository,
// _bookingSubscription, _show(), _message(), and the usual
// AppColors / GoogleFonts imports used elsewhere in this file.

  Future<void> _cancelRequest() async {
  final booking = _booking;
  if (booking == null || _cancelling) return;
  if (!_canCancelPendingRequest) {
    _show('Cancellation becomes available after the 30-minute waiting period.');
    return;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .5),
    builder: (dialogContext) => Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: Color(0xFFFCEEED),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.event_busy_rounded,
                color: Color(0xFFE0503C),
                size: 26,
              ),
            ),
            const SizedBox(height: 17),
            Text(
              'Cancel consultation request?',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your request to ${doctor.name} will be cancelled and the reserved fee will return to your wallet.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 13,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                // Cancel request — de-emphasized, outlined, left side.
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE3E7EC)),
                        foregroundColor: AppColors.textSecondary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.outfit(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Keep request — primary action, filled brand color, right side.
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.brand,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: Text(
                        'Keep request',
                        style: GoogleFonts.outfit(
                          fontSize: 13.5,
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
    ),
  );

  if (confirmed != true || !mounted) return;

  setState(() => _cancelling = true);
  try {
    await _repository.cancelPendingBooking(booking.id);
    await _bookingSubscription?.cancel();
    if (!mounted) return;
    setState(() => _booking = null);
    _show('Consultation request cancelled.');
  } catch (error) {
    if (mounted) _show(_message(error));
  } finally {
    if (mounted) setState(() => _cancelling = false);
  }
}

  void _openDoctorProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DoctorDetailsScreen(doctor: doctor)),
    );
  }

  void _show(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.black87,
        ),
      );
  }

  String _message(Object error) {
    // Keep the exact server message on this screen while the booking path is
    // being diagnosed. The global error formatter intentionally hides
    // technical Supabase errors behind a generic message.
    if (error is PostgrestException) {
      return error.message.trim().isEmpty
          ? 'Something went wrong. Please try again.'
          : error.message.trim();
    }

    var message = error.toString().trim();
    while (message.startsWith('Exception: ')) {
      message = message.substring('Exception: '.length).trim();
    }
    return message.isEmpty
        ? 'Something went wrong. Please try again.'
        : message;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _timeSinceServerSync.stop();
    _bookingSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_chatUnlocked) {
      return ChatRoomScreen(
        bookingId: _booking!.id,
        peerName: doctor.name,
        peerAvatarUrl: doctor.profileImage,
        peerSubtitle: _subtitle,
        peerVerified: doctor.isDoctorVerified,
        onPeerTap: _openDoctorProfile,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFD),
      appBar: _appBar(),
      body: _loading
          ? const AppProfileShimmer()
          : _error != null
              ? _ErrorState(message: _error!, retry: _load)
              : _LockedBody(
                  doctorName: doctor.name,
                  pending: _isPending,
                  isNewConsultation:
                      widget.startNewConsultation && _booking == null,
                  cancelling: _cancelling,
                  cancellationRemaining: _cancellationRemaining,
                  serverTimeReady: _serverTimeAtSync != null,
                  onCancel: _cancelRequest,
                ),
      bottomNavigationBar: _loading || _error != null
          ? null
          : _isPending
              ? const _LockedComposer()
              : _RequestPanel(
                  fee: doctor.consultationFee ?? 0,
                  balance: _patient?.walletBalance,
                  requesting: _requesting,
                  doctorAvailable: doctor.isAvailable,
                  onRequest: _requestConsultation,
                ),
    );
  }

  PreferredSizeWidget _appBar() => AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: .5,
        toolbarHeight: 70,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        titleSpacing: 0,
        title: InkWell(
          onTap: _openDoctorProfile,
          borderRadius: BorderRadius.circular(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFF1F3F5),
                backgroundImage: doctor.profileImage?.trim().isNotEmpty == true
                    ? CachedNetworkImageProvider(doctor.profileImage!)
                    : null,
                child: doctor.profileImage?.trim().isNotEmpty == true
                    ? null
                    : const Icon(Icons.person_rounded, color: AppColors.brand),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            doctor.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (doctor.isDoctorVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified_rounded,
                            size: 16,
                            color: AppColors.brand,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 10.8,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _BalanceDialogRow extends StatelessWidget {
  const _BalanceDialogRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      );
}

class _LockedBody extends StatelessWidget {
  const _LockedBody({
    required this.doctorName,
    required this.pending,
    required this.isNewConsultation,
    required this.cancelling,
    required this.cancellationRemaining,
    required this.serverTimeReady,
    required this.onCancel,
  });

  final String doctorName;
  final bool pending;
  final bool isNewConsultation;
  final bool cancelling;
  final Duration? cancellationRemaining;
  final bool serverTimeReady;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F4F6),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                'Today',
                style: GoogleFonts.outfit(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          if (pending) ...[
            const SizedBox(height: 22),
            Container(
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(17),
           
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    pending ? Icons.videocam_rounded : Icons.lock_outline_rounded,
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
                        pending
                            ? 'Consultation request sent'
                            : 'This consultation has not started yet',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pending
                            ? 'We notified $doctorName. Chat will unlock when the doctor accepts.'
                            : 'Send a request to start chatting with $doctorName.',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          height: 1.4,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            ),
            const SizedBox(height: 82),
          ] else
            const SizedBox(height: 100),
          Center(
            child: Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 22,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(
                pending
                    ? Icons.schedule_rounded
                    : isNewConsultation
                        ? Icons.medical_services_outlined
                        : Icons.lock_rounded,
                size: 34,
                color: AppColors.brand,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            pending
                ? 'Waiting for doctor’s response'
                : isNewConsultation
                    ? 'Start a new consultation'
                    : 'Chat is locked',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            pending
                ? 'Most doctors respond within a few minutes. We’ll notify you here.'
                : isNewConsultation
                    ? 'This creates a separate paid consultation with $doctorName. Your existing follow-ups stay unchanged.'
                    : 'You can’t send messages or make calls yet. Request a consultation to connect with $doctorName.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 13,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
          if (pending) ...[
            const SizedBox(height: 22),
            Center(
              child: _CancellationAvailability(
                remaining: cancellationRemaining,
                serverTimeReady: serverTimeReady,
                cancelling: cancelling,
                onCancel: onCancel,
              ),
            ),
          ],
        ],
      );
}

class _CancellationAvailability extends StatelessWidget {
  const _CancellationAvailability({
    required this.remaining,
    required this.serverTimeReady,
    required this.cancelling,
    required this.onCancel,
  });

  final Duration? remaining;
  final bool serverTimeReady;
  final bool cancelling;
  final VoidCallback onCancel;

  bool get _unlocked => serverTimeReady && remaining == Duration.zero;

  String get _countdown {
    final milliseconds = remaining?.inMilliseconds ?? 0;
    final seconds = (milliseconds + 999) ~/ 1000;
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) {
      return TextButton(
        onPressed: cancelling ? null : onCancel,
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF9A5B56),
          disabledForegroundColor: AppColors.textSecondary,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          textStyle: GoogleFonts.outfit(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        child: Text(cancelling ? 'Cancelling…' : 'Cancel request'),
      );
    }

    final totalSeconds = _PatientConsultationRequestScreenState
        ._patientCancellationDelay
        .inSeconds;
    final secondsRemaining = remaining?.inSeconds.clamp(0, totalSeconds);
    final progress = serverTimeReady && secondsRemaining != null
        ? 1 - (secondsRemaining / totalSeconds)
        : null;
    final almostReady =
        serverTimeReady && (secondsRemaining ?? totalSeconds) <= 5 * 60;
    final accent = almostReady ? const Color(0xFFD97706) : AppColors.brand;

    return Semantics(
      label: serverTimeReady
          ? 'Cancellation available in $_countdown'
          : 'Synchronizing cancellation timer',
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 310),
        padding: const EdgeInsets.fromLTRB(14, 13, 16, 13),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F6F8),
          borderRadius: BorderRadius.circular(17),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.07),
              blurRadius: 16,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.square(
                    dimension: 31,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 2.5,
                      backgroundColor: accent.withValues(alpha: 0.12),
                      color: accent,
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Icon(Icons.schedule_rounded, size: 15, color: accent),
                ],
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Text(
                      serverTimeReady ? _countdown : 'Syncing…',
                      key: ValueKey(serverTimeReady ? _countdown : null),
                      style: GoogleFonts.outfit(
                        fontSize: 21,
                        height: 1,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                        color: accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'You can cancel the request when this timer ends',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      fontSize: 10.5,
                      height: 1.25,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestPanel extends StatelessWidget {
  const _RequestPanel({
    required this.fee,
    required this.balance,
    required this.requesting,
    required this.doctorAvailable,
    required this.onRequest,
  });

  final double fee;
  final double? balance;
  final bool requesting;
  final bool doctorAvailable;
  final VoidCallback onRequest;

  String _money(double value) => NumberFormat('#,##0.##').format(value);

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
            boxShadow: [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 22,
                offset: Offset(0, -5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD7DBE0),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 14),
              _InfoRow(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Consultation fee',
                value: 'Rs. ${_money(fee)} per session',
              ),
              const Divider(height: 24, color: Color(0xFFEEF0F2)),
              _InfoRow(
                icon: Icons.wallet_outlined,
                title: 'Your wallet balance',
                value: balance == null ? 'Login required' : 'Rs. ${_money(balance!)}',
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: requesting || !doctorAvailable ? null : onRequest,
                  icon: requesting
                      ? const SizedBox.square(
                          dimension: 17,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.videocam_rounded, size: 20),
                  label: Text(
                    doctorAvailable ? 'Request consultation' : 'Doctor offline',
                  ),
                  style: FilledButton.styleFrom(
                    elevation: 0,
                    backgroundColor: AppColors.brand,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFF2F4F6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: AppColors.brand),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

class _LockedComposer extends StatelessWidget {
  const _LockedComposer();

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FA),
              borderRadius: BorderRadius.circular(13),
              
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_outline_rounded, size: 18, color: Color(0xFF667085)),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Chat is locked until the doctor accepts your request.',
                    style: GoogleFonts.outfit(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 36),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              TextButton(onPressed: retry, child: const Text('Try again')),
            ],
          ),
        ),
      );
}
