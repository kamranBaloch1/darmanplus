import 'package:darmaan/core/models/video_call_invite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VideoCallInviteRepository {
  VideoCallInviteRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;
  String get currentUserId {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Sign in is required to receive calls.');
    }
    return user.id;
  }

  Future<VideoCallInvite> startCall(String bookingId) async {
    dynamic result;
    try {
      result = await _client.rpc(
        'start_consultation_video_call',
        params: {'p_booking_id': bookingId},
      );
    } on PostgrestException catch (error) {
      final message = error.message.toLowerCase();
      if (message.contains('you are currently on another call')) {
        throw const VideoCallInviteException(
          'You already have an active call. Return to that call before starting another one.',
        );
      }
      if (message.contains('currently on another call')) {
        throw const VideoCallInviteException(
          'This user is currently on another call. Please try again later.',
        );
      }
      if (message.contains('incoming call') && message.contains('waiting')) {
        throw const VideoCallInviteException(
          'This user is already calling you. Please answer the incoming call.',
        );
      }
      rethrow;
    }
    final row = await _client
        .from('consultation_call_invites')
        .select()
        .eq('id', result.toString())
        .single();
    final invite = VideoCallInvite.fromMap(row);
    try {
      await _client.functions.invoke(
        'send-call-notification',
        body: {'invite_id': invite.id},
      );
    } catch (_) {
      // Realtime still delivers the incoming-call screen while both users are
      // in the app. Push delivery remains best effort and must not abort a call.
    }
    return invite;
  }

  Future<CallParticipantProfile> getParticipantProfile(String userId) async {
    final row = await _client
        .from('users')
        .select('name, profile_image, is_doctor_verified, specialization, title')
        .eq('uid', userId)
        .maybeSingle();
    return CallParticipantProfile(
      name: row?['name']?.toString(),
      photoUrl: row?['profile_image']?.toString(),
      verified: row?['is_doctor_verified'] == true,
      specialization: row?['specialization']?.toString(),
      title: row?['title']?.toString(),
    );
  }

  Future<VideoCallInvite?> getIncomingInvite(String inviteId) async {
    final cleanId = inviteId.trim();
    if (cleanId.isEmpty) return null;
    final row = await _client
        .from('consultation_call_invites')
        .select()
        .eq('id', cleanId)
        .eq('callee_id', currentUserId)
        .maybeSingle();
    if (row == null) return null;
    final invite = VideoCallInvite.fromMap(row);
    if (invite.status != VideoCallInviteStatus.ringing || invite.isExpired) {
      return null;
    }
    return invite;
  }

  Future<void> respond(String inviteId, bool accept) async {
    await _client.rpc(
      'respond_consultation_video_call',
      params: {'p_invite_id': inviteId, 'p_accept': accept},
    );
  }

  Future<void> cancel(String inviteId) async {
    await _client.rpc(
      'cancel_consultation_video_call',
      params: {'p_invite_id': inviteId},
    );
    try {
      await _client.functions.invoke(
        'send-call-notification',
        body: {'invite_id': inviteId},
      );
    } catch (_) {
      // Realtime still closes the incoming screen when both apps are active.
      // The cancellation push is best effort for a backgrounded callee.
    }
  }

  Stream<List<VideoCallInvite>> watchIncoming() => _client
      .from('consultation_call_invites')
      .stream(primaryKey: ['id'])
      .eq('callee_id', currentUserId)
      .order('created_at', ascending: false)
      .map(
        (rows) => rows
            .map(VideoCallInvite.fromMap)
            .where(
              (i) => i.status == VideoCallInviteStatus.ringing && !i.isExpired,
            )
            .toList(),
      );

  Stream<VideoCallInvite> watchInvite(String inviteId) => _client
      .from('consultation_call_invites')
      .stream(primaryKey: ['id'])
      .eq('id', inviteId)
      .map((rows) {
        if (rows.isEmpty) throw StateError('Call request not found');
        return VideoCallInvite.fromMap(rows.single);
      });
}

class VideoCallInviteException implements Exception {
  const VideoCallInviteException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CallParticipantProfile {
  const CallParticipantProfile({
    this.name,
    this.photoUrl,
    this.verified = false,
    this.specialization,
    this.title,
  });

  final String? name;
  final String? photoUrl;
  final bool verified;
  final String? specialization;
  final String? title;

  String get subtitle {
    final values = [specialization, title]
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    return values.join(' | ');
  }
}
