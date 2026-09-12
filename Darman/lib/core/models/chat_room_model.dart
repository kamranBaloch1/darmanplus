import 'chat_message_model.dart';

class ChatRoomModel {
  final String id;
  final String bookingId;
  final String patientId;
  final String doctorId;
  final String? lastMessageText;
  final MessageType? lastMessageType;
  final String? lastMessageSenderId;
  final DateTime? lastMessageAt;
  final int patientUnreadCount;
  final int doctorUnreadCount;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ChatRoomModel({
    required this.id,
    required this.bookingId,
    required this.patientId,
    required this.doctorId,
    this.lastMessageText,
    this.lastMessageType,
    this.lastMessageSenderId,
    this.lastMessageAt,
    this.patientUnreadCount = 0,
    this.doctorUnreadCount = 0,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ChatRoomModel.fromMap(Map<String, dynamic> map) => ChatRoomModel(
        id: map['id']?.toString() ?? '',
        bookingId: map['booking_id']?.toString() ?? '',
        patientId: map['patient_id']?.toString() ?? '',
        doctorId: map['doctor_id']?.toString() ?? '',
        lastMessageText: map['last_message_text']?.toString(),
        lastMessageType: map['last_message_type'] == null
            ? null
            : MessageType.values.cast<MessageType?>().firstWhere(
                  (e) => e?.name == map['last_message_type'],
                  orElse: () => null,
                ),
        lastMessageSenderId: map['last_message_sender_id']?.toString(),
        lastMessageAt: DateTime.tryParse(map['last_message_at']?.toString() ?? '')?.toUtc(),
        patientUnreadCount: (map['patient_unread_count'] as num?)?.toInt() ?? 0,
        doctorUnreadCount: (map['doctor_unread_count'] as num?)?.toInt() ?? 0,
        isActive: map['is_active'] != false,
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '')?.toUtc() ??
            DateTime.now().toUtc(),
        updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? '')?.toUtc() ??
            DateTime.now().toUtc(),
      );
}
