import 'dart:async';

import 'package:darmaan/core/utils/app_error_message.dart';
import 'package:darmaan/presentation/home/chat/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FollowUpEndCoordinator extends StatefulWidget {
  const FollowUpEndCoordinator({super.key, required this.child});

  final Widget child;

  @override
  State<FollowUpEndCoordinator> createState() =>
      _FollowUpEndCoordinatorState();
}

class _FollowUpEndCoordinatorState extends State<FollowUpEndCoordinator> {
  final _repository = ChatRepository();
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  String? _showingBookingId;
  Map<String, dynamic>? _queuedBooking;

  @override
  void initState() {
    super.initState();
    _subscription = _repository.watchUnseenFollowUpEnds().listen(
      (bookings) {
        if (bookings.isNotEmpty) _show(bookings.first);
      },
      onError: (_, _) {},
    );
  }

  Future<void> _show(Map<String, dynamic> booking) async {
    if (!mounted) return;
    if (_showingBookingId != null) {
      _queuedBooking = booking;
      return;
    }

    final bookingId = booking['id']?.toString() ?? '';
    if (bookingId.isEmpty) return;
    _showingBookingId = bookingId;

    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      final isDoctor = booking['doctor_id']?.toString() == currentUserId;
      final peerName = await _repository.getFollowUpPeerName(booking);
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.50),
        builder: (dialogContext) => Dialog(
          elevation: 0,
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircleAvatar(
                  radius: 30,
                  backgroundColor: Color(0xFFEDFAF1),
                  child: Icon(
                    Icons.check_rounded,
                    color: Color(0xFF18A957),
                    size: 30,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Follow-up complete',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.35,
                    color: const Color(0xFF101828),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Your follow-up session with $peerName has ended. '
                  '${isDoctor ? 'The patient has been notified.' : 'The doctor has closed this follow-up.'}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    height: 1.5,
                    color: const Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F7F9),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Text(
                    'The follow-up chat is now closed.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: const Color(0xFF344054),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    style: FilledButton.styleFrom(
                      elevation: 0,
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      side: const BorderSide(color: Color(0xFFD0D5DD)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    child: Text(
                      'Done',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await _repository.acknowledgeConsultationFollowUpEnd(bookingId);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppErrorMessage.from(error))),
        );
      }
    } finally {
      _showingBookingId = null;
      final queued = _queuedBooking;
      _queuedBooking = null;
      if (queued != null && mounted) {
        unawaited(_show(queued));
      }
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
