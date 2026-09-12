import 'package:darmaan/core/helpers/push_notification_service.dart';
import 'package:darmaan/core/services/offline_cache_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class AuthRepository {
  AuthRepository({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<void> logout() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId != null) {
      try {
        // Run this while the authenticated session is still available. The
        // role filter makes the shared patient/doctor logout flow safe.
        await _supabase
            .from('users')
            .update({
              'is_available': false,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('uid', userId)
            .eq('role', 'doctor');
      } catch (_) {
        // Signing out must remain possible if the device loses its connection
        // during this best-effort server update.
      }
    }
    try {
      await PushNotificationService.instance.deactivateBeforeSignOut();
    } catch (_) {
      // Notification cleanup is best effort and must not trap the user in
      // their account when the device is offline.
    }
    await OfflineCacheService.instance.clear();
    try {
      await DefaultCacheManager().emptyCache();
    } catch (_) {}
    await _supabase.auth.signOut(scope: SignOutScope.local);
  }
}
