import 'dart:async';

import 'package:darmaan/core/models/consultation_completion_model.dart';
import 'package:darmaan/presentation/home/chat/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:darmaan/core/utils/app_error_message.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class PatientCompletionCoordinator extends StatefulWidget {
  const PatientCompletionCoordinator({super.key, required this.child});
  final Widget child;

  @override
  State<PatientCompletionCoordinator> createState() =>
      _PatientCompletionCoordinatorState();
}

class _PatientCompletionCoordinatorState
    extends State<PatientCompletionCoordinator> {
  final _repository = ChatRepository();
  StreamSubscription<List<String>>? _subscription;
  StreamSubscription<List<Map<String, dynamic>>>? _followUpSubscription;
  Timer? _retryTimer;
  int _retryAttempt = 0;
  String? _showingBookingId;
  String? _queuedCompletionBookingId;
  Map<String, dynamic>? _queuedFollowUp;

  @override
  void initState() {
    super.initState();
    _subscribe();
    _subscribeToFollowUps();
  }

  void _subscribe() {
    _retryTimer?.cancel();
    _subscription?.cancel();
    _subscription = _repository.watchUnseenPatientCompletions().listen(
      (bookingIds) {
        _retryAttempt = 0;
        if (bookingIds.isNotEmpty) _show(bookingIds.first);
      },
      onError: (_, _) => _scheduleRetry(),
      cancelOnError: true,
    );
  }

  void _subscribeToFollowUps() {
    _followUpSubscription?.cancel();
    _followUpSubscription = _repository.watchUnseenPatientFollowUps().listen(
      (bookings) {
        if (bookings.isNotEmpty) _showFollowUp(bookings.first);
      },
      onError: (_, _) {},
    );
  }

  void _scheduleRetry() {
    if (!mounted || _retryTimer?.isActive == true) return;
    _retryAttempt = (_retryAttempt + 1).clamp(1, 5);
    _retryTimer = Timer(Duration(seconds: 1 << _retryAttempt), _subscribe);
  }

  Future<void> _show(String bookingId) async {
    if (!mounted) return;
    if (_showingBookingId != null) {
      _queuedCompletionBookingId = bookingId;
      return;
    }
    _showingBookingId = bookingId;
    try {
      final receipt = await _repository.getConsultationCompletion(bookingId);
      if (!mounted || !receipt.shouldShow || receipt.isDoctor) return;
      await _showReceipt(receipt);
      if (!mounted) return;
      if (!receipt.alreadyRated) await _showRating(receipt);
      await _repository.acknowledgeConsultationCompletion(bookingId);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_message(error))),
        );
      }
    } finally {
      _showingBookingId = null;
      final queuedCompletion = _queuedCompletionBookingId;
      _queuedCompletionBookingId = null;
      if (queuedCompletion != null && mounted) {
        unawaited(_show(queuedCompletion));
        return;
      }
      final queued = _queuedFollowUp;
      _queuedFollowUp = null;
      if (queued != null && mounted) {
        unawaited(_showFollowUp(queued));
      }
    }
  }

  Future<void> _showFollowUp(Map<String, dynamic> booking) async {
    if (!mounted) return;
    if (_showingBookingId != null) {
      _queuedFollowUp = booking;
      return;
    }

    final bookingId = booking['id']?.toString() ?? '';
    final rawDate = booking['follow_up_date']?.toString() ?? '';
    final followUpDate = DateTime.tryParse(rawDate);
    if (bookingId.isEmpty || followUpDate == null) return;

    _showingBookingId = bookingId;
    try {
      final doctorName = await _repository.getBookingDoctorName(booking);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.50),
        builder: (dialogContext) => _AppDialog(
          icon: Icons.event_repeat_rounded,
          iconBackgroundColor: const Color(0xFFEAF3FF),
          iconColor: const Color(0xFF1570EF),
          title: 'Follow-up scheduled',
          body: Column(
            children: [
              Text(
                '$doctorName scheduled your follow-up for '
                '${DateFormat('d MMMM yyyy').format(followUpDate)}.',
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
                child: Row(
                  children: [
                    const Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 18,
                      color: Color(0xFF1570EF),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Chat will open on this date at no additional charge.',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          height: 1.4,
                          color: const Color(0xFF344054),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          primaryLabel: 'Got it',
          onPrimary: () => Navigator.pop(dialogContext),
        ),
      );
      await _repository.acknowledgeConsultationFollowUp(bookingId);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_message(error))),
        );
      }
    } finally {
      _showingBookingId = null;
      final queuedCompletion = _queuedCompletionBookingId;
      _queuedCompletionBookingId = null;
      if (queuedCompletion != null && mounted) {
        unawaited(_show(queuedCompletion));
        return;
      }
      final queuedFollowUp = _queuedFollowUp;
      _queuedFollowUp = null;
      if (queuedFollowUp != null && mounted) {
        unawaited(_showFollowUp(queuedFollowUp));
      }
    }
  }

  // ---------------------------------------------------------------------
  // Receipt dialog
  // ---------------------------------------------------------------------

  Future<void> _showReceipt(ConsultationCompletionModel receipt) {
    final money = NumberFormat('#,##0');
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.50),
      builder: (dialogContext) => _AppDialog(
        icon: Icons.check_rounded,
        iconBackgroundColor: const Color(0xFFEDFAF1),
        iconColor: const Color(0xFF18A957),
        title: 'Consultation complete',
        body: Column(
          children: [
            Text(
              'Your session with Dr. ${receipt.doctorName} has ended.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 13,
                height: 1.5,
                color: const Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F8FA),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Text(
                    'Amount paid',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Rs. ${money.format(receipt.grossFee)}',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF101828),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        primaryLabel: 'Continue',
        onPrimary: () => Navigator.pop(dialogContext),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Rating dialog
  // ---------------------------------------------------------------------

  Future<void> _showRating(ConsultationCompletionModel receipt) async {
    var rating = 0;
    var submitting = false;
    final reviewController = TextEditingController();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.50),
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
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
                CircleAvatar(
                  radius: 30,
                  backgroundColor: const Color(0xFFFFF7E0),
                  child: const Icon(
                    Icons.star_rounded,
                    color: Color(0xFFF5A623),
                    size: 30,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Rate Dr. ${receipt.doctorName}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.35,
                    color: const Color(0xFF101828),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your feedback helps other patients choose care.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    height: 1.5,
                    color: const Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    final value = index + 1;
                    final filled = value <= rating;
                    return GestureDetector(
                      onTap: submitting
                          ? null
                          : () => setDialogState(() => rating = value),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Icon(
                          filled
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: filled
                              ? const Color(0xFFF5A623)
                              : const Color(0xFFD0D5DD),
                          size: 36,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: reviewController,
                  enabled: !submitting,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: Colors.black,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Add a comment (optional)',
                    hintStyle: GoogleFonts.outfit(
                      fontSize: 13,
                      color: const Color(0xFF98A2B3),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF7F8FA),
                    counterStyle: GoogleFonts.outfit(
                      fontSize: 11,
                      color: const Color(0xFF98A2B3),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: rating == 0 || submitting
                        ? null
                        : () async {
                            setDialogState(() => submitting = true);
                            try {
                              await _repository.submitConsultationRating(
                                bookingId: receipt.bookingId,
                                rating: rating,
                                review: reviewController.text,
                              );
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }
                            } catch (error) {
                              setDialogState(() => submitting = false);
                              if (dialogContext.mounted) {
                                ScaffoldMessenger.of(
                                  dialogContext,
                                ).showSnackBar(
                                  SnackBar(content: Text(_message(error))),
                                );
                              }
                            }
                          },
                    style: FilledButton.styleFrom(
                      elevation: 0,
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: const Color(0xFFF2F4F7),
                      disabledForegroundColor: const Color(0xFF98A2B3),
                      side: const BorderSide(color: Color(0xFFD0D5DD)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    child: submitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : Text(
                            'Submit rating',
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
      ),
    );
    reviewController.dispose();
  }

  String _message(Object error) => AppErrorMessage.from(error);

  @override
  void dispose() {
    _retryTimer?.cancel();
    _subscription?.cancel();
    _followUpSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Shared dialog shell — matches the styling used elsewhere in the app
/// (icon badge, bold title, single primary action) instead of the default
/// [AlertDialog] chrome.
class _AppDialog extends StatelessWidget {
  const _AppDialog({
    required this.icon,
    required this.iconBackgroundColor,
    required this.iconColor,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
  });

  final IconData icon;
  final Color iconBackgroundColor;
  final Color iconColor;
  final String title;
  final Widget body;
  final String primaryLabel;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    return Dialog(
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
            CircleAvatar(
              radius: 30,
              backgroundColor: iconBackgroundColor,
              child: Icon(icon, color: iconColor, size: 30),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.35,
                color: const Color(0xFF101828),
              ),
            ),
            const SizedBox(height: 10),
            body,
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: onPrimary,
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
                  primaryLabel,
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
    );
  }
}
