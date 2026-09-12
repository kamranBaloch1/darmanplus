import 'dart:io';

import 'package:darmaan/core/models/user_model.dart';
import 'package:darmaan/core/services/offline_cache_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DoctorProfileRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  String _safeFileExtension(File file, {required String fallback}) {
    final fileName = file.path.split(RegExp(r'[/\\]')).last;
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return fallback;
    final extension = fileName.substring(dot + 1).toLowerCase();
    return RegExp(r'^[a-z0-9]{1,10}$').hasMatch(extension)
        ? extension
        : fallback;
  }

  Future<UserModel> getDoctorProfile() async {
    final authUser = _supabase.auth.currentUser;
    final doctorId = authUser?.id ??
        (await OfflineCacheService.instance.readLastUserId());

    if (doctorId == null) {
      throw Exception('No authenticated user found');
    }
    if (await OfflineCacheService.instance.isDeviceOffline) {
      final cached = await OfflineCacheService.instance.readUser(doctorId);
      if (cached != null) return cached;
    }

    try {
      final response = await _supabase
          .from('users')
          .select()
          .eq('uid', doctorId)
          .single();

      final doctor = UserModel.fromMap(response);
      await OfflineCacheService.instance.cacheUser(doctor);
      return doctor;
    } catch (error) {
      final cached = await OfflineCacheService.instance.readUser(doctorId);
      if (cached != null) return cached;
      if (error is PostgrestException) throw Exception(error.message);
      throw Exception('Failed to fetch profile: $error');
    }
  }

  Future<String> _uploadFile({
    required File file,
    required String bucket,
    required String uid,
    required String extension,
  }) async {
    final fileName = '${DateTime.now().microsecondsSinceEpoch}.$extension';
    final storagePath = '$uid/$fileName';

    await _supabase.storage.from(bucket).upload(
          storagePath,
          file,
          fileOptions: const FileOptions(upsert: true),
        );

    return _supabase.storage.from(bucket).getPublicUrl(storagePath);
  }

  /// Updates whichever fields are passed. Pass only what changed —
  /// null fields are left untouched in the database.
  Future<void> updateProfile({
    String? name,
    String? specialization,
    String? title,
    int? experienceYears,
    String? gender,
    double? consultationFee,
    File? profilePhoto,
    File? introVideo,
  }) async {
    final authUser = _supabase.auth.currentUser;

    if (authUser == null) {
      throw Exception('No authenticated user found');
    }

    try {
      final Map<String, dynamic> updates = {
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (name != null && name.trim().isNotEmpty) {
        updates['name'] = name.trim();
      }

      if (specialization != null && specialization.trim().isNotEmpty) {
        updates['specialization'] = specialization.trim();
      }

      if (title != null && title.trim().isNotEmpty) {
        updates['title'] = title.trim();
      }

      if (experienceYears != null && experienceYears > 0) {
        updates['experience_years'] = experienceYears;
      }

      if (gender != null && gender.trim().isNotEmpty) {
        updates['gender'] = gender.trim();
      }

      if (consultationFee != null) {
        updates['consultation_fee'] = consultationFee;
      }

      if (profilePhoto != null) {
        final url = await _uploadFile(
          file: profilePhoto,
          bucket: 'doctor-avatars',
          uid: authUser.id,
          extension: 'jpg',
        );
        updates['profile_image'] = url;
      }

      if (introVideo != null) {
        final url = await _uploadFile(
          file: introVideo,
          bucket: 'doctor-intro-videos',
          uid: authUser.id,
          extension: _safeFileExtension(introVideo, fallback: 'mp4'),
        );
        updates['intro_video_url'] = url;
      }

      await _supabase.from('users').update(updates).eq('uid', authUser.id);

      final profile = await _supabase
          .from('users')
          .select(
            'profile_image, specialization, title, experience_years, gender, '
            'consultation_fee, is_profile_completed',
          )
          .eq('uid', authUser.id)
          .single();
      bool hasText(String key) =>
          profile[key]?.toString().trim().isNotEmpty == true;
      final fee = (profile['consultation_fee'] as num?)?.toDouble() ?? 0;
      final years = (profile['experience_years'] as num?)?.toInt() ?? 0;
      final completed = hasText('profile_image') &&
          hasText('specialization') &&
          hasText('title') &&
          years > 0 &&
          hasText('gender') &&
          fee > 0;
      final wasCompleted = profile['is_profile_completed'] == true;
      final statusUpdates = <String, dynamic>{
        'is_profile_completed': completed,
      };
      if (completed && !wasCompleted) {
        statusUpdates['is_available'] = true;
      }
      await _supabase
          .from('users')
          .update(statusUpdates)
          .eq('uid', authUser.id);
    } on StorageException catch (e) {
      throw Exception(e.message);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      throw Exception('Failed to update profile: $e');
    }
  }

  /// Returns the public URL for a document path (e.g. "uid/172837...9_0.pdf")
  /// stored in the public doctor-documents bucket. Synchronous — no network call.
  String getDocumentPublicUrl(String path) {
    return _supabase.storage.from('doctor-documents').getPublicUrl(path);
  }

  /// Updates the doctor's online/offline availability status.
  Future<void> updateAvailability(bool isAvailable) async {
    final authUser = _supabase.auth.currentUser;

    if (authUser == null) {
      throw Exception('No authenticated user found');
    }

    try {
      await _supabase
          .from('users')
          .update({
            'is_available': isAvailable,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('uid', authUser.id);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      throw Exception('Failed to update availability: $e');
    }
  }
}
