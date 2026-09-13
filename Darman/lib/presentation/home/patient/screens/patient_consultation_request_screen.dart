import 'dart:async';

import 'package:darmaan/core/models/booking_model.dart';
import 'package:darmaan/core/models/user_model.dart';
import 'package:darmaan/core/theme/app_colors.dart';
import 'package:darmaan/presentation/home/chat/chat_room.dart';
import 'package:darmaan/presentation/home/patient/repository/patient_repository.dart';
import 'package:darmaan/presentation/home/patient/screens/doctor_details_screen.dart';
import 'package:darmaan/presentation/home/wallet/screens/add_money_screen.dart';
import 'package:darmaan/widgets/guest_access.dart';
import 'package:darmaan/widgets/app_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:darmaan/widgets/app_icon.dart';
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
    extends State<PatientConsultationRequestScreen>
    with WidgetsBindingObserver {
  static const _patientCancellationDelay = Duration(minutes: 30);

  final PatientRepository _repository = PatientRepository();
  StreamSubscription<BookingModel>? _bookingSubscription;
  Timer? _countdownTimer;
  DateTime? _serverTimeAtSync;
  final Stopwatch _timeSinceServerSync = Stopwatch();
  int _serverClockSyncGeneration = 0;

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
    if (!_isPending) return;

    if (state == AppLifecycleState.resumed) {
      if (_serverTimeAtSync != null && mounted) setState(() {});
      _startCountdown();
      unawaited(_syncServerClock());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _serverClockSyncGeneration++;
      _countdownTimer?.cancel();
    }
  }

  DateTime? get _estimatedServerNow {
    return _serverTimeAtSync?.add(_timeSinceServerSync.elapsed);
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
    final syncGeneration = ++_serverClockSyncGeneration;
    final roundTrip = Stopwatch()..start();
    try {
      final serverNow = await _repository.getConsultationServerTime();
      roundTrip.stop();
      if (!mounted ||
          !_isPending ||
          syncGeneration != _serverClockSyncGeneration) {
        return;
      }
      final midpointOffset = Duration(
        microseconds: roundTrip.elapsedMicroseconds ~/ 2,
      );
      _serverTimeAtSync = serverNow.add(midpointOffset);
      _timeSinceServerSync
        ..reset()
        ..start();
      _startCountdown();
      setState(() {});
    } catch (error) {
      if (mounted &&
          _isPending &&
          syncGeneration == _serverClockSyncGeneration) {
        _show(_message(error));
      }
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
      if (timer.tick % 60 == 0) unawaited(_syncServerClock());
    });
  }

  Future<void> _load() async {
    try {
      final initialBooking = widget.initialBooking;
      final booking =
          (initialBooking?.doctorId == doctor.uid ? initialBooking : null) ??
          (widget.startNewConsultation
              ? null
              : await _repository.getActiveBooking(doctorId: doctor.uid));
      UserModel? patient;
      if (!_isGuest) patient = await _repository.getPatientProfile();
      if (!mounted) return;
      setState(() {
        _booking = booking;
        _patient = patient;
      });
      if (booking != null) {
        _watch(booking.id);
        if (booking.status == BookingStatus.pending) await _syncServerClock();
      }
      if (mounted) setState(() => _loading = false);
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
    _bookingSubscription = _repository
        .watchBooking(bookingId)
        .listen(
          (booking) {
            if (!mounted) return;
            final wasPending = _isPending;
            setState(() => _booking = booking);
            if (booking.status != BookingStatus.pending) {
              _serverClockSyncGeneration++;
              _countdownTimer?.cancel();
              _timeSinceServerSync.stop();
            } else if (!wasPending) {
              unawaited(_syncServerClock());
            }
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
        message:
            'Please login before sending a consultation request to ${doctor.name}.',
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
      unawaited(_refreshPatientProfile());
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

  Future<void> _refreshPatientProfile() async {
    if (_isGuest) return;
    try {
      final patient = await _repository.getPatientProfile();
      if (mounted) setState(() => _patient = patient);
    } catch (_) {
      // The booking stream remains authoritative if wallet refresh is delayed.
    }
  }

  Future<void> _openAddMoney() async {
    if (_isGuest) {
      await showLoginRequiredDialog(
        context,
        title: 'Login to add money',
        message: 'Please login to add money to your Darman wallet.',
      );
      return;
    }

    final balance = _patient?.walletBalance;
    if (balance == null) {
      _show('Your wallet is still loading. Please try again.');
      return;
    }

    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AddMoneyScreen(currentBalance: balance),
      ),
    );
    if (added == true && mounted) await _refreshPatientProfile();
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
                child: const AppIcon(
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
      _show(
        'Cancellation becomes available after the 30-minute waiting period.',
      );
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
                child: const AppIcon(
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
      unawaited(_refreshPatientProfile());
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
      backgroundColor: const Color(0xFFF0EEEA),
      appBar: _appBar(),
      body: _loading
          ? const AppProfileShimmer()
          : _error != null
          ? _ErrorState(message: _error!, retry: _load)
          : Column(
              children: [
                Expanded(
                  child: _ConversationPrelude(
                    doctorName: doctor.name,
                    pending: _isPending,
                    requesting: _requesting,
                    doctorAvailable: doctor.isAvailable,
                    cancellationRemaining: _cancellationRemaining,
                    serverTimeReady: _serverTimeAtSync != null,
                    canCancel: _canCancelPendingRequest,
                    cancelling: _cancelling,
                    onRequest: _requestConsultation,
                    onCancel: _cancelRequest,
                  ),
                ),
                _WalletFeeBar(
                  balance: _patient?.walletBalance,
                  fee: doctor.consultationFee ?? 0,
                  onAdd: _openAddMoney,
                ),
                const _DisabledComposer(),
              ],
            ),
    );
  }

  PreferredSizeWidget _appBar() => AppBar(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.white,
    elevation: 0,
    scrolledUnderElevation: .5,
    toolbarHeight: 56,
    leading: IconButton(
      onPressed: () => Navigator.pop(context),
      icon: const AppIcon(Icons.arrow_back_rounded),
    ),
    titleSpacing: 0,
    title: InkWell(
      onTap: _openDoctorProfile,
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFFF1F3F5),
                backgroundImage: doctor.profileImage?.trim().isNotEmpty == true
                    ? CachedNetworkImageProvider(doctor.profileImage!)
                    : null,
                child: doctor.profileImage?.trim().isNotEmpty == true
                    ? null
                    : const AppIcon(
                        Icons.person_rounded,
                        color: AppColors.brand,
                      ),
              ),
              Positioned(
                right: 0,
                bottom: 1,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: doctor.isAvailable
                        ? const Color(0xFF20C86B)
                        : const Color(0xFF9AA3AE),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
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
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (doctor.isDoctorVerified) ...[
                      const SizedBox(width: 4),
                      const AppIcon(
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
                    fontSize: 9.8,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: const [
      _DisabledHeaderAction(
        icon: Icons.videocam_outlined,
        label: 'Video call unlocks after consultation starts',
      ),
      SizedBox(width: 4),
    ],
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

class _ConversationPrelude extends StatelessWidget {
  const _ConversationPrelude({
    required this.doctorName,
    required this.pending,
    required this.requesting,
    required this.doctorAvailable,
    required this.cancellationRemaining,
    required this.serverTimeReady,
    required this.canCancel,
    required this.cancelling,
    required this.onRequest,
    required this.onCancel,
  });

  final String doctorName;
  final bool pending;
  final bool requesting;
  final bool doctorAvailable;
  final Duration? cancellationRemaining;
  final bool serverTimeReady;
  final bool canCancel;
  final bool cancelling;
  final VoidCallback onRequest;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const Positioned.fill(child: _ConversationPattern()),
      Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 15),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .88),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x08000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                'Today',
                style: GoogleFonts.outfit(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 22),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight > 40
                        ? constraints.maxHeight - 40
                        : 0,
                  ),
                  child: Center(
                    child: Transform.translate(
                      offset: const Offset(0, 16),
                      child: pending
                          ? _PendingRequestStatus(
                              remaining: cancellationRemaining,
                              serverTimeReady: serverTimeReady,
                              canCancel: canCancel,
                              cancelling: cancelling,
                              onCancel: onCancel,
                            )
                          : _StartConversationPrompt(
                              doctorName: doctorName,
                              requesting: requesting,
                              doctorAvailable: doctorAvailable,
                              onRequest: onRequest,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

class _ConversationPattern extends StatelessWidget {
  const _ConversationPattern();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: Opacity(
        opacity: .025,
        child: Stack(
          children: const [
            Positioned(
              left: 24,
              top: 90,
              child: AppIcon(Icons.chat_bubble_outline_rounded, size: 46),
            ),
            Positioned(
              right: 34,
              top: 145,
              child: AppIcon(Icons.medical_services_outlined, size: 42),
            ),
            Positioned(
              left: 54,
              top: 270,
              child: AppIcon(Icons.description_outlined, size: 38),
            ),
            Positioned(
              right: 58,
              top: 360,
              child: AppIcon(Icons.health_and_safety_rounded, size: 48),
            ),
            Positioned(
              left: 18,
              bottom: 52,
              child: AppIcon(Icons.favorite_border_rounded, size: 42),
            ),
            Positioned(
              right: 22,
              bottom: 30,
              child: AppIcon(Icons.chat_bubble_outline_rounded, size: 38),
            ),
          ],
        ),
      ),
    ),
  );
}

class _StartConversationPrompt extends StatefulWidget {
  const _StartConversationPrompt({
    required this.doctorName,
    required this.requesting,
    required this.doctorAvailable,
    required this.onRequest,
  });

  final String doctorName;
  final bool requesting;
  final bool doctorAvailable;
  final VoidCallback onRequest;

  @override
  State<_StartConversationPrompt> createState() =>
      _StartConversationPromptState();
}

class _StartConversationPromptState extends State<_StartConversationPrompt>
    with SingleTickerProviderStateMixin {
  static const _blue = Color(0xFF007EFE);

  late final AnimationController _pulseController;
  bool _animationsDisabled = false;

  String get _doctorNameWithoutTitle => widget.doctorName.trim().replaceFirst(
    RegExp(r'^dr\.?\s+', caseSensitive: false),
    '',
  );

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    _syncPulseAnimation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animationsDisabled =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_animationsDisabled == animationsDisabled) return;

    _animationsDisabled = animationsDisabled;
    _syncPulseAnimation();
  }

  @override
  void didUpdateWidget(covariant _StartConversationPrompt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requesting != widget.requesting ||
        oldWidget.doctorAvailable != widget.doctorAvailable) {
      _syncPulseAnimation();
    }
  }

  void _syncPulseAnimation() {
    final shouldAnimate =
        !_animationsDisabled && widget.doctorAvailable && !widget.requesting;
    if (!shouldAnimate) {
      _pulseController.stop();
    } else if (!_pulseController.isAnimating) {
      _pulseController.repeat();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 330),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 156,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (_pulseController.isAnimating)
                IgnorePointer(
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) => Stack(
                        alignment: Alignment.center,
                        children: [
                          _PulseRing(progress: _pulseController.value),
                          _PulseRing(
                            progress: (_pulseController.value + .5) % 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Semantics(
                button: true,
                enabled: !widget.requesting && widget.doctorAvailable,
                label: 'Request to talk to Dr $_doctorNameWithoutTitle',
                child: Material(
                  color: widget.doctorAvailable
                      ? _blue
                      : const Color(0xFFD5DBE3),
                  elevation: widget.doctorAvailable ? 2 : 0,
                  shadowColor: _blue.withValues(alpha: .24),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: widget.requesting || !widget.doctorAvailable
                        ? null
                        : widget.onRequest,
                    customBorder: const CircleBorder(),
                    child: SizedBox.square(
                      dimension: 84,
                      child: Center(
                        child: widget.requesting
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.3,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.videocam_rounded,
                                size: 34,
                                color: Colors.white,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 17),
        Text(
          'Request to talk',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            fontSize: 17,
            height: 1.2,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          'Talk to Dr $_doctorNameWithoutTitle',
          textAlign: TextAlign.center,
          maxLines: 2,
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
  );
}

class _PulseRing extends StatelessWidget {
  const _PulseRing({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final easedProgress = Curves.easeOutCubic.transform(progress);
    final opacity = (1 - progress) * .2;

    return Transform.scale(
      scale: .9 + (.42 * easedProgress),
      child: Opacity(
        opacity: opacity,
        child: Container(
          width: 116,
          height: 116,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF007EFE).withValues(alpha: .32),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF007EFE).withValues(alpha: .10),
                blurRadius: 18,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingRequestStatus extends StatefulWidget {
  const _PendingRequestStatus({
    required this.remaining,
    required this.serverTimeReady,
    required this.canCancel,
    required this.cancelling,
    required this.onCancel,
  });

  final Duration? remaining;
  final bool serverTimeReady;
  final bool canCancel;
  final bool cancelling;
  final VoidCallback onCancel;

  @override
  State<_PendingRequestStatus> createState() => _PendingRequestStatusState();
}

class _PendingRequestStatusState extends State<_PendingRequestStatus>
    with SingleTickerProviderStateMixin {
  static const _blue = Color(0xFF007EFE);

  late final AnimationController _breathingController;
  bool _animationsDisabled = false;

  @override
  void initState() {
    super.initState();
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animationsDisabled =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_animationsDisabled == animationsDisabled) return;

    _animationsDisabled = animationsDisabled;
    if (_animationsDisabled) {
      _breathingController.stop();
    } else if (!_breathingController.isAnimating) {
      _breathingController.repeat();
    }
  }

  @override
  void dispose() {
    _breathingController.dispose();
    super.dispose();
  }

  String get _countdown {
    final milliseconds = widget.remaining?.inMilliseconds ?? 0;
    final seconds = (milliseconds + 999) ~/ 1000;
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final totalSeconds = _PatientConsultationRequestScreenState
        ._patientCancellationDelay
        .inSeconds;
    final secondsRemaining = widget.remaining?.inSeconds.clamp(0, totalSeconds);
    final progress = widget.serverTimeReady && secondsRemaining != null
        ? secondsRemaining / totalSeconds
        : 1.0;

    return Semantics(
      liveRegion: true,
      label: widget.serverTimeReady
          ? widget.canCancel
                ? 'Waiting for doctor. You can cancel the request.'
                : 'Waiting for doctor. $_countdown remaining.'
          : 'Waiting for doctor.',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 178,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  if (!_animationsDisabled)
                    IgnorePointer(
                      child: RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _breathingController,
                          builder: (context, child) {
                            final pulse = Curves.easeOutCubic.transform(
                              _breathingController.value,
                            );
                            return Transform.scale(
                              scale: 1 + (.10 * pulse),
                              child: Opacity(
                                opacity: (1 - _breathingController.value) * .26,
                                child: Container(
                                  width: 168,
                                  height: 168,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _blue.withValues(alpha: .18),
                                      width: 3,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _blue.withValues(alpha: .08),
                                        blurRadius: 20,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  SizedBox.square(
                    dimension: 150,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: progress, end: progress),
                      duration: const Duration(seconds: 1),
                      curve: Curves.linear,
                      builder: (context, animatedProgress, child) =>
                          CircularProgressIndicator(
                            value: animatedProgress,
                            strokeWidth: 6,
                            strokeCap: StrokeCap.round,
                            backgroundColor: const Color(0xFFD9EAFD),
                            color: _blue,
                          ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.serverTimeReady ? _countdown : '--:--',
                        style: GoogleFonts.outfit(
                          fontSize: 26,
                          height: 1,
                          fontWeight: FontWeight.w600,
                          letterSpacing: .4,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        'Waiting for doctor',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          height: 1.2,
                          fontWeight: FontWeight.w400,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (widget.canCancel) ...[
              const SizedBox(height: 13),
              TextButton(
                onPressed: widget.cancelling ? null : widget.onCancel,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFA75048),
                  disabledForegroundColor: AppColors.textSecondary,
                  minimumSize: const Size(44, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                child: Text(
                  widget.cancelling ? 'Cancelling…' : 'Cancel request',
                  style: GoogleFonts.outfit(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WalletFeeBar extends StatelessWidget {
  const _WalletFeeBar({
    required this.fee,
    required this.balance,
    required this.onAdd,
  });

  final double fee;
  final double? balance;
  final VoidCallback onAdd;

  String _money(double value) => NumberFormat('#,##0.##').format(value);

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: const Color(0xFFEFF2F5)),
    ),
    child: Row(
      children: [
        Expanded(
          child: _WalletMetric(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Wallet',
            value: balance == null ? 'Sign in' : 'Rs. ${_money(balance!)}',
            trailing: TextButton(
              onPressed: onAdd,
              style: TextButton.styleFrom(
                minimumSize: const Size(40, 30),
                padding: const EdgeInsets.symmetric(horizontal: 7),
                foregroundColor: AppColors.brand,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                'Add',
                style: GoogleFonts.outfit(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
        Container(
          width: 1,
          height: 39,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          color: const Color(0xFFEEF1F4),
        ),
        Expanded(
          child: _WalletMetric(
            icon: Icons.payments_outlined,
            label: 'Fee',
            value: 'Rs. ${_money(fee)}',
          ),
        ),
      ],
    ),
  );
}

class _WalletMetric extends StatelessWidget {
  const _WalletMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xFFF2F7FC),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: AppIcon(icon, size: 16, color: AppColors.brand),
      ),
      const SizedBox(width: 9),
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 10,
                height: 1.1,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                fontSize: 12.5,
                height: 1.1,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
      ?trailing,
    ],
  );
}

class _DisabledComposer extends StatelessWidget {
  const _DisabledComposer();

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F7FA),
                    borderRadius: BorderRadius.circular(23),
                  ),
                  child: const Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Message…',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFFADB5C1),
                          ),
                        ),
                      ),
                      AppIcon(
                        Icons.attach_file_rounded,
                        size: 20,
                        color: Color(0xFF9AA3AE),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F3F6),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const AppIcon(
                  Icons.mic_none_rounded,
                  size: 21,
                  color: Color(0xFFB0B7C1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const AppIcon(
                Icons.lock_outline_rounded,
                size: 12,
                color: Color(0xFF98A2B3),
              ),
              const SizedBox(width: 5),
              Text(
                'Request to talk to enable messaging',
                style: GoogleFonts.outfit(
                  fontSize: 10.5,
                  color: const Color(0xFF98A2B3),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _DisabledHeaderAction extends StatelessWidget {
  const _DisabledHeaderAction({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: IconButton(
      onPressed: null,
      tooltip: label,
      icon: AppIcon(icon, size: 22),
      disabledColor: const Color(0xFFABB3BE),
      visualDensity: VisualDensity.compact,
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
          const AppIcon(Icons.error_outline_rounded, size: 36),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          TextButton(onPressed: retry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}