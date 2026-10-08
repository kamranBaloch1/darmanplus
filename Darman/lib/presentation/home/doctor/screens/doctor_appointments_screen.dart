import 'dart:async';

import 'package:darmaan/core/constants/images.dart';
import 'package:darmaan/core/models/booking_model.dart';
import 'package:darmaan/core/models/user_model.dart';
import 'package:darmaan/core/theme/app_colors.dart';
import 'package:darmaan/core/utils/app_error_message.dart';
import 'package:darmaan/widgets/app_shimmer.dart';
import 'package:darmaan/presentation/home/chat/chat_room.dart';
import 'package:darmaan/presentation/home/doctor/repository/doctor_appointments_repository.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:darmaan/widgets/unread_message_badge.dart';
import 'package:darmaan/widgets/app_icon.dart';

/// Lists every appointment request/booking made with the signed-in doctor,
/// split into "Upcoming" (pending/accepted/in progress) and "History"
/// (completed/cancelled). Pending requests show an Accept button.
class DoctorAppointmentsScreen extends StatefulWidget {
  const DoctorAppointmentsScreen({
    super.key,
    this.historyOnly = false,
    this.showBackButton = false,
    this.homeOnly = false,
    this.refreshToken = 0,
    this.isOnline = false,
    this.isUpdatingAvailability = false,
    this.onAvailabilityChanged,
  });

  final bool historyOnly;
  final bool showBackButton;
  final bool homeOnly;
  final int refreshToken;
  final bool isOnline;
  final bool isUpdatingAvailability;
  final ValueChanged<bool>? onAvailabilityChanged;

  @override
  State<DoctorAppointmentsScreen> createState() =>
      _DoctorAppointmentsScreenState();
}

