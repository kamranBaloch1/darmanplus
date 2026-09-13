import 'dart:async';

import 'package:darmaan/core/theme/app_colors.dart';
import 'package:darmaan/presentation/home/chat/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:darmaan/widgets/app_icon.dart';
import 'package:darmaan/core/utils/app_error_message.dart';
import 'package:google_fonts/google_fonts.dart';

class PatientSessionStartCoordinator extends StatefulWidget {
  const PatientSessionStartCoordinator({super.key, required this.child});

  final Widget child;

  @override
  State<PatientSessionStartCoordinator> createState() =>
      _PatientSessionStartCoordinatorState();
}

class _PatientSessionStartCoordinatorState
    extends State<PatientSessionStartCoordinator> {
  final ChatRepository _repository = ChatRepository();
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  Timer? _retryTimer;
  int _retryAttempt = 0;
  String? _showingBookingId;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    _retryTimer?.cancel();
    _subscription?.cancel();
    _subscription = _repository.watchPendingPatientSessionStarts().listen(
      (requests) {
        _retryAttempt = 0;
        if (requests.isNotEmpty) _show(requests.first);
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

  Future<void> _show(Map<String, dynamic> request) async {
    final bookingId = request['id']?.toString();
    if (!mounted || bookingId == null || _showingBookingId != null) return;
    _showingBookingId = bookingId;

    try {
      final doctorName = await _repository.getBookingDoctorName(request);
      if (!mounted) return;

      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: .52),
        builder: (dialogContext) => Dialog(
          elevation: 0,
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: .1),
                    shape: BoxShape.circle,
                  ),
                  child: const AppIcon(
                    Icons.video_call_rounded,
                    size: 32,
                    color: AppColors.brand,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Start consultation?',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF17202C),
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  '$doctorName is ready to begin your consultation. Once started, this appointment can no longer be cancelled.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 13.5,
                    height: 1.5,
                    color: const Color(0xFF697381),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    icon: const AppIcon(Icons.play_arrow_rounded, size: 20),
                    label: const Text('Start consultation'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  height: 43,
                  child: TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Not now',style: TextStyle(color: Colors.black87),),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      if (accepted == null || !mounted) return;
      await _repository.respondToSessionStart(
        bookingId: bookingId,
        accept: accepted,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppErrorMessage.from(error)),
          ),
        );
      }
    } finally {
      _showingBookingId = null;
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