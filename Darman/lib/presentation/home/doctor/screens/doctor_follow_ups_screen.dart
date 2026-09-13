import 'package:cached_network_image/cached_network_image.dart';
import 'package:darmaan/core/models/booking_model.dart';
import 'package:darmaan/core/models/user_model.dart';
import 'package:darmaan/core/theme/app_colors.dart';
import 'package:darmaan/core/utils/app_error_message.dart';
import 'package:darmaan/presentation/home/chat/chat_room.dart';
import 'package:darmaan/presentation/home/doctor/repository/doctor_appointments_repository.dart';
import 'package:darmaan/widgets/app_icon.dart';
import 'package:darmaan/widgets/app_shimmer.dart';
import 'package:darmaan/widgets/unread_message_badge.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class DoctorFollowUpsScreen extends StatefulWidget {
  const DoctorFollowUpsScreen({super.key, this.refreshToken = 0});

  final int refreshToken;

  @override
  State<DoctorFollowUpsScreen> createState() => _DoctorFollowUpsScreenState();
}

class _DoctorFollowUpsScreenState extends State<DoctorFollowUpsScreen> {
  final _repository = DoctorAppoinmentsRepository();
  bool _loading = true;
  String? _error;
  List<BookingModel> _followUps = const [];
  Map<String, UserModel> _patients = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DoctorFollowUpsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final bookings = await _repository.getDoctorBookings();
      final followUps = bookings
          .where(
            (booking) =>
                booking.hasScheduledFollowUp &&
                booking.followUpEndedAt == null,
          )
          .toList()
        ..sort(_sortFollowUps);
      final patients = await _repository.getPatientsByIds(
        followUps.map((booking) => booking.patientId).toSet().toList(),
      );
      if (!mounted) return;
      setState(() {
        _followUps = followUps;
        _patients = patients;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = AppErrorMessage.from(error);
        _loading = false;
      });
    }
  }

  int _sortFollowUps(BookingModel a, BookingModel b) {
    final aRank = _rank(a);
    final bRank = _rank(b);
    if (aRank != bRank) return aRank.compareTo(bRank);
    return a.followUpDate!.compareTo(b.followUpDate!);
  }

  int _rank(BookingModel booking) {
    if (booking.isFollowUpOpen) return 0;
    return 1;
  }

  void _openChat(BookingModel booking) {
    final patient = _patients[booking.patientId];
    if (patient == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          bookingId: booking.id,
          peerName: patient.name,
          peerAvatarUrl: patient.profileImage,
          peerSubtitle: 'Patient',
        ),
      ),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFD),
      body: SafeArea(
        child: _loading
            ? const AppListShimmer(itemCount: 3, horizontalPadding: 20)
            : _error != null
            ? _ErrorState(message: _error!, onRetry: _load)
            : RefreshIndicator(
                onRefresh: _load,
                color: AppColors.brand,
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                  itemCount: _followUps.isEmpty ? 3 : _followUps.length + 2,
                  separatorBuilder: (_, index) =>
                      SizedBox(height: index == 0 ? 24 : 12),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return const _FollowUpPageHeader();
                    }
                    if (index == 1) {
                      return Text(
  'Upcoming (${_followUps.length})',
  style: GoogleFonts.outfit(
    fontSize: 14.5,
    fontWeight: FontWeight.w500,
    color: const Color(0xFF102047),
  ),
);
                    }
                    if (_followUps.isEmpty) {
                      return const _EmptyState();
                    }
                    final booking = _followUps[index - 2];
                    return _FollowUpCard(
                      booking: booking,
                      patient: _patients[booking.patientId],
                      onMessage: () => _openChat(booking),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
class _FollowUpPageHeader extends StatelessWidget {
  const _FollowUpPageHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Follow-ups',
          style: GoogleFonts.outfit(
            fontSize: 20,
            height: 1.1,
            letterSpacing: -0.6,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF102047),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Stay connected with your patients',
          style: GoogleFonts.outfit(
            fontSize: 12,
            color: const Color(0xFF788294),
          ),
        ),
      ],
    );
  }
}
class _FollowUpCard extends StatelessWidget {
  const _FollowUpCard({
    required this.booking,
    required this.patient,
    required this.onMessage,
  });

  final BookingModel booking;
  final UserModel? patient;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final image = patient?.profileImage?.trim();
    final hasImage = image?.isNotEmpty == true;
    final isOpen = booking.isFollowUpOpen;
    final status = isOpen ? 'OPEN NOW' : 'UPCOMING';
    final statusColor = isOpen
        ? const Color(0xFF188456)
        : const Color(0xFFEF7A13);
    final statusBackground = isOpen
        ? const Color(0xFFEAF8F0)
        : const Color(0xFFFFF0E5);

    return Container(
      padding: const EdgeInsets.fromLTRB(13, 13, 13, 12),
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
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: const Color(0xFFF1F5FA),
                backgroundImage: hasImage
                    ? CachedNetworkImageProvider(image!)
                    : null,
                child: hasImage
                    ? null
                    : AppIcon(
                        Icons.person_rounded,
                        size: 20,
                        color: AppColors.brand,
                      ),
              ),
              const SizedBox(width: 11),
              // Name, status pill, and date all share one column so their
              // left edges line up automatically.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            patient?.name.trim().isNotEmpty == true
                                ? patient!.name
                                : 'Patient',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF102047),
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
                            color: statusBackground,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: statusColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                status,
                                style: GoogleFonts.outfit(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w500,
                                  color: statusColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        AppIcon(
                          Icons.calendar_month_rounded,
                          size: 13,
                          color: const Color(0xFF8490A2),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            DateFormat(
                              'dd MMMM yyyy',
                            ).format(booking.followUpDate!),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              fontSize: 11.5,
                              color: const Color(0xFF8490A2),
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
          const SizedBox(height: 11),
          const Divider(height: 1, color: Color(0xFFE8EDF3)),
          const SizedBox(height: 10),
          Material(
            color: const Color(0xFFF1F6FF),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onMessage,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                child: Row(
                  children: [
                    UnreadMessageBadge(
                      bookingId: booking.id,
                      isDoctor: true,
                      child: AppIcon(
                        Icons.forum_outlined,
                        color: AppColors.brand,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Open conversation',
                        style: GoogleFonts.outfit(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.brand,
                        ),
                      ),
                    ),
                    AppIcon(
                      Icons.chevron_right_rounded,
                      color: AppColors.brand,
                      size: 19,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 64),
      child: Column(
        children: [
          AppIcon(
            Icons.event_repeat_rounded,
            size: 46,
            color: const Color(0xFF98A2B3),
          ),
          const SizedBox(height: 16),
          Text(
            'No follow-ups yet',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Follow-ups you schedule after consultations will appear here.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 12.5,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}