class _DoctorAppointmentsScreenState extends State<DoctorAppointmentsScreen>
    with SingleTickerProviderStateMixin {
  final DoctorAppoinmentsRepository _doctorRepository =
      DoctorAppoinmentsRepository();
  late final TabController _tabController;

  bool _isLoading = true;
  String? _error;
  List<BookingModel> _bookings = [];
  Map<String, UserModel> _patientsById = {};
  Map<String, int> _ratingsByBookingId = {};
  final Set<String> _acceptingIds = {};
  final Set<String> _cancellingIds = {};
  Timer? _autoRefreshTimer;
  bool _silentRefreshing = false;
  int _historyPeriod = 0;
  DateTime _historyDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
    if (widget.homeOnly) {
      _autoRefreshTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _refreshSilently(),
      );
    }
  }

  @override
  void didUpdateWidget(covariant DoctorAppointmentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refreshSilently() async {
    if (_silentRefreshing || !mounted) return;
    _silentRefreshing = true;
    try {
      final bookings = await _doctorRepository.getDoctorBookings();
      final patientIds = bookings
          .map((item) => item.patientId)
          .toSet()
          .toList();
      final patients = await _doctorRepository.getPatientsByIds(patientIds);
      if (!mounted) return;
      setState(() {
        _bookings = bookings;
        _patientsById = patients;
      });
    } catch (_) {
      // Keep the last successful data on screen. Pull-to-refresh still exposes
      // persistent connectivity errors to the doctor.
    } finally {
      _silentRefreshing = false;
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final bookings = await _doctorRepository.getDoctorBookings();
      final patientIds = bookings.map((b) => b.patientId).toSet().toList();
      final patients = await _doctorRepository.getPatientsByIds(patientIds);
      final ratings = await _doctorRepository.getRatingsByBookingIds(
        bookings.map((booking) => booking.id).toList(),
      );

      if (!mounted) return;
      setState(() {
        _bookings = bookings;
        _patientsById = patients;
        _ratingsByBookingId = ratings;
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

  List<BookingModel> get _upcoming => _bookings
      .where(
        (b) =>
            b.status == BookingStatus.pending ||
            b.status == BookingStatus.accepted ||
            b.status == BookingStatus.inProgress ||
            b.hasUpcomingFollowUp,
      )
      .toList();

  List<BookingModel> get _homeAppointments => _bookings
      .where(
        (booking) =>
            booking.status == BookingStatus.pending ||
            booking.status == BookingStatus.accepted ||
            booking.status == BookingStatus.inProgress,
      )
      .toList();

  List<BookingModel> get _history => _bookings
      .where(
        (b) =>
            b.status == BookingStatus.completed ||
            b.status == BookingStatus.cancelled,
      )
      .toList();

  List<BookingModel> get _filteredHistory {
    final selected = DateTime(
      _historyDate.year,
      _historyDate.month,
      _historyDate.day,
    );
    final start = switch (_historyPeriod) {
      0 => selected,
      1 => selected.subtract(
        Duration(days: selected.weekday - DateTime.monday),
      ),
      _ => DateTime(selected.year, selected.month),
    };
    final end = switch (_historyPeriod) {
      0 => start.add(const Duration(days: 1)),
      1 => start.add(const Duration(days: 7)),
      _ => DateTime(selected.year, selected.month + 1),
    };
    final result = _history.where((booking) {
      final date =
          (booking.completedAt ?? booking.cancelledAt ?? booking.updatedAt)
              .toLocal();
      return !date.isBefore(start) && date.isBefore(end);
    }).toList();
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  String get _historyDateLabel {
    const months = [
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
    String date(DateTime value, {bool year = true}) =>
        '${value.day.toString().padLeft(2, '0')} ${months[value.month - 1]}${year ? ' ${value.year}' : ''}';
    if (_historyPeriod == 0) return date(_historyDate);
    if (_historyPeriod == 1) {
      final selected = DateTime(
        _historyDate.year,
        _historyDate.month,
        _historyDate.day,
      );
      final start = selected.subtract(Duration(days: selected.weekday - 1));
      return '${date(start, year: false)} - ${date(start.add(const Duration(days: 6)))}';
    }
    return '${months[_historyDate.month - 1]} ${_historyDate.year}';
  }

  Future<void> _pickHistoryDate() async {
    final picked = await showDatePicker(
      context: context,
      builder: _blackDatePickerTheme,
      initialDate: _historyDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: _historyPeriod == 0
          ? 'SELECT DAY'
          : _historyPeriod == 1
          ? 'SELECT ANY DAY IN THE WEEK'
          : 'SELECT ANY DAY IN THE MONTH',
    );
    if (picked != null && mounted) setState(() => _historyDate = picked);
  }

  Widget _blackDatePickerTheme(BuildContext context, Widget? child) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          primary: AppColors.brand,
          onPrimary: Colors.white,
          onSurface: Colors.black,
        ),
        datePickerTheme: const DatePickerThemeData(
          headerForegroundColor: Colors.black,
          weekdayStyle: TextStyle(color: Colors.black),
          dayStyle: TextStyle(color: Colors.black),
          yearStyle: TextStyle(color: Colors.black),
        ),
      ),
      child: child!,
    );
  }

  Future<void> _acceptBooking(BookingModel booking) async {
    final patient = _patientsById[booking.patientId];

    setState(() => _acceptingIds.add(booking.id));

    try {
      await _doctorRepository.acceptBooking(booking.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              'Accepted appointment with ${patient?.name ?? 'the patient'}',
            ),
          ),
        );

      await _load();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700,
            content: Text(_readableError(e)),
          ),
        );

      // The list may be stale (e.g. patient cancelled meanwhile) — refresh
      // so the tile reflects reality instead of still offering Accept.
      await _load();
    } finally {
      if (mounted) setState(() => _acceptingIds.remove(booking.id));
    }
  }

  Future<void> _cancelBooking(BookingModel booking) async {
    final patient = _patientsById[booking.patientId];
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD8DBDF),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Cancel appointment?',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              booking.status == BookingStatus.inProgress
                  ? 'The active consultation with ${patient?.name ?? 'this patient'} will be cancelled. The full reserved fee will be returned and the patient will be notified.'
                  : 'The appointment with ${patient?.name ?? 'this patient'} will be cancelled and the patient will be notified.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(sheetContext, true),
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFFF1F3F5),
                      foregroundColor: const Color(0xFFB42318),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Cancel appointment',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(sheetContext, false),
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFFF1F3F5),
                      foregroundColor: AppColors.textPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Keep appointment',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _cancellingIds.add(booking.id));
    try {
      await _doctorRepository.cancelBooking(booking.id);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.black87,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            content: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'The appointment with ${patient?.name ?? 'the patient'} has been cancelled.',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_readableError(error)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _cancellingIds.remove(booking.id));
    }
  }

  void _openChat(BookingModel booking) {
    final patient = _patientsById[booking.patientId];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          bookingId: booking.id,
          peerName: patient?.name ?? 'Patient',
          peerAvatarUrl: patient?.profileImage,
          peerSubtitle: 'Patient',
          openFromHistory:
              booking.status == BookingStatus.completed ||
              booking.status == BookingStatus.cancelled,
        ),
      ),
    );
  }

  String _readableError(Object e) {
    return AppErrorMessage.from(e);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.homeOnly) return _buildHome();
    if (widget.historyOnly) return _buildHistoryScreen();
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: Column(
        children: [
          _Header(),
          _TabBarSection(controller: _tabController),
          Expanded(
            child: _isLoading
                ? const AppListShimmer(itemCount: 5, horizontalPadding: 16)
                : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _AppointmentList(
                        bookings: _upcoming,
                        patientsById: _patientsById,
                        acceptingIds: _acceptingIds,
                        cancellingIds: _cancellingIds,
                        emptyIcon: Icons.event_available_outlined,
                        emptyMessage:
                            'No appointment requests right now.\nNew appointments will show up here.',
                        onRefresh: _load,
                        onAcceptBooking: _acceptBooking,
                        onCancelBooking: _cancelBooking,
                        onOpenChat: _openChat,
                      ),
                      _AppointmentList(
                        bookings: _history,
                        patientsById: _patientsById,
                        ratingsByBookingId: _ratingsByBookingId,
                        acceptingIds: _acceptingIds,
                        cancellingIds: _cancellingIds,
                        emptyIcon: Icons.history_rounded,
                        emptyMessage:
                            'Completed and cancelled appointments\nwill show up here.',
                        onRefresh: _load,
                        onAcceptBooking: _acceptBooking,
                        onCancelBooking: _cancelBooking,
                        onOpenChat: _openChat,
                        historyStyle: true,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHome() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                Image.asset(
                  logoHome,
                  width: 125,
                  height: 34,
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft,
                ),
                const Spacer(),
                _OnlineStatusButton(
                  isOnline: widget.isOnline,
                  isUpdating: widget.isUpdatingAvailability,
                  onTap: widget.onAvailabilityChanged == null
                      ? null
                      : () => widget.onAvailabilityChanged!(!widget.isOnline),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const AppListShimmer(itemCount: 5, horizontalPadding: 16)
                : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : _AppointmentList(
                    bookings: _homeAppointments,
                    patientsById: _patientsById,
                    acceptingIds: _acceptingIds,
                    cancellingIds: _cancellingIds,
                    emptyIcon: Icons.event_available_outlined,
                    emptyMessage:
                        'No active appointments right now.\nNew patient requests will appear here.',
                    onRefresh: _load,
                    onAcceptBooking: _acceptBooking,
                    onCancelBooking: _cancelBooking,
                    onOpenChat: _openChat,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: SafeArea(
        child: Column(
          children: [
          _Header(
            title: 'History',
            showBackButton: widget.showBackButton,
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
            child: Column(
              children: [
                Row(
                  children: List.generate(3, (index) {
                    final selected = _historyPeriod == index;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Material(
                          color: selected
                              ? AppColors.brand
                              : const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: () => setState(() {
                              _historyPeriod = index;
                              _historyDate = DateTime.now();
                            }),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              child: Text(
                                ['Day', 'Week', 'Month'][index],
                                textAlign: TextAlign.center,
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: selected
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 12),
                Material(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: _pickHistoryDate,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 13,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_month_outlined,
                            size: 18,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              _historyDateLabel,
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.black,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.expand_more_rounded,
                            color: Colors.black,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const AppListShimmer(itemCount: 5, horizontalPadding: 16)
                : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : _AppointmentList(
                    bookings: _filteredHistory,
                    patientsById: _patientsById,
                    ratingsByBookingId: _ratingsByBookingId,
                    acceptingIds: _acceptingIds,
                    cancellingIds: _cancellingIds,
                    emptyIcon: Icons.history_rounded,
                    emptyMessage:
                        'No consultation history found for this period.',
                    onRefresh: _load,
                    onAcceptBooking: _acceptBooking,
                    onCancelBooking: _cancelBooking,
                    onOpenChat: _openChat,
                    historyStyle: true,
                  ),
          ),
          ],
        ),
      ),
    );
  }
}

class _OnlineStatusButton extends StatelessWidget {
  const _OnlineStatusButton({
    required this.isOnline,
    required this.isUpdating,
    required this.onTap,
  });

  final bool isOnline;
  final bool isUpdating;
  final VoidCallback? onTap;

  static const Color _onlineColor = AppColors.brand;
  static const Color _offlineColor = Color(0xFFE5E7EB);

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isOnline ? _onlineColor : _offlineColor;
    final foregroundColor = isOnline ? Colors.white : const Color(0xFF4B5563);
    final dotColor = isOnline ? Colors.white : const Color(0xFF9CA3AF);

    return Semantics(
      button: true,
      toggled: isOnline,
      label: isOnline ? 'Doctor is online' : 'Doctor is offline',
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: isUpdating ? null : onTap,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            height: 42, 
            constraints: const BoxConstraints(minWidth: 102),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: isOnline
                  ? [
                      BoxShadow(
                        color: _onlineColor.withValues(alpha: 0.2),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isUpdating)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: foregroundColor,
                    ),
                  )
                else
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                const SizedBox(width: 7),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: Text(
                    isOnline ? 'Online' : 'Offline',
                    key: ValueKey(isOnline),
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: foregroundColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header + tab bar
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    this.title = 'Appointments',
    this.showBackButton = false,
  });
  final String title;
  final bool showBackButton;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          if (showBackButton) ...[
            IconButton(
              onPressed: () => Navigator.pop(context),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(
                width: 38,
                height: 38,
              ),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TabBarSection extends StatelessWidget {
  final TabController controller;

  const _TabBarSection({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: TabBar(
        controller: controller,
        isScrollable: false,
        labelColor: AppColors.brand,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.brand,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: GoogleFonts.outfit(
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        unselectedLabelStyle: GoogleFonts.outfit(
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        tabs: const [
          Tab(text: 'Upcoming'),
          Tab(text: 'History'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// List + states
// ---------------------------------------------------------------------------

class _AppointmentList extends StatelessWidget {
  final List<BookingModel> bookings;
  final Map<String, UserModel> patientsById;
  final Map<String, int> ratingsByBookingId;
  final Set<String> acceptingIds;
  final Set<String> cancellingIds;
  final IconData emptyIcon;
  final String emptyMessage;
  final Future<void> Function() onRefresh;
  final ValueChanged<BookingModel> onAcceptBooking;
  final ValueChanged<BookingModel> onCancelBooking;
  final ValueChanged<BookingModel> onOpenChat;
  final bool historyStyle;

  const _AppointmentList({
    required this.bookings,
    required this.patientsById,
    this.ratingsByBookingId = const {},
    required this.acceptingIds,
    required this.cancellingIds,
    required this.emptyIcon,
    required this.emptyMessage,
    required this.onRefresh,
    required this.onAcceptBooking,
    required this.onCancelBooking,
    required this.onOpenChat,
    this.historyStyle = false,
  });

  @override
  Widget build(BuildContext context) {
    if (bookings.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.14),
            _EmptyState(icon: emptyIcon, message: emptyMessage),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: historyStyle
            ? const EdgeInsets.all(16)
            : const EdgeInsets.fromLTRB(16, 10, 16, 24),
        itemCount: bookings.length,
        itemBuilder: (context, index) {
          final booking = bookings[index];
          if (historyStyle) {
            return _DoctorHistoryCard(
              booking: booking,
              patient: patientsById[booking.patientId],
              rating: ratingsByBookingId[booking.id],
              onOpenChat: () => onOpenChat(booking),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: _AppointmentTile(
              booking: booking,
              patient: patientsById[booking.patientId],
              isAccepting: acceptingIds.contains(booking.id),
              isCancelling: cancellingIds.contains(booking.id),
              onAccept: () => onAcceptBooking(booking),
              onCancel: () => onCancelBooking(booking),
              onOpenChat: () => onOpenChat(booking),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onRetry,
              child: Text(
                'Try again',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Appointment tile
// ---------------------------------------------------------------------------

class _DoctorHistoryCard extends StatefulWidget {
  const _DoctorHistoryCard({
    required this.booking,
    required this.patient,
    required this.rating,
    required this.onOpenChat,
  });
  final BookingModel booking;
  final UserModel? patient;
  final int? rating;
  final VoidCallback onOpenChat;

  @override
  State<_DoctorHistoryCard> createState() => _DoctorHistoryCardState();
}

class _DoctorHistoryCardState extends State<_DoctorHistoryCard> {
  bool _expanded = false;

  BookingModel get booking => widget.booking;
  UserModel? get patient => widget.patient;
  DateTime get date =>
      (booking.completedAt ?? booking.cancelledAt ?? booking.updatedAt)
          .toLocal();

  String _formatDate(DateTime value, {bool time = false}) {
    const months = [
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
    final base =
        '${value.day.toString().padLeft(2, '0')} '
        '${months[value.month - 1]} ${value.year}';
    if (!time) return base;
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    return '$base • $hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    final completed = booking.status == BookingStatus.completed;
    final statusColor = completed
        ? const Color(0xFF16834A)
        : const Color(0xFFB42318);
    final hasImage = patient?.profileImage?.trim().isNotEmpty == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 23,
                      backgroundColor: const Color(0xFFF1F3F5),
                      backgroundImage: hasImage
                          ? CachedNetworkImageProvider(patient!.profileImage!)
                          : null,
                      child: hasImage
                          ? null
                          : Icon(
                              Icons.person_rounded,
                              color: AppColors.textSecondary,
                              size: 22,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            patient?.name ?? 'Patient unavailable',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            patient?.phone?.trim().isNotEmpty == true
                                ? patient!.phone!
                                : 'Patient consultation',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        completed ? 'Completed' : 'Cancelled',
                        style: GoogleFonts.outfit(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: statusColor,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatDate(date),
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 21,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
                if ((completed && booking.followUpDate != null) ||
                    widget.rating != null) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 7,
                      children: [
                        if (completed && booking.followUpDate != null)
                          _HistoryMetaPill(
                            icon: Icons.event_repeat_rounded,
                            text:
                                'Follow-up on ${_formatDate(booking.followUpDate!)}',
                            color: const Color(0xFF175CD3),
                            background: const Color(0xFFEAF3FF),
                          ),
                        if (widget.rating != null)
                          _HistoryMetaPill(
                            icon: Icons.star_rounded,
                            text: '${widget.rating}',
                            color: const Color(0xFF9A6700),
                            background: const Color(0xFFFFF4D6),
                          ),
                      ],
                    ),
                  ),
                ],
                if (_expanded) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FA),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        _HistoryDetailRow(
                          label: completed ? 'Completed on' : 'Cancelled on',
                          value: _formatDate(date, time: true),
                        ),
                        const SizedBox(height: 10),
                        _HistoryDetailRow( 
                          label: 'Consultation fee',
                          value:
                              'Rs. ${booking.consultationFee.toStringAsFixed(0)}',
                        ),
                        if (!completed &&
                            booking.cancellationReason?.trim().isNotEmpty ==
                                true) ...[
                          const SizedBox(height: 10),
                          _HistoryDetailRow(
                            label: 'Reason',
                            value: booking.cancellationReason!.trim(),
                          ),
                        ],
                        const SizedBox(height: 13),
                        Align(
                          alignment: Alignment.centerRight,
                          child: UnreadMessageBadge(
                            bookingId: booking.id,
                            isDoctor: true,
                            child: OutlinedButton.icon(
                              onPressed: widget.onOpenChat,
                              icon: const AppIcon(
                                Icons.chat_bubble_outline_rounded,
                                size: 17,
                              ),
                              label: Text(
                                'View chat',
                                style: GoogleFonts.outfit(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.brand,
                                backgroundColor: Colors.white,
                                side: BorderSide(
                                  color: AppColors.brand.withValues(alpha: 0.25),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryDetailRow extends StatelessWidget {
  const _HistoryDetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ),
      const SizedBox(width: 16),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: GoogleFonts.outfit(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    ],
  );
}

class _HistoryMetaPill extends StatelessWidget {
  const _HistoryMetaPill({
    required this.icon,
    required this.text,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          text,
          style: GoogleFonts.outfit(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    ),
  );
}
class _AppointmentTile extends StatelessWidget {
  final BookingModel booking;
  final UserModel? patient;
  final bool isAccepting;
  final bool isCancelling;
  final VoidCallback onAccept;
  final VoidCallback onCancel;
  final VoidCallback onOpenChat;

  const _AppointmentTile({
    required this.booking,
    required this.patient,
    required this.isAccepting,
    required this.isCancelling,
    required this.onAccept,
    required this.onCancel,
    required this.onOpenChat,
  });

  bool get _hasImage =>
      patient?.profileImage != null && patient!.profileImage!.trim().isNotEmpty;

  bool get _canAccept => booking.status == BookingStatus.pending;

  bool get _canCancel =>
      booking.status == BookingStatus.pending ||
      booking.status == BookingStatus.accepted ||
      booking.status == BookingStatus.inProgress;

  bool get _canChat =>
      booking.status == BookingStatus.accepted ||
      booking.status == BookingStatus.inProgress ||
      booking.isFollowUpOpen;

  String get _subtitle {
    if (booking.hasScheduledFollowUp) return 'Follow-up Consultation';
    switch (booking.status) {
      case BookingStatus.pending:
        return 'Consultation Request';
      case BookingStatus.accepted:
        return 'In consultation';
      case BookingStatus.inProgress:
        return 'In progress';
      case BookingStatus.completed:
        return 'Completed';
      case BookingStatus.cancelled:
        return 'Cancelled';
    }
  }

  ({String label, Color color, Color bg}) get _pill {
    if (booking.hasScheduledFollowUp) {
      return (
        label: 'Follow-up',
        color: const Color(0xFF175CD3),
        bg: const Color(0xFFEAF3FF),
      );
    }
    switch (booking.status) {
      case BookingStatus.pending:
        return (
          label: 'NEW',
          color: const Color(0xFFB54708),
          bg: const Color(0xFFFEF0E1),
        );
      case BookingStatus.accepted:
        return (
          label: 'In consultation',
          color: const Color(0xFF16834A),
          bg: const Color(0xFFE7F6EC),
        );
      case BookingStatus.inProgress:
        return (
          label: 'In progress',
          color: const Color(0xFF16834A),
          bg: const Color(0xFFE7F6EC),
        );
      case BookingStatus.completed:
      case BookingStatus.cancelled:
        return (
          label: booking.status == BookingStatus.completed
              ? 'Completed'
              : 'Cancelled',
          color: AppColors.textSecondary,
          bg: const Color(0xFFF1F3F5),
        );
    }
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatDateTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final month = _months[local.month - 1];
    final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$month ${local.day}, ${local.year} · $hour12:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final pill = _pill;
    final timeLabel = booking.hasScheduledFollowUp
        ? _formatDateTime(booking.followUpDate!)
        : _formatDateTime(booking.createdAt);

    final showSecondary = _canCancel;
    final secondaryLabel =
        booking.status == BookingStatus.pending ? 'Decline' : 'Cancel';

    final showPrimary = _canAccept || _canChat;
    final primaryLabel = _canAccept ? 'Accept' : 'Message';
    final primaryIcon = _canAccept
        ? Icons.check_rounded
        : Icons.chat_bubble_outline_rounded;
    final primaryBusy = _canAccept ? isAccepting : false;
    final primaryOnTap = _canAccept ? onAccept : onOpenChat;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(13, 13, 13, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: const Color(0xFFF1F3F5),
                backgroundImage: _hasImage
                    ? CachedNetworkImageProvider(patient!.profileImage!)
                    : null,
                child: _hasImage
                    ? null
                    : AppIcon(
                        Icons.person_rounded,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
              ),
              const SizedBox(width: 11),
              // Name, subtitle, and time all live in ONE column so their
              // left edges align automatically — no manual pixel math.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            patient?.name ?? 'Patient unavailable',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: pill.bg,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            pill.label,
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: pill.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                   
                   
                    Row(
                      children: [
                        AppIcon(
                          Icons.access_time_rounded,
                          size: 13,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            timeLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (showSecondary || showPrimary) ...[
            const SizedBox(height: 11),
            const Divider(height: 1, color: Color(0xFFE9EBEE)),
            const SizedBox(height: 10),
            Row(
              children: [
                if (showSecondary)
                  Expanded(
                    child: _PillActionButton(
                      label: secondaryLabel,
                      filled: false,
                      busy: isCancelling,
                      onTap: isCancelling ? null : onCancel,
                    ),
                  ),
                if (showSecondary && showPrimary) const SizedBox(width: 9),
                if (showPrimary)
                  Expanded(
                    child: _PillActionButton(
                      label: primaryLabel,
                      icon: primaryIcon,
                      filled: true,
                      busy: primaryBusy,
                      onTap: primaryBusy ? null : primaryOnTap,
                      iconWidget: _canAccept
                          ? null
                          : UnreadMessageBadge(
                              bookingId: booking.id,
                              isDoctor: true,
                              child: AppIcon(
                                primaryIcon,
                                size: 14,
                                color: AppColors.brand,
                              ),
                            ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PillActionButton extends StatelessWidget {
  const _PillActionButton({
    required this.label,
    required this.filled,
    required this.onTap,
    this.icon,
    this.iconWidget,
    this.busy = false,
  });

  final String label;
  final bool filled;
  final VoidCallback? onTap;
  final IconData? icon;
  final Widget? iconWidget;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: TextButton(
        onPressed: busy ? null : onTap,
        style: TextButton.styleFrom(
          backgroundColor: filled ? AppColors.brand : Colors.transparent,
          foregroundColor: filled ? Colors.white : const Color(0xFF9CA3AF),
          disabledBackgroundColor: filled
              ? AppColors.brand.withValues(alpha: .6)
              : Colors.transparent,
          disabledForegroundColor: filled
              ? Colors.white
              : const Color(0xFF9CA3AF),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: filled
                ? BorderSide.none
                : const BorderSide(color: Color(0xFFE9EBEE), width: 1),
          ),
        ),
        child: busy
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: filled ? Colors.white : const Color(0xFF9CA3AF),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (filled) ...[
                    Container(
                      width: 19,
                      height: 19,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      // Explicit color overrides the white foregroundColor
                      // this button would otherwise pass down via IconTheme.
                      child: iconWidget ??
                          (icon != null
                              ? AppIcon(icon, size: 13, color: AppColors.brand)
                              : const SizedBox.shrink()),
                    ),
                    const SizedBox(width: 7),
                  ],
                  Text(
                    label,
                    style: GoogleFonts.outfit(
                      fontSize: filled ? 13.5 : 13,
                      fontWeight: filled ? FontWeight.w500 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
