import 'dart:io';
import 'dart:math' as math;

import 'package:darmaan/core/models/chat_message_model.dart';
import 'package:darmaan/core/models/chat_room_model.dart';
import 'package:darmaan/core/models/consultation_session_model.dart';
import 'package:darmaan/core/models/consultation_completion_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class ChatException implements Exception {
  final String message;
  const ChatException(this.message);
  @override
  String toString() => message;
}

class ChatRepository {
  ChatRepository({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;
  static const _uuid = Uuid();
  static const int pageSize = 40;
  static const int preSessionMessageLimit = 20;
  static final Map<String, _SignedUrlCacheEntry> _signedUrlCache = {};

  String get currentUserId {
    final id = _supabase.auth.currentUser?.id;
    if (id == null) throw const ChatException('Please sign in to use chat.');
    return id;
  }

  Future<ChatRoomModel> getOrCreateRoom(String bookingId) async {
    try {
      final result = await _supabase.rpc(
        'ensure_chat_room',
        params: {'p_booking_id': bookingId},
      );
      final id = result is String ? result : result.toString();
      final row = await _supabase
          .from('chat_rooms')
          .select()
          .eq('id', id)
          .single();
      return ChatRoomModel.fromMap(row);
    } on PostgrestException catch (e) {
      throw ChatException(e.message);
    }
  }

  Future<ChatRoomModel> getRoom(String roomId) async {
    final row = await _supabase
        .from('chat_rooms')
        .select()
        .eq('id', roomId)
        .single();
    return ChatRoomModel.fromMap(row);
  }

  Stream<List<ChatMessageModel>> watchLatestMessages(String roomId) {
    return _supabase
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('chat_room_id', roomId)
        .order('created_at', ascending: false)
        .limit(pageSize)
        .map(
          (rows) =>
              rows.map(ChatMessageModel.fromMap).toList().reversed.toList(),
        );
  }

  Stream<ConsultationSessionModel> watchSession(String bookingId) {
    return _supabase
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('id', bookingId)
        .map((rows) {
          if (rows.isEmpty) throw const ChatException('Booking not found.');
          return ConsultationSessionModel.fromMap(rows.single);
        });
  }

  Future<ConsultationSessionModel> getSession(String bookingId) async {
    try {
      final row = await _supabase
          .from('bookings')
          .select(
            'id, status, session_start_status, session_start_requested_at, '
            'session_start_responded_at, started_at, call_started_at, '
            'call_ended_at, follow_up_date, follow_up_ended_at',
          )
          .eq('id', bookingId)
          .single();
      return ConsultationSessionModel.fromMap(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e) {
      throw ChatException(e.message);
    }
  }

  Stream<List<String>> watchUnseenPatientCompletions() {
    final userId = currentUserId;
    return _supabase
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('patient_id', userId)
        .map((rows) {
          final pending = rows.where(
            (row) =>
                row['status'] == 'completed' &&
                row['patient_receipt_seen_at'] == null,
          ).toList()
            ..sort((a, b) => (a['completed_at']?.toString() ?? '')
                .compareTo(b['completed_at']?.toString() ?? ''));
          return pending.map((row) => row['id'].toString()).toList();
        });
  }

  Stream<List<Map<String, dynamic>>> watchUnseenPatientFollowUps() {
    final userId = currentUserId;
    return _supabase
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('patient_id', userId)
        .map((rows) {
          final pending = rows
              .where(
                (row) =>
                    row['status'] == 'completed' &&
                    row['follow_up_date'] != null &&
                    row['follow_up_ended_at'] == null &&
                    row['follow_up_patient_seen_at'] == null,
              )
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
            ..sort(
              (a, b) => (a['follow_up_scheduled_at']?.toString() ?? '')
                  .compareTo(b['follow_up_scheduled_at']?.toString() ?? ''),
            );
          return pending;
        });
  }

  Stream<List<Map<String, dynamic>>> watchUnseenFollowUpEnds() {
    final userId = currentUserId;
    return _supabase
        .from('bookings')
        .stream(primaryKey: ['id'])
        .map((rows) {
          final pending = rows
              .where((row) {
                if (row['follow_up_ended_at'] == null) return false;
                if (row['patient_id']?.toString() == userId) {
                  return row['follow_up_patient_end_seen_at'] == null;
                }
                if (row['doctor_id']?.toString() == userId) {
                  return row['follow_up_doctor_end_seen_at'] == null;
                }
                return false;
              })
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
            ..sort(
              (a, b) => (a['follow_up_ended_at']?.toString() ?? '')
                  .compareTo(b['follow_up_ended_at']?.toString() ?? ''),
            );
          return pending;
        });
  }

  Stream<List<Map<String, dynamic>>> watchPendingPatientSessionStarts() {
    final userId = currentUserId;
    return _supabase
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('patient_id', userId)
        .map((rows) {
          final pending = rows
              .where(
                (row) {
                  final requestedAt = DateTime.tryParse(
                    row['session_start_requested_at']?.toString() ?? '',
                  )?.toUtc();
                  return row['session_start_status'] == 'pending' &&
                      row['status'] == 'accepted' &&
                      requestedAt != null &&
                      DateTime.now().toUtc().isBefore(
                        requestedAt.add(
                          ConsultationSessionModel.sessionStartRequestLifetime,
                        ),
                      );
                },
              )
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
            ..sort(
              (a, b) => (a['session_start_requested_at']?.toString() ?? '')
                  .compareTo(
                    b['session_start_requested_at']?.toString() ?? '',
                  ),
            );
          return pending;
        });
  }

  Future<String> getBookingDoctorName(Map<String, dynamic> booking) async {
    final doctorId = booking['doctor_id']?.toString();
    if (doctorId == null || doctorId.isEmpty) return 'Your doctor';
    try {
      final user = await _supabase
          .from('users')
          .select('name')
          .eq('uid', doctorId)
          .maybeSingle();
      final name = user?['name']?.toString().trim();
      return name == null || name.isEmpty ? 'Your doctor' : 'Dr. $name';
    } on PostgrestException {
      return 'Your doctor';
    }
  }

  Future<String> getFollowUpPeerName(Map<String, dynamic> booking) async {
    final isDoctor = booking['doctor_id']?.toString() == currentUserId;
    final peerId = booking[isDoctor ? 'patient_id' : 'doctor_id']
            ?.toString() ??
        '';
    if (peerId.isEmpty) return isDoctor ? 'your patient' : 'your doctor';
    try {
      final user = await _supabase
          .from('users')
          .select('name')
          .eq('uid', peerId)
          .maybeSingle();
      final name = user?['name']?.toString().trim();
      if (name == null || name.isEmpty) {
        return isDoctor ? 'your patient' : 'your doctor';
      }
      return isDoctor ? name : 'Dr. $name';
    } on PostgrestException {
      return isDoctor ? 'your patient' : 'your doctor';
    }
  }

  Future<void> requestSessionStart(String bookingId) async {
    try {
      await _supabase.rpc(
        'request_consultation_start',
        params: {'p_booking_id': bookingId},
      );
      await _notifySessionStart(bookingId, 'requested');
    } on PostgrestException catch (e) {
      throw ChatException(e.message);
    }
  }

  Future<void> respondToSessionStart({
    required String bookingId,
    required bool accept,
  }) async {
    try {
      await _supabase.rpc(
        'respond_to_consultation_start',
        params: {'p_booking_id': bookingId, 'p_accept': accept},
      );
      await _notifySessionStart(
        bookingId,
        accept ? 'accepted' : 'declined',
      );
    } on PostgrestException catch (e) {
      throw ChatException(e.message);
    }
  }

  Future<void> _notifySessionStart(String bookingId, String event) async {
    try {
      await _supabase.functions.invoke(
        'send-session-start-notification',
        body: {'booking_id': bookingId, 'event': event},
      );
    } catch (_) {
      // The consultation action is authoritative; push delivery is best effort.
    }
  }

  Future<void> endConsultation(String bookingId) async {
    try {
      await _supabase.rpc(
        'end_video_consultation',
        params: {'p_booking_id': bookingId},
      );
      await _notifyConsultationCompletion(bookingId, 'ended');
    } on PostgrestException catch (e) {
      throw ChatException(e.message);
    }
  }

  Future<void> scheduleConsultationFollowUp(
    String bookingId,
    DateTime date,
  ) async {
    final value = '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    try {
      await _supabase.rpc(
        'schedule_consultation_follow_up',
        params: {'p_booking_id': bookingId, 'p_follow_up_date': value},
      );
      await _notifyConsultationCompletion(bookingId, 'follow_up_scheduled');
    } on PostgrestException catch (e) {
      throw ChatException(e.message);
    }
  }

  Future<void> acknowledgeConsultationFollowUp(String bookingId) async {
    try {
      await _supabase.rpc(
        'acknowledge_consultation_follow_up',
        params: {'p_booking_id': bookingId},
      );
    } on PostgrestException catch (e) {
      throw ChatException(e.message);
    }
  }

  Future<void> endConsultationFollowUp(String bookingId) async {
    try {
      await _supabase.rpc(
        'end_consultation_follow_up',
        params: {'p_booking_id': bookingId},
      );
      try {
        await _supabase.functions.invoke(
          'send-follow-up-ended-notification',
          body: {'booking_id': bookingId},
        );
      } catch (_) {
        // Ending the follow-up is authoritative; push is best effort.
      }
    } on PostgrestException catch (e) {
      throw ChatException(e.message);
    }
  }

  Future<void> acknowledgeConsultationFollowUpEnd(String bookingId) async {
    try {
      await _supabase.rpc(
        'acknowledge_consultation_follow_up_end',
        params: {'p_booking_id': bookingId},
      );
    } on PostgrestException catch (e) {
      throw ChatException(e.message);
    }
  }

  Future<ConsultationCompletionModel> getConsultationCompletion(
    String bookingId,
  ) async {
    try {
      final result = await _supabase.rpc(
        'get_consultation_completion',
        params: {'p_booking_id': bookingId},
      );
      return ConsultationCompletionModel.fromMap(
        Map<String, dynamic>.from(result as Map),
      );
    } on PostgrestException catch (e) {
      throw ChatException(e.message);
    }
  }

  Future<void> acknowledgeConsultationCompletion(String bookingId) async {
    try {
      await _supabase.rpc(
        'acknowledge_consultation_completion',
        params: {'p_booking_id': bookingId},
      );
    } on PostgrestException catch (e) {
      throw ChatException(e.message);
    }
  }

  Future<void> submitConsultationRating({
    required String bookingId,
    required int rating,
    String? review,
  }) async {
    try {
      await _supabase.rpc(
        'submit_consultation_rating',
        params: {
          'p_booking_id': bookingId,
          'p_rating': rating,
          'p_review': review?.trim().isEmpty == true ? null : review?.trim(),
        },
      );
      await _notifyConsultationCompletion(bookingId, 'rated');
    } on PostgrestException catch (e) {
      throw ChatException(e.message);
    }
  }

  Future<void> _notifyConsultationCompletion(
    String bookingId,
    String event,
  ) async {
    try {
      await _supabase.functions.invoke(
        'send-consultation-completion-notification',
        body: {'booking_id': bookingId, 'event': event},
      );
    } catch (_) {
      // Completion and rating remain successful even if push delivery fails.
    }
  }

  Future<List<ChatMessageModel>> loadOlderMessages({
    required String roomId,
    required DateTime before,
  }) async {
    final rows = await _supabase
        .from('chat_messages')
        .select()
        .eq('chat_room_id', roomId)
        .lt('created_at', before.toUtc().toIso8601String())
        .order('created_at', ascending: false)
        .limit(pageSize);
    return (rows as List)
        .map(
          (e) => ChatMessageModel.fromMap(Map<String, dynamic>.from(e as Map)),
        )
        .toList()
        .reversed
        .toList();
  }

  Future<ChatMessageModel> sendText({
    required ChatRoomModel room,
    required String text,
    bool isFollowUp = false,
    String? id,
    String? replyToMessageId,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) throw const ChatException('Message cannot be empty.');
    if (clean.length > 4000) {
      throw const ChatException(
        'Message is too long. Maximum is 4,000 characters.',
      );
    }
    return _insertMessage(
      room: room,
      id: id,
      type: MessageType.text,
      text: clean,
      isFollowUp: isFollowUp,
      replyToMessageId: replyToMessageId,
    );
  }

  Future<ChatMessageModel> sendAttachment({
    required ChatRoomModel room,
    required File file,
    required MessageType type,
    required String fileName,
    required String mimeType,
    bool isFollowUp = false,
    String? id,
    String? caption,
    int? voiceDurationSeconds,
    String? replyToMessageId,
  }) async {
    if (!{
      MessageType.image,
      MessageType.file,
      MessageType.voice,
    }.contains(type)) {
      throw const ChatException('Unsupported attachment type.');
    }
    final size = await file.length();
    final max = type == MessageType.image ? 15 * 1024 * 1024 : 25 * 1024 * 1024;
    if (size <= 0 || size > max) {
      throw ChatException(
        'This file must be smaller than ${max ~/ 1024 ~/ 1024} MB.',
      );
    }

    final messageId = id ?? _uuid.v4();
    final safeName = _sanitizeFileName(fileName);
    final storagePath = '$currentUserId/${room.id}/$messageId-$safeName';

    try {
      await _supabase.storage
          .from('chat-media')
          .upload(
            storagePath,
            file,
            fileOptions: FileOptions(contentType: mimeType, upsert: false),
          );
      try {
        return await _insertMessage(
          room: room,
          id: messageId,
          type: type,
          text: caption?.trim().isEmpty == true ? null : caption?.trim(),
          mediaUrl: storagePath,
          fileName: safeName,
          fileSizeBytes: size,
          mimeType: mimeType,
          voiceDurationSeconds: voiceDurationSeconds,
          isFollowUp: isFollowUp,
          replyToMessageId: replyToMessageId,
        );
      } catch (_) {
        await _supabase.storage.from('chat-media').remove([storagePath]);
        rethrow;
      }
    } on StorageException catch (e) {
      throw ChatException(e.message);
    }
  }

  Future<ChatMessageModel> _insertMessage({
    required ChatRoomModel room,
    String? id,
    required MessageType type,
    String? text,
    String? mediaUrl,
    String? fileName,
    int? fileSizeBytes,
    String? mimeType,
    int? voiceDurationSeconds,
    bool isFollowUp = false,
    String? replyToMessageId,
  }) async {
    if (!room.isActive && !isFollowUp) {
      throw const ChatException('This consultation chat is closed.');
    }
    final now = DateTime.now().toUtc();
    final draft = ChatMessageModel(
      id: id ?? _uuid.v4(),
      chatRoomId: room.id,
      bookingId: room.bookingId,
      senderId: currentUserId,
      type: type,
      status: MessageStatus.sent,
      text: text,
      mediaUrl: mediaUrl,
      fileName: fileName,
      fileSizeBytes: fileSizeBytes,
      mimeType: mimeType,
      voiceDurationSeconds: voiceDurationSeconds,
      replyToMessageId: replyToMessageId,
      createdAt: now,
      updatedAt: now,
    );
    try {
      final Map<String, dynamic> row;
      if (isFollowUp) {
        final result = await _supabase.rpc(
          'send_follow_up_chat_message',
          params: {
            'p_message_id': draft.id,
            'p_room_id': draft.chatRoomId,
            'p_booking_id': draft.bookingId,
            'p_type': draft.type.name,
            'p_text': draft.text,
            'p_media_url': draft.mediaUrl,
            'p_file_name': draft.fileName,
            'p_file_size_bytes': draft.fileSizeBytes,
            'p_mime_type': draft.mimeType,
            'p_voice_duration_seconds': draft.voiceDurationSeconds,
            'p_reply_to_message_id': draft.replyToMessageId,
          },
        );
        if (result is! Map) {
          throw const ChatException('The message could not be sent.');
        }
        row = Map<String, dynamic>.from(result);
      } else {
        final result = await _supabase
            .from('chat_messages')
            .insert(draft.toInsertMap())
            .select()
            .single();
        row = Map<String, dynamic>.from(result);
      }
      final message = ChatMessageModel.fromMap(row);
      await _notifyChatMessage(message.id);
      return message;
    } on PostgrestException catch (e) {
      throw ChatException(e.message);
    }
  }

  Future<void> _notifyChatMessage(String messageId) async {
    try {
      await _supabase.functions.invoke(
        'send-consultation-activity-notification',
        body: {'event': 'chat_message', 'message_id': messageId},
      );
    } catch (_) {
      // The message is already stored; push delivery is best effort.
    }
  }

  Future<void> markRoomRead(String roomId) async {
    await _supabase.rpc('mark_chat_room_read', params: {'p_room_id': roomId});
  }

  Future<void> markRoomDelivered(String roomId) async {
    await _supabase.rpc(
      'mark_chat_room_delivered',
      params: {'p_room_id': roomId},
    );
  }

  Future<void> deleteForEveryone(ChatMessageModel message) async {
    if (message.senderId != currentUserId) {
      throw const ChatException('You can only delete your own message.');
    }
    await _supabase.rpc(
      'soft_delete_chat_message',
      params: {'p_message_id': message.id},
    );
    if (message.mediaUrl != null) {
      try {
        await _supabase.storage.from('chat-media').remove([message.mediaUrl!]);
      } catch (_) {
        // The row is already safely redacted; storage cleanup can be retried later.
      }
    }
  }

  Future<String> createSignedMediaUrl(String storagePath) {
    final now = DateTime.now();
    final cached = _signedUrlCache[storagePath];
    if (cached != null && now.isBefore(cached.expiresAt)) {
      return cached.url;
    }
    final future = _supabase.storage
        .from('chat-media')
        .createSignedUrl(storagePath, 900);
    _signedUrlCache[storagePath] = _SignedUrlCacheEntry(
      url: future,
      expiresAt: now.add(const Duration(minutes: 12)),
    );
    future.catchError((_) {
      _signedUrlCache.remove(storagePath);
      return '';
    });
    return future;
  }

  String _sanitizeFileName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return cleaned.isEmpty
        ? 'attachment'
        : cleaned.substring(0, math.min(cleaned.length, 120));
  }
}

class _SignedUrlCacheEntry {
  const _SignedUrlCacheEntry({required this.url, required this.expiresAt});
  final Future<String> url;
  final DateTime expiresAt;
}
