import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

class PhoneAuthRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> sendOtp({required String phoneNumber}) async {
    try {
      final response = await _supabase.functions.invoke(
        'send-whatsapp-otp',
        body: {'phone': phoneNumber},
      );
      if (response.status != 200) {
        throw Exception(_sendError(_errorCode(response.data)));
      }
    } on FunctionException catch (error) {
      throw Exception(_sendError(_errorCode(error.details)));
    }
  }

  Future<void> verifyOtp({
    required String phoneNumber,
    required String otp,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'verify-whatsapp-otp',
        body: {'phone': phoneNumber, 'otp': otp},
      );
      if (response.status != 200 || response.data is! Map) {
        throw Exception(_verifyError(_errorCode(response.data)));
      }

      final refreshToken = (response.data as Map)['refresh_token'] as String?;
      if (refreshToken == null || refreshToken.isEmpty) {
        throw Exception('invalid_session');
      }
      final authResponse = await _supabase.auth.setSession(refreshToken);
      if (authResponse.session == null || authResponse.user == null) {
        throw Exception('invalid_session');
      }
    } on FunctionException catch (error) {
      throw Exception(_verifyError(_errorCode(error.details)));
    } on AuthException {
      throw Exception('invalid_session');
    }
  }

  String? _errorCode(dynamic data) {
    if (data is Map) return data['error']?.toString();
    if (data is String) {
      final value = data.trim();
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return decoded['error']?.toString();
      } catch (_) {
        // Some function failures contain a plain error code rather than JSON.
      }
      return value;
    }
    return null;
  }

  String _sendError(String? code) {
    switch (code) {
      case 'invalid_phone_format':
        return 'invalid_phone';
      case 'phone_not_registered_whatsapp':
        return 'phone_not_registered_whatsapp';
      case 'max_attempts_reached':
        return 'max_attempts_reached';
      default:
        return 'otp_send_failed';
    }
  }

  String _verifyError(String? code) {
    switch (code) {
      case 'otp_invalid':
      case 'otp_expired':
      case 'max_attempts_reached':
        return code!;
      case 'invalid_phone_format':
        return 'invalid_phone';
      case 'session_creation_failed':
      case 'user_creation_failed':
      case 'invalid_session':
        return 'invalid_session';
      default:
        return 'otp_verification_failed';
    }
  }
}
