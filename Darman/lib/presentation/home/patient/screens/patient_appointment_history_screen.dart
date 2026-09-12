import 'package:darmaan/core/models/booking_model.dart';
import 'package:darmaan/core/models/user_model.dart';
import 'package:darmaan/core/theme/app_colors.dart';
import 'package:darmaan/presentation/home/patient/repository/patient_repository.dart';
import 'package:darmaan/presentation/home/patient/screens/doctor_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:darmaan/widgets/app_shimmer.dart';
import 'package:darmaan/core/utils/app_error_message.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

enum _HistoryPeriod { day, week, month }

class PatientAppointmentHistoryScreen extends StatefulWidget {
  const PatientAppointmentHistoryScreen({
    super.key,
    this.refreshToken = 0,
  });

  final int refreshToken;

  @override
  State<PatientAppointmentHistoryScreen> createState() =>
      _PatientAppointmentHistoryScreenState();
}

class _PatientAppointmentHistoryScreenState
    extends State<PatientAppointmentHistoryScreen> {
  final PatientRepository _repository = PatientRepository();
  bool _isLoading = true;
  String? _error;
  List<BookingModel> _bookings = [];
  Map<String, UserModel> _doctors = {};
  Map<String, int> _ratingsByBookingId = {};
  _HistoryPeriod _period = _HistoryPeriod.day;
  DateTime _selectedDate = DateTime.now();
  String? _expandedBookingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PatientAppointmentHistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _load();
    }
  }

  Future<void> _load() async {
    if (mounted) setState(() { _isLoading = true; _error = null; });
    try {
      final bookings = await _repository.getPatientBookings();
      final doctors = await _repository.getDoctorsByIds(
        bookings.map((booking) => booking.doctorId).toSet().toList(),
      );
      final ratings = await _repository.getRatingsByBookingIds(
        bookings.map((booking) => booking.id).toList(),
      );
      if (!mounted) return;
      setState(() {
        _bookings = bookings;
        _doctors = doctors;
        _ratingsByBookingId = ratings;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = AppErrorMessage.from(error);
        _isLoading = false;
      });
    }
  }

  DateTime _historyDate(BookingModel booking) =>
      (booking.completedAt ?? booking.cancelledAt ?? booking.updatedAt).toLocal();

  DateTime get _rangeStart {
    final day = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    switch (_period) {
      case _HistoryPeriod.day:
        return day;
      case _HistoryPeriod.week:
        return day.subtract(Duration(days: day.weekday - DateTime.monday));
      case _HistoryPeriod.month:
        return DateTime(day.year, day.month);
    }
  }

  DateTime get _rangeEnd {
    switch (_period) {
      case _HistoryPeriod.day:
        return _rangeStart.add(const Duration(days: 1));
      case _HistoryPeriod.week:
        return _rangeStart.add(const Duration(days: 7));
      case _HistoryPeriod.month:
        return DateTime(_selectedDate.year, _selectedDate.month + 1);
    }
  }

  List<BookingModel> get _history {
    final result = _bookings.where((booking) {
      if (booking.status != BookingStatus.completed &&
          booking.status != BookingStatus.cancelled) return false;
      final date = _historyDate(booking);
      return !date.isBefore(_rangeStart) && date.isBefore(_rangeEnd);
    }).toList();
    result.sort((a, b) => _historyDate(b).compareTo(_historyDate(a)));
    return result;
  }

  String get _selectorLabel {
    switch (_period) {
      case _HistoryPeriod.day:
        return DateFormat('dd MMM yyyy').format(_selectedDate);
      case _HistoryPeriod.week:
        final end = _rangeEnd.subtract(const Duration(days: 1));
        return '${DateFormat('dd MMM').format(_rangeStart)} - ${DateFormat('dd MMM yyyy').format(end)}';
      case _HistoryPeriod.month:
        return DateFormat('MMMM yyyy').format(_selectedDate);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      builder: (context, child) {
        final theme = Theme.of(context);
        return Theme(
          data: theme.copyWith(
            colorScheme: theme.colorScheme.copyWith(
              primary: AppColors.brand,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: _period == _HistoryPeriod.day
          ? 'SELECT DAY'
          : _period == _HistoryPeriod.week
              ? 'SELECT ANY DAY IN THE WEEK'
              : 'SELECT ANY DAY IN THE MONTH',
    );
    if (picked != null && mounted) {
      setState(() { _selectedDate = picked; _expandedBookingId = null; });
    }
  }

  void _openDoctor(BookingModel booking) {
    final doctor = _doctors[booking.doctorId];
    if (doctor == null) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => DoctorDetailsScreen(doctor: doctor),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text('History', style: GoogleFonts.outfit(
          fontSize: 20, fontWeight: FontWeight.w500, color: AppColors.textPrimary,
        )),
      ),
      body: Column(children: [
        _filters(),
        Expanded(child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Color(0xFFFAFAFA),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: _content(),
        )),
      ]),
    );
  }

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(children: [
        Row(children: _HistoryPeriod.values.map((period) {
          final selected = period == _period;
          final label = switch (period) {
            _HistoryPeriod.day => 'Day',
            _HistoryPeriod.week => 'Week',
            _HistoryPeriod.month => 'Month',
          };
          return Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Material(
              color: selected ? AppColors.brand : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() {
                  _period = period;
                  _selectedDate = DateTime.now();
                  _expandedBookingId = null;
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(label, textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 14, fontWeight: FontWeight.w500,
                      color: selected ? Colors.white : AppColors.textPrimary,
                    )),
                ),
              ),
            ),
          ));
        }).toList()),
        const SizedBox(height: 16),
        Material(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(children: [
                Icon(Icons.calendar_month_outlined, size: 19,
                    color: AppColors.textSecondary),
                const SizedBox(width: 10),
                Expanded(child: Text(_selectorLabel, style: GoogleFonts.outfit(
                  fontSize: 14, fontWeight: FontWeight.w500,
                  color: Colors.black,
                ))),
                const Icon(Icons.expand_more_rounded, color: Colors.black),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _content() {
    if (_isLoading) {
      return const AppListShimmer(
        itemCount: 5,
        showAvatar: false,
        horizontalPadding: 16,
      );
    }
    if (_error != null) {
      return _MessageState(
        icon: Icons.error_outline_rounded,
        title: 'Couldn’t load history',
        message: _error!,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }
    final history = _history;
    if (history.isEmpty) {
      return _MessageState(
        icon: Icons.history_rounded,
        title: 'No history found',
        message: 'Your completed consultations will appear here.',
        onRefresh: _load,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.brand,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: history.length,
        itemBuilder: (context, index) {
          final booking = history[index];
          return _HistoryCard(
            booking: booking,
            doctor: _doctors[booking.doctorId],
            rating: _ratingsByBookingId[booking.id],
            expanded: _expandedBookingId == booking.id,
            onTap: () => setState(() {
              _expandedBookingId = _expandedBookingId == booking.id ? null : booking.id;
            }),
            onDoctorTap: () => _openDoctor(booking),
          );
        },
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.booking,
    required this.doctor,
    required this.rating,
    required this.expanded,
    required this.onTap,
    required this.onDoctorTap,
  });

  final BookingModel booking;
  final UserModel? doctor;
  final int? rating;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onDoctorTap;

  DateTime get _date =>
      (booking.completedAt ?? booking.cancelledAt ?? booking.updatedAt).toLocal();

  String get _doctorSubtitle {
    final specialization = doctor?.specialization?.trim() ?? '';
    final title = doctor?.title?.trim() ?? '';

    if (specialization.isNotEmpty && title.isNotEmpty) {
      return '$specialization | $title';
    }
    if (specialization.isNotEmpty) return specialization;
    if (title.isNotEmpty) return title;
    return 'Consultation';
  }

  @override
  Widget build(BuildContext context) {
    final completed = booking.status == BookingStatus.completed;
    final statusColor = completed ? const Color(0xFF16834A) : const Color(0xFFB42318);
    final hasImage = doctor?.profileImage?.trim().isNotEmpty == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 14,
          offset: const Offset(0, 5),
        )],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(children: [
                CircleAvatar(
                  radius: 23,
                  backgroundColor: const Color(0xFFF1F3F5),
                  backgroundImage: hasImage
                      ? CachedNetworkImageProvider(doctor!.profileImage!)
                      : null,
                  child: hasImage ? null : Icon(Icons.person_rounded,
                    color: AppColors.textSecondary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(child: Text(
                        doctor?.name ?? 'Doctor unavailable',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 15.5, fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      )),
                      if (doctor?.isDoctorVerified == true) ...[
                        const SizedBox(width: 5),
                        Icon(Icons.verified_rounded, size: 16, color: AppColors.brand),
                      ],
                    ]),
                    const SizedBox(height: 3),
                    Text(_doctorSubtitle,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(fontSize: 12,
                        color: AppColors.textSecondary)),
                  ],
                )),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(completed ? 'Completed' : 'Cancelled',
                    style: GoogleFonts.outfit(
                      fontSize: 11.5, fontWeight: FontWeight.w500,
                      color: statusColor,
                    )),
                ),
                const Spacer(),
                Text(DateFormat('dd MMM yyyy').format(_date),
                  style: GoogleFonts.outfit(fontSize: 12,
                    color: AppColors.textSecondary)),
                const SizedBox(width: 5),
                Icon(expanded ? Icons.expand_less : Icons.expand_more,
                  size: 21, color: AppColors.textSecondary),
              ]),
              if ((completed && booking.followUpDate != null) ||
                  rating != null) ...[
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
                              'Follow-up on ${DateFormat('dd MMM yyyy').format(booking.followUpDate!)}',
                          color: const Color(0xFF175CD3),
                          background: const Color(0xFFEAF3FF),
                        ),
                      if (rating != null)
                        _HistoryMetaPill(
                          icon: Icons.star_rounded,
                          text: '$rating',
                          color: const Color(0xFF9A6700),
                          background: const Color(0xFFFFF4D6),
                        ),
                    ],
                  ),
                ),
              ],
              if (expanded) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F8FA),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(children: [
                    _DetailRow(
                      label: completed ? 'Completed on' : 'Cancelled on',
                      value: DateFormat('dd MMM yyyy • hh:mm a').format(_date),
                    ),
                    const SizedBox(height: 10),
                    _DetailRow(
                      label: 'Consultation fee',
                      value: 'Rs. ${NumberFormat('#,##0').format(booking.consultationFee)}',
                    ),
                    if (!completed && booking.cancellationReason?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 10),
                      _DetailRow(label: 'Reason', value: booking.cancellationReason!.trim()),
                    ],
                    if (doctor != null) ...[
                      const SizedBox(height: 10),
                      SizedBox(width: double.infinity, child: TextButton(
                        onPressed: onDoctorTap,
                        child: const Text('View doctor profile'),
                      )),
                    ],
                  ]),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Text(label, style: GoogleFonts.outfit(
        fontSize: 12, color: AppColors.textSecondary))),
      const SizedBox(width: 16),
      Flexible(child: Text(value, textAlign: TextAlign.right,
        style: GoogleFonts.outfit(
          fontSize: 12.5, fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ))),
    ]);
  }
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

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.onRefresh,
  });
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final content = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.16),
        Icon(icon, size: 54, color: Colors.grey.shade300),
        const SizedBox(height: 14),
        Text(title, textAlign: TextAlign.center, style: GoogleFonts.outfit(
          fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.textPrimary,
        )),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(message, textAlign: TextAlign.center,
            style: GoogleFonts.outfit(fontSize: 12.5,
              color: AppColors.textSecondary)),
        ),
        if (onAction != null) ...[
          const SizedBox(height: 16),
          Center(child: TextButton(
            onPressed: onAction,
            child: Text(actionLabel ?? 'Retry'),
          )),
        ],
      ],
    );
    return onRefresh == null
        ? content
        : RefreshIndicator(onRefresh: onRefresh!, child: content);
  }
}
