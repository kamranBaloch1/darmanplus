class AppErrorMessage {
  const AppErrorMessage._();

  static String from(
    Object? error, {
    String fallback = 'Something went wrong. Please try again.',
  }) {
    if (error == null) return fallback;

    var message = error.toString().trim();
    for (final prefix in const [
      'Exception: ',
      'ClientException: ',
      'AuthException: ',
      'StorageException: ',
      'PostgrestException: ',
      'FunctionsHttpError: ',
      'RealtimeSubscribeException: ',
    ]) {
      if (message.startsWith(prefix)) message = message.substring(prefix.length);
    }

    final lower = message.toLowerCase();

    if (_containsAny(lower, const [
      'socketexception',
      'failed host lookup',
      'network is unreachable',
      'connection refused',
      'connection reset',
      'network request failed',
      'no internet',
      'timed out',
      'timeout',
      'realtimesubscribeexception',
    ])) {
      return 'Please check your internet connection and try again.';
    }

    if (_containsAny(lower, const [
      'jwt expired',
      'invalid jwt',
      'refresh token',
      'session expired',
      'not authenticated',
    ])) {
      return 'Your session has expired. Please sign in again.';
    }

    if (_containsAny(lower, const [
      'invalid login credentials',
      'invalid credentials',
      'invalid otp',
      'token has expired',
      'otp expired',
    ])) {
      return 'The verification details are incorrect or expired. Please try again.';
    }

    if (_containsAny(lower, const [
      'permission denied',
      'not authorized',
      'row-level security',
      'row level security',
      'security policy',
      '42501',
    ])) {
      return 'You do not have permission to perform this action.';
    }

    if (_containsAny(lower, const [
      'insufficient wallet',
      'insufficient balance',
      'not enough balance',
    ])) {
      return 'Your wallet balance is insufficient for this consultation.';
    }

    if (_containsAny(lower, const [
      'duplicate key',
      'already exists',
      '23505',
    ])) {
      return 'This information already exists.';
    }

    if (_containsAny(lower, const [
      'could not find the function',
      'function not found',
      'edge function',
      'functionshttperror',
      'pgrst202',
      'pgrst204',
      'relation does not exist',
      'column does not exist',
      'sqlstate',
      'twilio',
      'firebase_service_account',
      'invalid api key',
      'authentication error - invalid username',
    ])) {
      return 'This service is temporarily unavailable. Please try again shortly.';
    }

    if (_looksTechnical(message, lower)) return fallback;

    return message.isEmpty ? fallback : message;
  }

  static bool _looksTechnical(String message, String lower) {
    if (message.length > 220 || message.contains('\n') || message.contains(' at #')) {
      return true;
    }
    if (RegExp(r'^[a-z0-9]+(?:_[a-z0-9]+)+$').hasMatch(message)) {
      return true;
    }
    return _containsAny(lower, const [
      'postgrest',
      'supabase',
      'postgres',
      'stack trace',
      'dart:',
      'package:',
      'statuscode:',
      'status code:',
      'status:',
      'details:',
      'hint:',
      'code:',
      '<html',
      'https://',
      'http://',
    ]);
  }

  static bool _containsAny(String value, List<String> candidates) =>
      candidates.any(value.contains);
}
