import 'dart:async';

import 'package:darmaan/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UnreadMessageBadge extends StatefulWidget {
  const UnreadMessageBadge({
    super.key,
    required this.bookingId,
    required this.isDoctor,
    required this.child,
    this.initialCount = 0,
  });

  final String bookingId;
  final bool isDoctor;
  final Widget child;
  final int initialCount;

  @override
  State<UnreadMessageBadge> createState() => _UnreadMessageBadgeState();
}

class _UnreadMessageBadgeState extends State<UnreadMessageBadge> {
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  int _count = 0;

  String get _field =>
      widget.isDoctor ? 'doctor_unread_count' : 'patient_unread_count';

  @override
  void initState() {
    super.initState();
    _count = widget.initialCount.clamp(0, 9999).toInt();
    _loadNow();
    _watch();
  }

  @override
  void didUpdateWidget(covariant UnreadMessageBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookingId != widget.bookingId ||
        oldWidget.isDoctor != widget.isDoctor) {
      _count = widget.initialCount.clamp(0, 9999).toInt();
      _subscription?.cancel();
      _loadNow();
      _watch();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _loadNow() async {
    try {
      final row = await Supabase.instance.client
          .from('chat_rooms')
          .select('$_field')
          .eq('booking_id', widget.bookingId)
          .maybeSingle();
      if (!mounted || row == null) return;
      _setCount(row[_field]);
    } catch (_) {}
  }

  void _watch() {
    _subscription = Supabase.instance.client
        .from('chat_rooms')
        .stream(primaryKey: ['id'])
        .eq('booking_id', widget.bookingId)
        .listen((rows) {
      if (!mounted || rows.isEmpty) return;
      _setCount(rows.first[_field]);
    });
  }

  void _setCount(dynamic value) {
    final next = ((value as num?)?.toInt() ?? 0).clamp(0, 9999).toInt();
    if (next == _count) return;
    setState(() => _count = next);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _count > 0;
    return Semantics(
      label: visible
          ? '$_count unread ${_count == 1 ? 'message' : 'messages'}'
          : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          Positioned(
            top: -10,
            right: -12,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, animation) {
                return ScaleTransition(
                  scale: CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutBack,
                  ),
                  child: child,
                );
              },
              child: visible
                  ? Container(
                      key: ValueKey(_count > 99 ? '99+' : _count),
                      constraints: const BoxConstraints(
                        minWidth: 20,
                        minHeight: 20,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE03137),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.textPrimary.withValues(alpha: .16),
                            blurRadius: 9,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Text(
                        _count > 99 ? '99+' : '$_count',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 9.5,
                          height: 1,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('empty')),
            ),
          ),
        ],
      ),
    );
  }
}
