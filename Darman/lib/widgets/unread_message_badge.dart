import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Realtime, appointment-scoped unread badge for a chat action.
class UnreadMessageBadge extends StatelessWidget {
  const UnreadMessageBadge({
    super.key,
    required this.bookingId,
    required this.isDoctor,
    required this.child,
  });

  final String bookingId;
  final bool isDoctor;
  final Widget child;

  Stream<int> _watchCount() => _UnreadRoomStream.rooms
      .map((rows) {
        final matches = rows.where(
          (row) => row['booking_id']?.toString() == bookingId,
        );
        if (matches.isEmpty) return 0;
        final field = isDoctor
            ? 'doctor_unread_count'
            : 'patient_unread_count';
        return ((matches.first[field] as num?)?.toInt() ?? 0)
            .clamp(0, 9999)
            .toInt();
      });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _watchCount(),
      initialData: 0,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return Semantics(
          label: count > 0
              ? '$count unread ${count == 1 ? 'message' : 'messages'}'
              : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              child,
              Positioned(
                top: -9,
                right: -12,
                child: AnimatedScale(
                  scale: count > 0 ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutBack,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5484D),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 9.5,
                        height: 1,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _UnreadRoomStream {
  static String? _userId;
  static Stream<List<Map<String, dynamic>>>? _rooms;

  static Stream<List<Map<String, dynamic>>> get rooms {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (_rooms == null || _userId != userId) {
      _userId = userId;
      _rooms = client
          .from('chat_rooms')
          .stream(primaryKey: ['id'])
          .asBroadcastStream(
            onListen: (subscription) => subscription.resume(),
            onCancel: (subscription) => subscription.pause(),
          );
    }
    return _rooms!;
  }
}
