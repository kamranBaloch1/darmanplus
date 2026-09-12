import 'package:darmaan/core/services/server_clock_service.dart';

enum BookingStatus { pending, accepted, inProgress, completed, cancelled }
enum SessionStartStatus { none, pending, declined }

class BookingModel {
  const BookingModel({
    required this.id,
    required this.patientId,
    required this.doctorId,
    this.status = BookingStatus.pending,
    this.sessionStartStatus = SessionStartStatus.none,
    required this.consultationFee,
    this.consultationRoomId,
    this.patientJoinedAt,
    this.doctorJoinedAt,
    required this.createdAt,
    this.acceptedAt,
    this.startedAt,
    this.completedAt,
    this.sessionStartRequestedAt,
    this.sessionStartRespondedAt,
    this.cancelledBy,
    this.cancellationReason,
    this.cancelledAt,
    this.followUpDate,
    this.followUpScheduledAt,
    this.followUpPatientSeenAt,
    this.followUpEndedAt,
    this.followUpPatientEndSeenAt,
    this.followUpDoctorEndSeenAt,
    required this.updatedAt,
  });

  final String id;
  final String patientId;
  final String doctorId;
  final BookingStatus status;
  final SessionStartStatus sessionStartStatus;
  final double consultationFee;
  final String? consultationRoomId;
  final DateTime? patientJoinedAt;
  final DateTime? doctorJoinedAt;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? sessionStartRequestedAt;
  final DateTime? sessionStartRespondedAt;
  final String? cancelledBy;
  final String? cancellationReason;
  final DateTime? cancelledAt;
  final DateTime? followUpDate;
  final DateTime? followUpScheduledAt;
  final DateTime? followUpPatientSeenAt;
  final DateTime? followUpEndedAt;
  final DateTime? followUpPatientEndSeenAt;
  final DateTime? followUpDoctorEndSeenAt;
  final DateTime updatedAt;

  bool get canPatientCancel =>
      status == BookingStatus.pending || status == BookingStatus.accepted;
  bool get canUseVideoCall => status == BookingStatus.inProgress;
  bool get hasPendingSessionRequest =>
      status == BookingStatus.accepted &&
      sessionStartStatus == SessionStartStatus.pending;
  bool get hasScheduledFollowUp =>
      status == BookingStatus.completed && followUpDate != null;
  bool get hasUpcomingFollowUp {
    final date = followUpDate;
    if (!hasScheduledFollowUp ||
        date == null ||
        followUpEndedAt != null) {
      return false;
    }
    return isFollowUpOpen || !_dateOnly(date).isBefore(_pakistanToday());
  }
  bool get isFollowUpOpen {
    final date = followUpDate;
    if (!hasScheduledFollowUp || date == null || followUpEndedAt != null) {
      return false;
    }
    return !_dateOnly(date).isAfter(_pakistanToday());
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'patient_id': patientId,
        'doctor_id': doctorId,
        'status': status.name,
        'session_start_status': sessionStartStatus.name,
        'consultation_fee': consultationFee,
        'consultation_room_id': consultationRoomId,
        'patient_joined_at': patientJoinedAt?.toUtc().toIso8601String(),
        'doctor_joined_at': doctorJoinedAt?.toUtc().toIso8601String(),
        'created_at': createdAt.toUtc().toIso8601String(),
        'accepted_at': acceptedAt?.toUtc().toIso8601String(),
        'started_at': startedAt?.toUtc().toIso8601String(),
        'completed_at': completedAt?.toUtc().toIso8601String(),
        'session_start_requested_at': sessionStartRequestedAt?.toUtc().toIso8601String(),
        'session_start_responded_at': sessionStartRespondedAt?.toUtc().toIso8601String(),
        'cancelled_by': cancelledBy,
        'cancellation_reason': cancellationReason,
        'cancelled_at': cancelledAt?.toUtc().toIso8601String(),
        'follow_up_date': followUpDate == null
            ? null
            : '${followUpDate!.year.toString().padLeft(4, '0')}-'
                '${followUpDate!.month.toString().padLeft(2, '0')}-'
                '${followUpDate!.day.toString().padLeft(2, '0')}',
        'follow_up_scheduled_at':
            followUpScheduledAt?.toUtc().toIso8601String(),
        'follow_up_patient_seen_at':
            followUpPatientSeenAt?.toUtc().toIso8601String(),
        'follow_up_ended_at': followUpEndedAt?.toUtc().toIso8601String(),
        'follow_up_patient_end_seen_at':
            followUpPatientEndSeenAt?.toUtc().toIso8601String(),
        'follow_up_doctor_end_seen_at':
            followUpDoctorEndSeenAt?.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory BookingModel.fromMap(Map<String, dynamic> map) => BookingModel(
        id: map['id']?.toString() ?? '',
        patientId: map['patient_id']?.toString() ?? '',
        doctorId: map['doctor_id']?.toString() ?? '',
        status: BookingStatus.values.firstWhere(
          (value) => value.name == map['status'],
          orElse: () => BookingStatus.pending,
        ),
        sessionStartStatus: SessionStartStatus.values.firstWhere(
          (value) => value.name == map['session_start_status'],
          orElse: () => SessionStartStatus.none,
        ),
        consultationFee: (map['consultation_fee'] as num?)?.toDouble() ?? 0,
        consultationRoomId: map['consultation_room_id']?.toString(),
        patientJoinedAt: _date(map['patient_joined_at']),
        doctorJoinedAt: _date(map['doctor_joined_at']),
        createdAt: _date(map['created_at']) ?? DateTime.now().toUtc(),
        acceptedAt: _date(map['accepted_at']),
        startedAt: _date(map['started_at']),
        completedAt: _date(map['completed_at']),
        sessionStartRequestedAt: _date(map['session_start_requested_at']),
        sessionStartRespondedAt: _date(map['session_start_responded_at']),
        cancelledBy: map['cancelled_by']?.toString(),
        cancellationReason: map['cancellation_reason']?.toString(),
        cancelledAt: _date(map['cancelled_at']),
        followUpDate: _dateOnlyValue(map['follow_up_date']),
        followUpScheduledAt: _date(map['follow_up_scheduled_at']),
        followUpPatientSeenAt: _date(map['follow_up_patient_seen_at']),
        followUpEndedAt: _date(map['follow_up_ended_at']),
        followUpPatientEndSeenAt:
            _date(map['follow_up_patient_end_seen_at']),
        followUpDoctorEndSeenAt:
            _date(map['follow_up_doctor_end_seen_at']),
        updatedAt: _date(map['updated_at']) ?? DateTime.now().toUtc(),
      );

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

  static DateTime _pakistanToday() {
    return ServerClockService.instance.pakistanToday;
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);
}
