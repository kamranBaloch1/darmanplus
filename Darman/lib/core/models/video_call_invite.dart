enum VideoCallInviteStatus {
  ringing,
  accepted,
  declined,
  cancelled,
  expired,
  ended,
}

class VideoCallInvite {
  const VideoCallInvite({
    required this.id,
    required this.bookingId,
    required this.callerId,
    required this.calleeId,
    required this.callerName,
    required this.calleeName,
    required this.callerIsDoctor,
    required this.calleeIsDoctor,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.respondedAt,
  });

  final String id, bookingId, callerId, calleeId, callerName, calleeName;
  final bool callerIsDoctor;
  final bool calleeIsDoctor;
  final VideoCallInviteStatus status;
  final DateTime createdAt, expiresAt;
  final DateTime? respondedAt;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);

  factory VideoCallInvite.fromMap(Map<String, dynamic> map) => VideoCallInvite(
        id: map['id'].toString(),
        bookingId: map['booking_id'].toString(),
        callerId: map['caller_id'].toString(),
        calleeId: map['callee_id'].toString(),
        callerName: map['caller_name']?.toString() ?? 'Caller',
        calleeName: map['callee_name']?.toString() ?? 'Participant',
        callerIsDoctor: map['caller_is_doctor'] == true,
        calleeIsDoctor: map['callee_is_doctor'] == true,
        status: VideoCallInviteStatus.values.firstWhere(
          (value) => value.name == map['status'],
          orElse: () => VideoCallInviteStatus.expired,
        ),
        createdAt: DateTime.parse(map['created_at'].toString()).toUtc(),
        expiresAt: DateTime.parse(map['expires_at'].toString()).toUtc(),
        respondedAt: map['responded_at'] == null
            ? null
            : DateTime.tryParse(map['responded_at'].toString())?.toUtc(),
      );
}
