import 'package:darmaan/core/services/server_clock_service.dart';

import 'booking_model.dart' show SessionStartStatus;

class ConsultationSessionModel {
  static const sessionStartRequestLifetime = Duration(hours: 1);

  const ConsultationSessionModel({
    required this.bookingId,
    required this.bookingStatus,
    required this.sessionStartStatus,
    this.sessionStartRequestedAt,
    this.sessionStartRespondedAt,
    this.startedAt,
    this.callStartedAt,
    this.callEndedAt,
    this.followUpDate,
    this.followUpEndedAt,
  });

  final String bookingId;
  final String bookingStatus;
  final SessionStartStatus sessionStartStatus;
  final DateTime? sessionStartRequestedAt;
  final DateTime? sessionStartRespondedAt;
  final DateTime? startedAt;
  final DateTime? callStartedAt;
  final DateTime? callEndedAt;
  final DateTime? followUpDate;
  final DateTime? followUpEndedAt;

  bool get isInProgress => bookingStatus == 'inProgress';
  bool get isEnded => bookingStatus == 'completed' || bookingStatus == 'cancelled';
  bool get hasUnendedFollowUp =>
      bookingStatus == 'completed' &&
      followUpDate != null &&
      followUpEndedAt == null;
  bool get isFollowUpOpen {
    final date = followUpDate;
    if (bookingStatus != 'completed' ||
        date == null ||
        followUpEndedAt != null) {
      return false;
    }
    final today = ServerClockService.instance.pakistanToday;
    final scheduled = DateTime.utc(date.year, date.month, date.day);
    return !scheduled.isAfter(today);
  }
  bool get isFollowUpUpcoming => hasUnendedFollowUp && !isFollowUpOpen;
  bool get isRequestPending {
    final requestedAt = sessionStartRequestedAt;
    return bookingStatus == 'accepted' &&
        sessionStartStatus == SessionStartStatus.pending &&
        requestedAt != null &&
        DateTime.now().toUtc().isBefore(
          requestedAt.add(sessionStartRequestLifetime),
        );
  }

  factory ConsultationSessionModel.fromMap(Map<String, dynamic> map) {
    return ConsultationSessionModel(
      bookingId: map['id']?.toString() ?? '',
      bookingStatus: map['status']?.toString() ?? 'pending',
      sessionStartStatus: SessionStartStatus.values.firstWhere(
        (value) => value.name == map['session_start_status'],
        orElse: () => SessionStartStatus.none,
      ),
      sessionStartRequestedAt: _date(map['session_start_requested_at']),
      sessionStartRespondedAt: _date(map['session_start_responded_at']),
      startedAt: _date(map['started_at']),
      callStartedAt: _date(map['call_started_at']),
      callEndedAt: _date(map['call_ended_at']),
      followUpDate: _dateOnlyValue(map['follow_up_date']),
      followUpEndedAt: _date(map['follow_up_ended_at']),
    );
  }

  static DateTime? _date(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString())?.toUtc();

  static DateTime? _dateOnlyValue(dynamic value) {
    final parts = value?.toString().split('-');
    if (parts == null || parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2].substring(0, 2));
    if (year == null || month == null || day == null) return null;
    return DateTime.utc(year, month, day);
  }
}
