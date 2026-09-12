import 'package:darmaan/core/models/booking_model.dart';
import 'package:darmaan/core/models/user_model.dart';
import 'package:darmaan/core/services/offline_cache_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DoctorAppoinmentsRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<BookingModel>> getDoctorBookings() async {
    final doctorId = _supabase.auth.currentUser?.id ??
        (await OfflineCacheService.instance.readLastUserId());
    if (doctorId == null) {
      throw Exception('You must be signed in to view your appointments.');
    }
    if (await OfflineCacheService.instance.isDeviceOffline) {
      final cached = await OfflineCacheService.instance.readBookings(
        role: 'doctor',
        userId: doctorId,
      );
      if (cached != null) return cached;
    }

    try {
      final response = await _supabase
          .from('bookings')
          .select()
          .eq('doctor_id', doctorId)
          .order('created_at', ascending: false);

      final bookings = (response as List)
          .map((row) => BookingModel.fromMap(row as Map<String, dynamic>))
          .toList();
      await OfflineCacheService.instance.cacheBookings(
        role: 'doctor',
        userId: doctorId,
        bookings: bookings,
      );
      return bookings;
    } catch (error) {
      final cached = await OfflineCacheService.instance.readBookings(
        role: 'doctor',
        userId: doctorId,
      );
      if (cached != null) return cached;
      if (error is PostgrestException) throw Exception(error.message);
      throw Exception('Failed to fetch your appointments: $error');
    }
  }

  Future<Map<String, UserModel>> getPatientsByIds(
    List<String> patientIds,
  ) async {
    if (patientIds.isEmpty) return {};
    final ownerId = _supabase.auth.currentUser?.id ??
        (await OfflineCacheService.instance.readLastUserId());
    if (ownerId == null) {
      throw Exception('You must be signed in to view patient details.');
    }
    if (await OfflineCacheService.instance.isDeviceOffline) {
      final cached = await OfflineCacheService.instance.readPeople(
        scope: 'doctor_patients',
        userId: ownerId,
      );
      if (cached != null) {
        return Map.fromEntries(
          cached.entries.where((entry) => patientIds.contains(entry.key)),
        );
      }
    }

    try {
      final response = await _supabase
          .from('users')
          .select()
          .inFilter('uid', patientIds);

      final patients = (response as List)
          .map((row) => UserModel.fromMap(row as Map<String, dynamic>))
          .toList();

      await OfflineCacheService.instance.cachePeople(
        scope: 'doctor_patients',
        userId: ownerId,
        people: patients,
      );
      return {for (final patient in patients) patient.uid: patient};
    } catch (error) {
      final cached = await OfflineCacheService.instance.readPeople(
        scope: 'doctor_patients',
        userId: ownerId,
      );
      if (cached != null) {
        return Map.fromEntries(
          cached.entries.where((entry) => patientIds.contains(entry.key)),
        );
      }
      if (error is PostgrestException) throw Exception(error.message);
      throw Exception('Failed to load patient details: $error');
    }
  }

  Future<Map<String, int>> getRatingsByBookingIds(
    List<String> bookingIds,
  ) async {
    if (bookingIds.isEmpty || _supabase.auth.currentUser == null) return {};
    try {
      final rows = await _supabase
          .from('consultation_ratings')
          .select('booking_id, rating')
          .inFilter('booking_id', bookingIds);
      return {
        for (final row in rows as List)
          if (row['booking_id'] != null && row['rating'] is num)
            row['booking_id'].toString(): (row['rating'] as num).toInt(),
      };
    } catch (_) {
      // Ratings are optional history metadata; history should still load.
      return {};
    }
  }

  Future<void> acceptBooking(String bookingId) async {
    final doctorId = _supabase.auth.currentUser?.id;
    if (doctorId == null) {
      throw Exception('You must be signed in to accept a booking.');
    }

    final now = DateTime.now().toUtc();

    try {
      final updated = await _supabase
          .from('bookings')
          .update({
            'status': BookingStatus.accepted.name,
            'accepted_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          })
          .eq('id', bookingId)
          .eq('doctor_id', doctorId)
          .eq('status', BookingStatus.pending.name)
          .select();

      if ((updated as List).isEmpty) {
        throw Exception(
          'This request can no longer be accepted. It may already have '
          'been cancelled or resolved.',
        );
      }

      await _notifyPatient(bookingId);
    } on PostgrestException catch (error) {
      throw Exception(error.message);
    }
  }

  Future<void> cancelBooking(String bookingId) async {
    if (_supabase.auth.currentUser == null) {
      throw Exception('You must be signed in to cancel an appointment.');
    }

    try {
      await _supabase.rpc(
        'cancel_booking_as_doctor',
        params: {
          'p_booking_id': bookingId,
          'p_reason': 'Cancelled by doctor',
        },
      );

      await _notifyPatient(bookingId);
    } on PostgrestException catch (error) {
      throw Exception(error.message);
    }
  }

  Future<void> _notifyPatient(String bookingId) async {
    try {
      await _supabase.functions.invoke(
        'send-booking-status-notification',
        body: {'booking_id': bookingId},
      );
    } catch (_) {
      // Accepting or cancelling must remain successful if FCM is unavailable.
    }
  }
}
