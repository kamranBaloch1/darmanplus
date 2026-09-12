import 'dart:convert';

import 'package:darmaan/core/models/booking_model.dart';
import 'package:darmaan/core/models/user_model.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Small encrypted, stale-while-revalidate cache for essential offline data.
/// Supabase remains authoritative; cached values are only used when a network
/// request fails. Never store OTPs, payment credentials, documents, or tokens
/// here.
class OfflineCacheService {
  OfflineCacheService._();

  static final OfflineCacheService instance = OfflineCacheService._();

  static const _prefix = 'darman.offline.v1.';
  static const _lastUserIdKey = '${_prefix}last_user_id';
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );

  String _profileKey(String userId) => '${_prefix}profile.$userId';
  String _bookingsKey(String role, String userId) =>
      '${_prefix}bookings.$role.$userId';
  String _peopleKey(String scope, String userId) =>
      '${_prefix}people.$scope.$userId';
  String _doctorsKey(String? specialization) {
    final normalized = specialization?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return '${_prefix}public_doctors.all';
    }
    final safe = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return '${_prefix}public_doctors.$safe';
  }

  Future<void> _write(String key, Object data) async {
    try {
      final value = jsonEncode({
        'saved_at': DateTime.now().toUtc().toIso8601String(),
        'data': data,
      });
      await _storage.write(key: key, value: value);
    } catch (_) {
      // A cache write must never turn a successful server request into an
      // application error.
    }
  }

  Future<dynamic> _read(String key) async {
    try {
      final value = await _storage.read(key: key);
      if (value == null || value.isEmpty) return null;
      final decoded = jsonDecode(value);
      return decoded is Map ? decoded['data'] : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> cacheUser(UserModel user) async {
    try {
      await Future.wait([
        _write(_profileKey(user.uid), user.toMap()),
        _storage.write(key: _lastUserIdKey, value: user.uid),
      ]);
    } catch (_) {}
  }

  Future<UserModel?> readUser([String? userId]) async {
    try {
      final id = userId ?? await _storage.read(key: _lastUserIdKey);
      if (id == null || id.isEmpty) return null;
      final data = await _read(_profileKey(id));
      if (data is! Map) return null;
      return UserModel.fromMap(Map<String, dynamic>.from(data));
    } catch (_) {
      return null;
    }
  }

  Future<String?> readLastUserId() async {
    try {
      return await _storage.read(key: _lastUserIdKey);
    } catch (_) {
      return null;
    }
  }

  Future<bool> get isDeviceOffline async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.isEmpty ||
          results.every((result) => result == ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  Future<void> cachePublicDoctors(
    List<UserModel> doctors, {
    String? specialization,
  }) => _write(
    _doctorsKey(specialization),
    doctors.map((doctor) => doctor.toMap()).toList(),
  );

  Future<List<UserModel>?> readPublicDoctors({String? specialization}) async {
    var data = await _read(_doctorsKey(specialization));
    if (data is! List && specialization?.trim().isNotEmpty == true) {
      data = await _read(_doctorsKey(null));
    }
    if (data is! List) return null;
    final doctors = data
        .whereType<Map>()
        .map((row) => UserModel.fromMap(Map<String, dynamic>.from(row)))
        .toList();
    final requested = specialization?.trim().toLowerCase();
    if (requested == null || requested.isEmpty) return doctors;
    return doctors
        .where(
          (doctor) => doctor.specialization?.trim().toLowerCase() == requested,
        )
        .toList();
  }

  Future<void> cacheBookings({
    required String role,
    required String userId,
    required List<BookingModel> bookings,
  }) => _write(
    _bookingsKey(role, userId),
    bookings.map((booking) => booking.toMap()).toList(),
  );

  Future<List<BookingModel>?> readBookings({
    required String role,
    required String userId,
  }) async {
    final data = await _read(_bookingsKey(role, userId));
    if (data is! List) return null;
    return data
        .whereType<Map>()
        .map((row) => BookingModel.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<void> cachePeople({
    required String scope,
    required String userId,
    required Iterable<UserModel> people,
  }) => _write(
    _peopleKey(scope, userId),
    people.map((person) => person.toMap()).toList(),
  );

  Future<Map<String, UserModel>?> readPeople({
    required String scope,
    required String userId,
  }) async {
    final data = await _read(_peopleKey(scope, userId));
    if (data is! List) return null;
    final people = data
        .whereType<Map>()
        .map((row) => UserModel.fromMap(Map<String, dynamic>.from(row)));
    return {for (final person in people) person.uid: person};
  }

  Future<void> clear() async {
    final values = await _storage.readAll();
    await Future.wait(
      values.keys
          .where((key) => key.startsWith(_prefix))
          .map((key) => _storage.delete(key: key)),
    );
  }
}
