import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DoctorRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> submitDoctorDocuments(
    List<XFile> documents, {
    required String name,
    required File profilePhoto,
  }) async {
    final authUser = _supabase.auth.currentUser;

    if (authUser == null) {
      throw Exception('No authenticated user found');
    }

    if (documents.isEmpty) {
      throw Exception('Please select at least one document');
    }
    if (name.trim().length < 2) {
      throw Exception('Please enter your full name');
    }
    if (!await profilePhoto.exists()) {
      throw Exception('Please select a valid profile photo');
    }

    final List<String> uploadedDocumentPaths = [];

    try {
      final avatarPath =
          '${authUser.id}/${DateTime.now().microsecondsSinceEpoch}.jpg';
      await _supabase.storage.from('doctor-avatars').upload(
            avatarPath,
            profilePhoto,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );
      final profileImageUrl = _supabase.storage
          .from('doctor-avatars')
          .getPublicUrl(avatarPath);

      for (int i = 0; i < documents.length; i++) {
        final document = documents[i];

        if (document.path == null) {
          throw Exception(
            'Unable to access ${document.name}',
          );
        }

        final file = File(document.path!);

        final fileName =
            '${DateTime.now().microsecondsSinceEpoch}_$i.pdf';

        final storagePath =
            '${authUser.id}/$fileName';

        await _supabase.storage
            .from('doctor-documents')
            .upload(
              storagePath,
              file,
              fileOptions: const FileOptions(
                contentType: 'application/pdf',
                upsert: false,
              ),
            );

        uploadedDocumentPaths.add(storagePath);
      }

      // Update existing doctor user
      await _supabase
          .from('users')
          .update({
            'name': name.trim(),
            'profile_image': profileImageUrl,
            'doctor_documents': uploadedDocumentPaths,
            'is_profile_completed': false,
            'is_doctor_verified': false,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('uid', authUser.id);
    } on StorageException catch (e) {
      throw Exception(e.message);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      throw Exception(
        'Failed to submit documents: $e',
      );
    }
  }
}
