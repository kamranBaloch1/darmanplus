import 'dart:async';

import 'package:darmaan/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DoctorRatingCoordinator extends StatefulWidget {
  const DoctorRatingCoordinator({super.key, required this.child});

  final Widget child;

  @override
  State<DoctorRatingCoordinator> createState() =>
      _DoctorRatingCoordinatorState();
}

class _DoctorRatingCoordinatorState extends State<DoctorRatingCoordinator> {
  final SupabaseClient _client = Supabase.instance.client;
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  Timer? _retryTimer;
  bool _showing = false;
  int _retryAttempt = 0;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    final doctorId = _client.auth.currentUser?.id;
    if (doctorId == null) return;
    _retryTimer?.cancel();
    _subscription?.cancel();
    _subscription = _client
        .from('consultation_ratings')
        .stream(primaryKey: ['id'])
        .eq('doctor_id', doctorId)
        .map((rows) {
          final unseen = rows
              .where((row) => row['doctor_seen_at'] == null)
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
            ..sort(
              (a, b) => (a['created_at']?.toString() ?? '')
                  .compareTo(b['created_at']?.toString() ?? ''),
            );
          return unseen;
        })
        .listen(
          (ratings) {
            _retryAttempt = 0;
            if (ratings.isNotEmpty && !_showing) _show(ratings.first);
          },
          onError: (_, _) => _scheduleRetry(),
          cancelOnError: true,
        );
  }

  void _scheduleRetry() {
    if (!mounted || _retryTimer?.isActive == true) return;
    _retryAttempt = (_retryAttempt + 1).clamp(1, 5);
    _retryTimer = Timer(Duration(seconds: 1 << _retryAttempt), _subscribe);
  }

  Future<void> _show(Map<String, dynamic> rating) async {
    final ratingId = rating['id']?.toString();
    final patientId = rating['patient_id']?.toString();
    final stars = (rating['rating'] as num?)?.toInt() ?? 0;
    final review = rating['review']?.toString().trim();
    if (!mounted || ratingId == null || patientId == null) return;
    _showing = true;

    String patientName = 'A patient';
    try {
      final patient = await _client
          .from('users')
          .select('name')
          .eq('uid', patientId)
          .maybeSingle();
      final name = patient?['name']?.toString().trim();
      if (name?.isNotEmpty == true) patientName = name!;
    } catch (_) {}

    if (!mounted) {
      _showing = false;
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: .52),
      builder: (dialogContext) => Dialog(
        elevation: 0,
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 21),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E7),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFFE8A3)),
                ),
                child: const Icon(
                  Icons.star_rounded,
                  size: 34,
                  color: Color(0xFFFFB400),
                ),
              ),
              const SizedBox(height: 17),
              Text(
                'New patient rating',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                '$patientName rated your consultation',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  5,
                  (index) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(
                      index < stars
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      size: 31,
                      color: const Color(0xFFFFB400),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                '$stars out of 5',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
              if (review?.isNotEmpty == true) ...[
                const SizedBox(height: 17),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F8FA),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '“$review”',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 12.5,
                      height: 1.45,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 21),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  style: FilledButton.styleFrom(
                    elevation: 0,
                    backgroundColor: const Color(0xFFF2F4F6),
                    foregroundColor: AppColors.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: Text(
                    'Done',
                    style: GoogleFonts.outfit(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    var acknowledged = false;
    try {
      await _client.rpc(
        'acknowledge_doctor_rating',
        params: {'p_rating_id': ratingId},
      );
      acknowledged = true;
    } catch (_) {
      // Keep it unseen so it can be shown again on a later app session.
    } finally {
      _showing = false;
      if (acknowledged && mounted) {
        Timer.run(_subscribe);
      }
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
