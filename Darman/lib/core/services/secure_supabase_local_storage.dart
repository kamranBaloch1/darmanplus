import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Encrypted Supabase session persistence with a one-time migration from the
/// package's previous SharedPreferences storage. This prevents an app update
/// from unexpectedly signing out existing users.
class SecureSupabaseLocalStorage extends LocalStorage {
  SecureSupabaseLocalStorage({required this.persistSessionKey});

  final String persistSessionKey;

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );

  @override
  Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    final encrypted = await _secureStorage.read(key: persistSessionKey);
    if (encrypted != null && encrypted.isNotEmpty) return;

    final preferences = await SharedPreferences.getInstance();
    final previousSession = preferences.getString(persistSessionKey);
    if (previousSession == null || previousSession.isEmpty) return;

    await _secureStorage.write(
      key: persistSessionKey,
      value: previousSession,
    );
    await preferences.remove(persistSessionKey);
  }

  @override
  Future<bool> hasAccessToken() async {
    final value = await _secureStorage.read(key: persistSessionKey);
    return value != null && value.isNotEmpty;
  }

  @override
  Future<String?> accessToken() =>
      _secureStorage.read(key: persistSessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _secureStorage.write(
        key: persistSessionKey,
        value: persistSessionString,
      );

  @override
  Future<void> removePersistedSession() =>
      _secureStorage.delete(key: persistSessionKey);
}
