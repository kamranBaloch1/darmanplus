import 'dart:async';

import 'package:darmaan/core/models/consultation_session_model.dart';
import 'package:darmaan/presentation/home/chat/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:darmaan/core/utils/app_error_message.dart';

/// Wrap the active patient appointment screen with this widget.
class PatientSessionStartListener extends StatefulWidget {
  const PatientSessionStartListener({super.key, required this.bookingId, required this.doctorName, required this.child});
  final String bookingId;
  final String doctorName;
  final Widget child;
  @override State<PatientSessionStartListener> createState() => _PatientSessionStartListenerState();
}

class _PatientSessionStartListenerState extends State<PatientSessionStartListener> {
  final ChatRepository _repository = ChatRepository();
  StreamSubscription<ConsultationSessionModel>? _subscription;
  bool _dialogVisible = false;

  @override void initState() { super.initState(); _listen(); }
  @override void didUpdateWidget(covariant PatientSessionStartListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookingId != widget.bookingId) _listen();
  }
  void _listen() {
    _subscription?.cancel();
    _subscription = _repository.watchSession(widget.bookingId).listen((session) {
      if (session.isRequestPending) _showRequest();
    });
  }
  Future<void> _showRequest() async {
    if (!mounted || _dialogVisible) return;
    _dialogVisible = true;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start consultation?'),
        content: Text('${widget.doctorName} is ready to begin your consultation. Once started, this appointment can no longer be cancelled.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Start session')),
        ],
      ),
    );
    _dialogVisible = false;
    if (accepted == null || !mounted) return;
    try {
      await _repository.respondToSessionStart(bookingId: widget.bookingId, accept: accepted);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppErrorMessage.from(error))),
      );
    }
  }
  @override void dispose() { _subscription?.cancel(); super.dispose(); }
  @override Widget build(BuildContext context) => widget.child;
}
