import 'package:darmaan/core/models/user_model.dart';
import 'package:darmaan/core/services/offline_cache_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Creates the user's profile row right after they pick a role
  /// (patient/doctor) for the first time.
  Future<void> createUser({
    required UserRole role,
  }) async {
    final authUser = _supabase.auth.currentUser;

    if (authUser == null) {
      throw Exception('No authenticated user found');
    }

    try {
      final userModel = UserModel(
        uid: authUser.id,
        name: 'User',
        role: role,

        email: authUser.email,
        isEmailVerified: authUser.emailConfirmedAt != null,

        phone: authUser.phone ??
            authUser.userMetadata?['verified_phone']?.toString(),
        isPhoneVerified: true,

        profileImage: null,
        isProfileCompleted: false,

        doctorDocuments: const [],

        isDoctorVerified: false,
        isAvailable: false,

        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await _supabase
          .from('users')
          .insert(userModel.toMap());
      await OfflineCacheService.instance.cacheUser(userModel);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      throw Exception('Failed to create user: $e');
    }
  }

  /// Fetches the current authenticated user's profile row.
  /// Returns null if:
  /// - nobody is logged in, OR
  /// - the user is logged in with Supabase Auth but hasn't picked a role
  ///   yet (no row in `users` table).
  Future<UserModel?> getCurrentUser() async {
    final authUser = _supabase.auth.currentUser;

    if (authUser == null) return OfflineCacheService.instance.readUser();
    if (await OfflineCacheService.instance.isDeviceOffline) {
      final cached = await OfflineCacheService.instance.readUser(authUser.id);
      if (cached != null) return cached;
    }

    try {
      final response = await _supabase
          .from('users')
          .select()
          .eq('uid', authUser.id)
          .maybeSingle();

      if (response == null) return null;

      final row = Map<String, dynamic>.from(response);
      final authPhone = (authUser.phone ??
              authUser.userMetadata?['verified_phone']?.toString())
          ?.trim();
      if ((row['phone'] == null || row['phone'].toString().trim().isEmpty) &&
          authPhone?.isNotEmpty == true) {
        await _supabase.from('users').update({
          'phone': authPhone,
          'is_phone_verified': true,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('uid', authUser.id);
        row['phone'] = authPhone;
        row['is_phone_verified'] = true;
      }

      final user = UserModel.fromMap(row);
      await OfflineCacheService.instance.cacheUser(user);
      return user;
    } catch (error) {
      final cached = await OfflineCacheService.instance.readUser(authUser.id);
      if (cached != null) return cached;
      if (error is PostgrestException) throw Exception(error.message);
      throw Exception('Failed to fetch user: $error');
    }
  }
}
