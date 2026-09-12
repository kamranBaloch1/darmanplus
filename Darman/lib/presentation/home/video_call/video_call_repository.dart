import 'package:darmaan/core/models/video_call_access.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VideoCallException implements Exception {
  const VideoCallException(this.message);
  final String message;
  @override String toString() => message;
}

class VideoCallRepository {
  VideoCallRepository({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  Future<VideoCallAccess> getAccess(String bookingId) async {
    try {
      final response = await _client.functions.invoke('agora-token', body: {'booking_id': bookingId});
      if (response.status < 200 || response.status >= 300 || response.data is! Map) {
        throw VideoCallException(_message(response.data));
      }
      return VideoCallAccess.fromMap(Map<String, dynamic>.from(response.data as Map));
    } catch (error) {
      if (error is VideoCallException) rethrow;
      throw VideoCallException(error.toString());
    }
  }

  Future<void> markJoined(String bookingId) async {
    await _client.rpc('mark_consultation_call_joined', params: {'p_booking_id': bookingId});
  }

  Future<void> markLeft(String bookingId) async {
    await _client.rpc('mark_consultation_call_left', params: {'p_booking_id': bookingId});
  }

  Future<void> endCall(String bookingId) async {
    await _client.rpc(
      'end_active_video_call',
      params: {'p_booking_id': bookingId},
    );
  }

  String _message(dynamic data) => data is Map && data['error'] != null
      ? data['error'].toString()
      : 'Unable to join the consultation.';
}
