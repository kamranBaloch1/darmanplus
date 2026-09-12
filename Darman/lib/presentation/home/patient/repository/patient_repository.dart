import 'dart:io';
import 'dart:math' as math;

import 'package:darmaan/core/models/booking_model.dart';
import 'package:darmaan/core/models/consultation_review_model.dart';
import 'package:darmaan/core/models/doctor_review_summary_model.dart';
import 'package:darmaan/core/models/user_model.dart';
import 'package:darmaan/core/services/offline_cache_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PatientRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const String _playReviewDoctorId =
      '9b9dd1ed-c6a2-459a-9035-a209f350c0b8';
  static const String _playReviewPatientId =
      '364705c0-2319-468d-8871-d17bb2a33c25';

  bool _canShowInPublicCatalogue(UserModel doctor) {
    final viewerId = _supabase.auth.currentUser?.id;
    if (viewerId == _playReviewPatientId) {
      return doctor.uid == _playReviewDoctorId;
    }
    return doctor.uid != _playReviewDoctorId;
  }

  static const List<String> _activeStatuses = [
    'pending',
    'accepted',
    'inProgress',
  ];

  /// Fetches completed, verified doctor profiles. Available doctors are shown
  /// first. Rating order uses a 95% confidence-adjusted lower bound so a very
  /// small number of perfect reviews cannot outrank a consistently strong
  /// doctor purely because of the raw average.
  Future<List<UserModel>> getDoctorsBySpecialization(
    String specialization,
  ) => _getPublicDoctors(specialization: specialization);

  Future<List<UserModel>> getAllDoctors() => _getPublicDoctors();

  Stream<List<BookingModel>> watchActivePatientBookings() {
    final patientId = _supabase.auth.currentUser?.id;
    if (patientId == null) return Stream.value(const []);

    return _supabase
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('patient_id', patientId)
        .map((rows) {
          final bookings = rows
              .map(BookingModel.fromMap)
              .where(
                (booking) =>
                    _activeStatuses.contains(booking.status.name) ||
                    booking.hasUpcomingFollowUp,
              )
              .toList()
            ..sort((a, b) {
              if (a.hasUpcomingFollowUp != b.hasUpcomingFollowUp) {
                return a.hasUpcomingFollowUp ? -1 : 1;
              }
              final aDate = a.followUpDate;
              final bDate = b.followUpDate;
              if (aDate != null && bDate != null) {
                final order = aDate.compareTo(bDate);
                if (order != 0) return order;
              }
              return b.updatedAt.compareTo(a.updatedAt);
            });
          return bookings;
        });
  }

  Future<List<UserModel>> _getPublicDoctors({String? specialization}) async {
    if (await OfflineCacheService.instance.isDeviceOffline) {
      final cached = await OfflineCacheService.instance.readPublicDoctors(
        specialization: specialization,
      );
      if (cached != null) {
        return cached
            .where(_canShowInPublicCatalogue)
            .map((doctor) {
              final map = doctor.toMap()..['is_available'] = false;
              return UserModel.fromMap(map);
            })
            .toList();
      }
    }
    try {
      final response = await _supabase.functions.invoke(
        'public-doctors',
        body: {
          if (specialization != null) 'specialization': specialization,
        },
      );
      if (response.status != 200 || response.data is! Map) {
        throw Exception('Unable to load doctors right now.');
      }
      final doctors = (response.data as Map)['doctors'];
      if (doctors is! List) {
        throw Exception('Unable to load doctors right now.');
      }

      final result = doctors
          .map((row) => UserModel.fromMap(row as Map<String, dynamic>))
          .where(_canShowInPublicCatalogue)
          .toList();
      result.sort((a, b) {
        if (a.isAvailable != b.isAvailable) {
          return a.isAvailable ? -1 : 1;
        }
        final ratingOrder = _doctorRankingScore(b).compareTo(
          _doctorRankingScore(a),
        );
        if (ratingOrder != 0) return ratingOrder;
        final reviewOrder = b.doctorReviewCount.compareTo(a.doctorReviewCount);
        if (reviewOrder != 0) return reviewOrder;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      await OfflineCacheService.instance.cachePublicDoctors(
        result,
        specialization: specialization,
      );
      return result;
    } catch (e) {
      final cached = await OfflineCacheService.instance.readPublicDoctors(
        specialization: specialization,
      );
      if (cached != null) {
        // Availability is live state. Never advertise a cached doctor as
        // reachable while the current refresh cannot contact the server.
        return cached
            .where(_canShowInPublicCatalogue)
            .map((doctor) {
              final map = doctor.toMap()..['is_available'] = false;
              return UserModel.fromMap(map);
            })
            .toList();
      }
      final message = e.toString().replaceFirst('Exception: ', '');
      throw Exception(message);
    }
  }

  /// Wilson lower confidence bound applied to the normalized average rating.
  /// The review count controls confidence: more evidence makes the score less
  /// volatile while new doctors can still move upward as reviews accumulate.
  static double _doctorRankingScore(UserModel doctor) {
    final count = doctor.doctorReviewCount;
    if (count <= 0) return -1;

    const z = 1.96;
    const zSquared = z * z;
    final normalizedRating =
        (doctor.doctorRating / 5).clamp(0.0, 1.0).toDouble();
    final denominator = 1 + zSquared / count;
    final center = normalizedRating + zSquared / (2 * count);
    final margin = z * math.sqrt(
      (normalizedRating * (1 - normalizedRating) +
              zSquared / (4 * count)) /
          count,
    );
    return (center - margin) / denominator;
  }

  Future<List<ConsultationReviewModel>> getDoctorReviews(
    String doctorId, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final rows = await _supabase.rpc(
        'get_doctor_reviews',
        params: {'p_doctor_id': doctorId, 'p_limit': limit, 'p_offset': offset},
      );
      return (rows as List)
          .map(
            (row) => ConsultationReviewModel.fromMap(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw Exception(error.message);
    }
  }

  Future<DoctorReviewSummaryModel> getDoctorReviewSummary(
    String doctorId,
  ) async {
    try {
      final result = await _supabase.rpc(
        'get_doctor_review_summary',
        params: {'p_doctor_id': doctorId},
      );
      return DoctorReviewSummaryModel.fromMap(
        Map<String, dynamic>.from(result as Map),
      );
    } on PostgrestException catch (error) {
      throw Exception(error.message);
    }
  }

  /// Creates a booking for the signed-in patient with [doctorId].
  ///
  /// Re-reads the doctor's row instead of trusting whatever the profile
  /// screen had cached, so a stale fee or availability flag can't slip
  /// into a real booking. Blocks a second active booking with the same
  /// doctor, then reserves the consultation fee out of the patient's
  /// wallet before the booking row is created — if the patient doesn't
  /// have enough balance, nothing is booked. Reservation and booking creation
  /// happen together in one database transaction so a failed booking can never
  /// leave money stuck or allow two requests to spend the same balance.
  ///
  /// The commission split isn't computed here — it happens once the
  /// consultation is marked completed, at which point the doctor's cut
  /// moves from the patient's `wallet_reserved_balance` into the doctor's
  /// own `wallet_balance` (the same field doubles as the doctor's payout
  /// balance and the patient's spendable balance — `wallet_reserved_balance`
  /// is only ever used on the patient side, to hold funds mid-booking).
   Future<BookingModel> createBooking({required String doctorId}) async {
    final patientId = _supabase.auth.currentUser?.id;
    if (patientId == null) {
      throw Exception('You must be signed in to book an appointment.');
    }

    if (doctorId == patientId) {
      throw Exception('You cannot book yourself.');
    }

    await _assertNoDuplicateDoctorBooking(
      patientId: patientId,
      doctorId: doctorId,
    );
    final doctor = await _getAvailableDoctorOrThrow(doctorId);

    final fee = doctor.consultationFee!;

    try {
      final inserted = await _supabase.rpc(
        'create_patient_booking_secure',
        params: {'p_doctor_id': doctorId},
      );

      final booking = BookingModel.fromMap(
        Map<String, dynamic>.from(inserted as Map),
      );

      // The booking is already created, so notification failure must not
      // cancel the booking or release its reserved wallet amount.
      try {
        await _supabase.functions.invoke(
          'send-booking-notification',
          body: {'booking_id': booking.id},
        );
      } catch (_) {}

      return booking;
    } on PostgrestException catch (e) {
      if (e.message.toLowerCase().contains('insufficient wallet balance')) {
        final row = await _supabase
            .from('users')
            .select('wallet_balance')
            .eq('uid', patientId)
            .single();
        final available = (row['wallet_balance'] as num?)?.toDouble() ?? 0;
        throw InsufficientWalletBalanceException(
          requiredAmount: fee,
          availableBalance: available,
          shortfall: (fee - available).clamp(0, double.infinity),
        );
      }
      throw Exception(_friendlyInsertError(e));
    } catch (e) {
      if (e is InsufficientWalletBalanceException) rethrow;
      throw Exception('Failed to create booking: $e');
    }
  }

  /// Streams live updates for a single booking (status changes, join
  /// timestamps, etc.) so the UI can react as the doctor accepts, starts,
  /// or rejects the consultation without polling.
  Stream<BookingModel> watchBooking(String bookingId) {
    return _supabase
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('id', bookingId)
        .map((rows) {
          if (rows.isEmpty) {
            throw Exception('This booking no longer exists.');
          }
          return BookingModel.fromMap(rows.first);
        });
  }

  /// Returns an upcoming follow-up first, otherwise the most recently updated
  /// active booking between the signed-in patient and [doctorId].
  Future<BookingModel?> getActiveBooking({required String doctorId}) async {
    final patientId = _supabase.auth.currentUser?.id;
    if (patientId == null) return null;

    try {
      final followUps = await _supabase
          .from('bookings')
          .select()
          .eq('patient_id', patientId)
          .eq('doctor_id', doctorId)
          .eq('status', BookingStatus.completed.name)
          .order('follow_up_date')
          .limit(20);
      final relevantFollowUps = (followUps as List)
          .map((row) => BookingModel.fromMap(
                Map<String, dynamic>.from(row as Map),
              ))
          .where(
            (booking) =>
                booking.isFollowUpOpen || booking.hasUpcomingFollowUp,
          )
          .toList();
      if (relevantFollowUps.isNotEmpty) {
        relevantFollowUps.sort((a, b) {
          if (a.isFollowUpOpen != b.isFollowUpOpen) {
            return a.isFollowUpOpen ? -1 : 1;
          }
          return a.followUpDate!.compareTo(b.followUpDate!);
        });
        return relevantFollowUps.first;
      }

      final activeRows = await _supabase
          .from('bookings')
          .select()
          .eq('patient_id', patientId)
          .eq('doctor_id', doctorId)
          .inFilter('status', _activeStatuses)
          .order('updated_at', ascending: false)
          .limit(1);
      if ((activeRows as List).isEmpty) return null;
      return BookingModel.fromMap(
        Map<String, dynamic>.from(activeRows.first as Map),
      );
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      throw Exception('Failed to check booking status: $e');
    }
  }

  Future<List<BookingModel>> getActiveFollowUpsForDoctor({
    required String doctorId,
  }) async {
    final patientId = _supabase.auth.currentUser?.id;
    if (patientId == null) return const [];
    try {
      final rows = await _supabase
          .from('bookings')
          .select()
          .eq('patient_id', patientId)
          .eq('doctor_id', doctorId)
          .eq('status', BookingStatus.completed.name)
          .order('follow_up_date');
      final followUps = (rows as List)
          .map(
            (row) => BookingModel.fromMap(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .where((booking) => booking.hasUpcomingFollowUp)
          .toList();
      followUps.sort((a, b) {
        if (a.isFollowUpOpen != b.isFollowUpOpen) {
          return a.isFollowUpOpen ? -1 : 1;
        }
        return a.followUpDate!.compareTo(b.followUpDate!);
      });
      return followUps;
    } on PostgrestException catch (error) {
      throw Exception(error.message);
    }
  }

  Future<BookingModel?> getActiveStandardBooking({
    required String doctorId,
  }) async {
    final patientId = _supabase.auth.currentUser?.id;
    if (patientId == null) return null;
    try {
      final rows = await _supabase
          .from('bookings')
          .select()
          .eq('patient_id', patientId)
          .eq('doctor_id', doctorId)
          .inFilter('status', _activeStatuses)
          .order('updated_at', ascending: false)
          .limit(1);
      if ((rows as List).isEmpty) return null;
      return BookingModel.fromMap(
        Map<String, dynamic>.from(rows.first as Map),
      );
    } on PostgrestException catch (error) {
      throw Exception(error.message);
    }
  }

  /// Lets the patient cancel a booking that's still `pending` — once a
  /// doctor has accepted or the consult has started, cancellation should
  /// go through a separate flow (refund handling, notifying the doctor).
  ///
  /// The consultation fee was moved out of the patient's spendable
  /// `wallet_balance` into `wallet_reserved_balance` atomically when the
  /// booking is created. Cancelling here releases
  /// that reservation back to the patient — otherwise the money would sit
  /// locked against a booking that no longer exists.
  Future<void> cancelPendingBooking(String bookingId, {String? reason}) async {
    final patientId = _supabase.auth.currentUser?.id;
    if (patientId == null) {
      throw Exception('You must be signed in to cancel a booking.');
    }

    try {
      await _supabase.rpc(
        'cancel_appointment_as_patient',
        params: {
          'p_booking_id': bookingId,
          'p_reason': reason ?? 'Cancelled by patient',
        },
      );
      await _notifyDoctorOfPatientCancellation(bookingId);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  /// Uses the database clock so cancellation eligibility cannot be changed by
  /// editing the device date or time.
  Future<DateTime> getConsultationServerTime() async {
    try {
      final value = await _supabase.rpc('consultation_server_now');
      final parsed = DateTime.tryParse(value.toString())?.toUtc();
      if (parsed == null) {
        throw Exception('The server returned an invalid time.');
      }
      return parsed;
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<void> _notifyDoctorOfPatientCancellation(String bookingId) async {
    try {
      await _supabase.functions.invoke(
        'send-consultation-activity-notification',
        body: {'event': 'patient_cancelled', 'booking_id': bookingId},
      );
    } catch (_) {
      // Cancellation remains successful if the notification cannot be sent.
    }
  }

  // -- helpers ---------------------------------------------------------

  Future<UserModel> _getAvailableDoctorOrThrow(String doctorId) async {
    final row = await _supabase
        .from('users')
        .select()
        .eq('uid', doctorId)
        .eq('role', 'doctor')
        .maybeSingle();

    if (row == null) {
      throw Exception('This doctor could not be found.');
    }

    final doctor = UserModel.fromMap(row);

    if (!doctor.isAvailable) {
      throw Exception('${doctor.name} is not available right now.');
    }

    if (doctor.consultationFee == null || doctor.consultationFee! <= 0) {
      throw Exception('This doctor has not set a consultation fee yet.');
    }

    return doctor;
  }

  Future<void> _assertNoDuplicateDoctorBooking({
    required String patientId,
    required String doctorId,
  }) async {
    final existing = await _supabase
        .from('bookings')
        .select('id')
        .eq('patient_id', patientId)
        .eq('doctor_id', doctorId)
        .inFilter('status', _activeStatuses)
        .maybeSingle();

    if (existing != null) {
      throw Exception('You already have an active booking with this doctor.');
    }
  }

  String _friendlyInsertError(PostgrestException e) {
    // Surfaces a unique-constraint violation (e.g. a DB-level guard against
    // duplicate active bookings) as a normal message instead of a raw
    // Postgres error code.
    if (e.code == '23505') {
      return 'You already have an active booking with this doctor.';
    }
    return e.message;
  }

  /// Every booking the signed-in patient has ever made, most recent first.
  /// Used by the appointments tab — unlike `getActiveBooking`, this isn't
  /// scoped to a single doctor or to active statuses.
  Future<List<BookingModel>> getPatientBookings() async {
    final patientId = _supabase.auth.currentUser?.id ??
        (await OfflineCacheService.instance.readLastUserId());
    if (patientId == null) {
      throw Exception('You must be signed in to view your appointments.');
    }
    if (await OfflineCacheService.instance.isDeviceOffline) {
      final cached = await OfflineCacheService.instance.readBookings(
        role: 'patient',
        userId: patientId,
      );
      if (cached != null) return cached;
    }

    try {
      final response = await _supabase
          .from('bookings')
          .select()
          .eq('patient_id', patientId)
          .order('created_at', ascending: false);

      final bookings = (response as List)
          .map((row) => BookingModel.fromMap(row as Map<String, dynamic>))
          .toList();
      await OfflineCacheService.instance.cacheBookings(
        role: 'patient',
        userId: patientId,
        bookings: bookings,
      );
      return bookings;
    } catch (error) {
      final cached = await OfflineCacheService.instance.readBookings(
        role: 'patient',
        userId: patientId,
      );
      if (cached != null) return cached;
      if (error is PostgrestException) throw Exception(error.message);
      throw Exception('Failed to fetch your appointments: $error');
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

  /// Batch-fetches doctor profiles for the given [doctorIds], keyed by uid.
  /// Bookings only store a doctor_id + a consultation-fee snapshot, not the
  /// doctor's name/photo/specialization, so the appointments list needs
  /// this to render anything beyond a bare booking row.
  Future<Map<String, UserModel>> getDoctorsByIds(List<String> doctorIds) async {
    if (doctorIds.isEmpty) return {};
    final ownerId = _supabase.auth.currentUser?.id ??
        (await OfflineCacheService.instance.readLastUserId()) ??
        'guest';
    if (await OfflineCacheService.instance.isDeviceOffline) {
      final cached = await OfflineCacheService.instance.readPeople(
        scope: 'patient_doctors',
        userId: ownerId,
      );
      if (cached != null) {
        return Map.fromEntries(
          cached.entries.where((entry) => doctorIds.contains(entry.key)),
        );
      }
    }

    try {
      final response = await _supabase
          .from('users')
          .select()
          .inFilter('uid', doctorIds);

      final doctors = (response as List)
          .map((row) => UserModel.fromMap(row as Map<String, dynamic>))
          .toList();

      await OfflineCacheService.instance.cachePeople(
        scope: 'patient_doctors',
        userId: ownerId,
        people: doctors,
      );
      return {for (final doctor in doctors) doctor.uid: doctor};
    } catch (error) {
      final cached = await OfflineCacheService.instance.readPeople(
        scope: 'patient_doctors',
        userId: ownerId,
      );
      if (cached != null) {
        return Map.fromEntries(
          cached.entries.where((entry) => doctorIds.contains(entry.key)),
        );
      }
      if (error is PostgrestException) throw Exception(error.message);
      throw Exception('Failed to load doctor details: $error');
    }
  }

  Future<UserModel> getPatientProfile() async {
    final authUser = _supabase.auth.currentUser;
    final patientId = authUser?.id ??
        (await OfflineCacheService.instance.readLastUserId());
    if (patientId == null) throw Exception('Please sign in to view your profile.');
    if (await OfflineCacheService.instance.isDeviceOffline) {
      final cached = await OfflineCacheService.instance.readUser(patientId);
      if (cached != null) return cached;
    }
    try {
      final row = await _supabase.from('users').select().eq('uid', patientId).single();
      final profile = Map<String, dynamic>.from(row);
      final storedPhone = profile['phone']?.toString().trim();
      if (storedPhone == null || storedPhone.isEmpty) {
        final authPhone = (authUser?.phone ??
                authUser?.userMetadata?['verified_phone']?.toString())
            ?.trim();
        if (authPhone?.isNotEmpty == true) {
          await _supabase.from('users').update({
            'phone': authPhone,
            'is_phone_verified': true,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('uid', patientId);
          profile['phone'] = authPhone;
          profile['is_phone_verified'] = true;
        }
      }
      final patient = UserModel.fromMap(profile);
      await OfflineCacheService.instance.cacheUser(patient);
      return patient;
    } catch (error) {
      final cached = await OfflineCacheService.instance.readUser(patientId);
      if (cached != null) return cached;
      if (error is PostgrestException) throw Exception(error.message);
      throw Exception('Failed to fetch your profile: $error');
    }
  }

  Future<void> updatePatientProfile({
    required String name,
    String? phone,
    String? gender,
    DateTime? dateOfBirth,
    File? profilePhoto,
  }) async {
    final patientId = _supabase.auth.currentUser?.id;
    if (patientId == null) throw Exception('Please sign in to update your profile.');
    final cleanName = name.trim();
    if (cleanName.length < 2) throw Exception('Please enter your full name.');
    try {
      String? profileImageUrl;
      if (profilePhoto != null) {
        final path = '$patientId/profile.jpg';
        await _supabase.storage.from('patient-avatars').upload(
          path,
          profilePhoto,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );
        final publicUrl =
            _supabase.storage.from('patient-avatars').getPublicUrl(path);
        profileImageUrl =
            '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
      }

      await _supabase.from('users').update({
        'name': cleanName,
        if (phone?.trim().isNotEmpty == true) 'phone': phone!.trim(),
        if (gender?.trim().isNotEmpty == true) 'gender': gender!.trim(),
        if (dateOfBirth != null)
          'date_of_birth': dateOfBirth.toUtc().toIso8601String(),
        'is_profile_completed': true,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        if (profileImageUrl != null) 'profile_image': profileImageUrl,
      }).eq('uid', patientId).select('uid').single();
    } on StorageException catch (error) {
      throw Exception(error.message);
    } on PostgrestException catch (error) {
      throw Exception(error.message);
    }
  }
}

class InsufficientWalletBalanceException implements Exception {
  const InsufficientWalletBalanceException({
    required this.requiredAmount,
    required this.availableBalance,
    required this.shortfall,
  });

  final double requiredAmount;
  final double availableBalance;
  final double shortfall;

  @override
  String toString() => 'Your wallet balance is insufficient for this consultation.';
}
