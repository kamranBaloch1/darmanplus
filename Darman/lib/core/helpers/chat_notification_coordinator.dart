import 'dart:async';

import 'package:darmaan/core/helpers/push_notification_service.dart';
import 'package:darmaan/core/models/booking_model.dart';
import 'package:darmaan/core/models/user_model.dart';
import 'package:darmaan/presentation/home/chat/chat_room.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatNotificationCoordinator extends StatefulWidget {
  const ChatNotificationCoordinator({super.key, required this.child});

  final Widget child;

  @override
  State<ChatNotificationCoordinator> createState() =>
      _ChatNotificationCoordinatorState();
}

class _ChatNotificationCoordinatorState
    extends State<ChatNotificationCoordinator> {
  StreamSubscription<Map<String, dynamic>>? _subscription;
  String? _openingBookingId;

  @override
  void initState() {
    super.initState();
    _subscription = PushNotificationService.instance.chatNotificationTaps.listen(
      _openFromData,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final data =
          PushNotificationService.instance.takePendingChatNotificationData();
      if (data != null) unawaited(_openFromData(data));
    });
  }

  Future<void> _openFromData(Map<String, dynamic> data) async {
    final bookingId = data['booking_id']?.toString().trim() ?? '';
    if (!mounted || bookingId.isEmpty || _openingBookingId == bookingId) return;

    PushNotificationService.instance.takePendingChatNotificationData();
    _openingBookingId = bookingId;
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null) return;

      final bookingRow = await Supabase.instance.client
          .from('bookings')
          .select()
          .eq('id', bookingId)
          .maybeSingle();
      if (!mounted || bookingRow == null) return;

      final booking = BookingModel.fromMap(bookingRow);
      final isDoctor = booking.doctorId == currentUserId;
      final peerId = isDoctor ? booking.patientId : booking.doctorId;

      final peerRow = await Supabase.instance.client
          .from('users')
          .select()
          .eq('uid', peerId)
          .maybeSingle();
      if (!mounted) return;

      final peer = peerRow == null ? null : UserModel.fromMap(peerRow);
      final subtitle = isDoctor
          ? 'Patient'
          : [peer?.specialization, peer?.title]
              .whereType<String>()
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .join(' | ');

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatRoomScreen(
            bookingId: booking.id,
            peerName: peer?.name ?? (isDoctor ? 'Patient' : 'Your doctor'),
            peerAvatarUrl: peer?.profileImage,
            peerSubtitle: subtitle.isEmpty
                ? (isDoctor ? 'Patient' : 'Doctor')
                : subtitle,
            peerVerified: !isDoctor && peer?.isDoctorVerified == true,
            openFromHistory:
                booking.status == BookingStatus.completed ||
                booking.status == BookingStatus.cancelled,
          ),
        ),
      );
    } catch (_) {
      // If routing fails, keep the app open on its current screen.
    } finally {
      if (_openingBookingId == bookingId) _openingBookingId = null;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
