import 'dart:async';

import 'package:darmaan/core/helpers/push_notification_service.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps the operating-system notification bar synchronized with the user's
/// active consultation, regardless of which Darmaan screen is currently open.
class ConsultationProgressCoordinator extends StatefulWidget {
  const ConsultationProgressCoordinator({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<ConsultationProgressCoordinator> createState() =>
      _ConsultationProgressCoordinatorState();
}

class _ConsultationProgressCoordinatorState
    extends State<ConsultationProgressCoordinator> {
  final SupabaseClient _client = Supabase.instance.client;
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  Timer? _retryTimer;
  int _retryAttempt = 0;
  String? _shownBookingId;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    _retryTimer?.cancel();
    _subscription?.cancel();
    _subscription = _client
        .from('bookings')
        .stream(primaryKey: ['id'])
        .listen(
      (rows) {
        _retryAttempt = 0;
        final active = rows
            .where(
              (row) =>
                  row['status'] == 'inProgress' &&
                  (row['patient_id']?.toString() == userId ||
                      row['doctor_id']?.toString() == userId),
            )
            .toList()
          ..sort(
            (a, b) => (b['started_at']?.toString() ?? '')
                .compareTo(a['started_at']?.toString() ?? ''),
          );
        _sync(active.isEmpty ? null : active.first, userId);
      },
      onError: (_, __) => _scheduleRetry(),
      cancelOnError: true,
    );
  }

  Future<void> _sync(Map<String, dynamic>? booking, String userId) async {
    if (booking == null) {
      _shownBookingId = null;
      await PushNotificationService.instance
          .cancelConsultationInProgress();
      return;
    }

    final bookingId = booking['id']?.toString() ?? '';
    if (bookingId.isEmpty || bookingId == _shownBookingId) return;

    final isDoctor = booking['doctor_id']?.toString() == userId;
    final peerId = isDoctor
        ? booking['patient_id']?.toString()
        : booking['doctor_id']?.toString();
    var peerName = isDoctor ? 'your patient' : 'your doctor';

    if (peerId != null && peerId.isNotEmpty) {
      try {
        final profile = await _client
            .from('users')
            .select('name')
            .eq('uid', peerId)
            .maybeSingle();
        final name = profile?['name']?.toString().trim();
        if (name != null && name.isNotEmpty) peerName = name;
      } catch (_) {}
    }

    if (!mounted) return;
    final startedAt = DateTime.tryParse(
      booking['started_at']?.toString() ?? '',
    )?.toLocal();
    await PushNotificationService.instance.showConsultationInProgress(
      bookingId: bookingId,
      peerName: peerName,
      isDoctor: isDoctor,
      startedAt: startedAt,
    );
    _shownBookingId = bookingId;
  }

  void _scheduleRetry() {
    if (!mounted || _retryTimer?.isActive == true) return;
    _retryAttempt = (_retryAttempt + 1).clamp(1, 5);
    _retryTimer = Timer(Duration(seconds: 1 << _retryAttempt), _subscribe);
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
