enum MessageType { text, image, file, voice, system }

enum MessageStatus { sending, sent, delivered, read, failed }

class ChatMessageModel {
  final String id;
  final String chatRoomId;
  final String bookingId;
  final String? senderId;
  final MessageType type;
  final MessageStatus status;
  final String? text;
  final String? mediaUrl;
  final String? mediaThumbnailUrl;
  final String? fileName;
  final int? fileSizeBytes;
  final String? mimeType;
  final int? voiceDurationSeconds;
  final String? replyToMessageId;
  final ChatMessageModel? replyTo;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final DateTime updatedAt;

  const ChatMessageModel({
    required this.id,
    required this.chatRoomId,
    required this.bookingId,
    required this.senderId,
    required this.type,
    required this.status,
    this.text,
    this.mediaUrl,
    this.mediaThumbnailUrl,
    this.fileName,
    this.fileSizeBytes,
    this.mimeType,
    this.voiceDurationSeconds,
    this.replyToMessageId,
    this.replyTo,
    this.isDeleted = false,
    required this.createdAt,
    this.deliveredAt,
    this.readAt,
    required this.updatedAt,
  });

  bool get hasAttachment =>
      type == MessageType.image || type == MessageType.file || type == MessageType.voice;

  ChatMessageModel copyWith({
    MessageStatus? status,
    ChatMessageModel? replyTo,
    bool? isDeleted,
  }) => ChatMessageModel(
        id: id,
        chatRoomId: chatRoomId,
        bookingId: bookingId,
        senderId: senderId,
        type: type,
        status: status ?? this.status,
        text: text,
        mediaUrl: mediaUrl,
        mediaThumbnailUrl: mediaThumbnailUrl,
        fileName: fileName,
        fileSizeBytes: fileSizeBytes,
        mimeType: mimeType,
        voiceDurationSeconds: voiceDurationSeconds,
        replyToMessageId: replyToMessageId,
        replyTo: replyTo ?? this.replyTo,
        isDeleted: isDeleted ?? this.isDeleted,
        createdAt: createdAt,
        deliveredAt: deliveredAt,
        readAt: readAt,
        updatedAt: updatedAt,
      );

  Map<String, dynamic> toInsertMap() => {
        'id': id,
        'chat_room_id': chatRoomId,
        'booking_id': bookingId,
        'sender_id': senderId,
        'type': type.name,
        'status': MessageStatus.sent.name,
        'text': text,
        'media_url': mediaUrl,
        'media_thumbnail_url': mediaThumbnailUrl,
        'file_name': fileName,
        'file_size_bytes': fileSizeBytes,
        'mime_type': mimeType,
        'voice_duration_seconds': voiceDurationSeconds,
        'reply_to_message_id': replyToMessageId,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory ChatMessageModel.fromMap(Map<String, dynamic> map) {
    final replyMap = map['reply_to'];
    return ChatMessageModel(
      id: map['id']?.toString() ?? '',
      chatRoomId: map['chat_room_id']?.toString() ?? '',
      bookingId: map['booking_id']?.toString() ?? '',
      senderId: map['sender_id']?.toString(),
      type: MessageType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => MessageType.text,
      ),
      status: MessageStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => MessageStatus.sent,
      ),
      text: map['text']?.toString(),
      mediaUrl: map['media_url']?.toString(),
      mediaThumbnailUrl: map['media_thumbnail_url']?.toString(),
      fileName: map['file_name']?.toString(),
      fileSizeBytes: (map['file_size_bytes'] as num?)?.toInt(),
      mimeType: map['mime_type']?.toString(),
      voiceDurationSeconds: (map['voice_duration_seconds'] as num?)?.toInt(),
      replyToMessageId: map['reply_to_message_id']?.toString(),
      replyTo: replyMap is Map<String, dynamic>
          ? ChatMessageModel.fromMap(replyMap)
          : replyMap is Map
              ? ChatMessageModel.fromMap(Map<String, dynamic>.from(replyMap))
              : null,
      isDeleted: map['is_deleted'] == true,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      deliveredAt: DateTime.tryParse(map['delivered_at']?.toString() ?? '')?.toUtc(),
      readAt: DateTime.tryParse(map['read_at']?.toString() ?? '')?.toUtc(),
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
    );
  }
}
