import 'dart:async';
import 'package:darmaan/core/helpers/push_notification_service.dart';
import 'package:darmaan/core/models/video_call_invite.dart';
import 'package:darmaan/presentation/home/video_call/incoming_video_call_screen.dart';
import 'package:darmaan/presentation/home/video_call/video_call_invite_repository.dart';
import 'package:flutter/material.dart';

class IncomingCallCoordinator extends StatefulWidget {
  const IncomingCallCoordinator({super.key, required this.child});
  final Widget child;
  @override
  State<IncomingCallCoordinator> createState() =>
      _IncomingCallCoordinatorState();
}

class _IncomingCallCoordinatorState extends State<IncomingCallCoordinator> {
  final _repository = VideoCallInviteRepository();
  StreamSubscription<List<VideoCallInvite>>? _subscription;
  StreamSubscription<NativeIncomingCallEvent>? _nativeActionSubscription;
  Timer? _retryTimer;
  Timer? _pendingOpenRetryTimer;
  int _retryAttempt = 0;
  int _pendingOpenRetryAttempt = 0;
  Map<String, dynamic>? _pendingCallData;
  String? _showingId;
  bool _permissionPromptShown = false;

  @override
  void initState() {
    super.initState();
    _subscribe();
    _nativeActionSubscription = PushNotificationService
        .instance
        .nativeIncomingCallActions
        .listen((event) {
          if (event.action == NativeIncomingCallAction.accept) {
            unawaited(_openPendingNotificationCall());
          }
        });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_openPendingNotificationCall());
      unawaited(_explainFullScreenPermissionIfNeeded());
    });
  }

  Future<void> _openPendingNotificationCall() async {
    final data = _pendingCallData ??
        PushNotificationService.instance.takePendingIncomingCallData();
    final inviteId = data?['invite_id']?.toString().trim() ?? '';
    if (!mounted || inviteId.isEmpty || _showingId != null) return;
    _pendingCallData = Map<String, dynamic>.from(data!);
    try {
      final invite = await _repository.getIncomingInvite(inviteId);
      if (invite != null && mounted) {
        _pendingCallData = null;
        _pendingOpenRetryAttempt = 0;
        _pendingOpenRetryTimer?.cancel();
        await _incoming([invite]);
        return;
      }
      _schedulePendingOpenRetry();
    } catch (_) {
      _schedulePendingOpenRetry();
    }
  }

  void _schedulePendingOpenRetry() {
    if (!mounted ||
        _pendingCallData == null ||
        _pendingOpenRetryTimer?.isActive == true ||
        _pendingOpenRetryAttempt >= 8) {
      return;
    }
    _pendingOpenRetryAttempt++;
    final delay = Duration(
      milliseconds: _pendingOpenRetryAttempt <= 3 ? 350 : 750,
    );
    _pendingOpenRetryTimer = Timer(delay, _openPendingNotificationCall);
  }

  Future<void> _explainFullScreenPermissionIfNeeded() async {
    if (!mounted ||
        _permissionPromptShown ||
        PushNotificationService.instance.hasPendingAcceptedIncomingCall ||
        PushNotificationService.instance.fullScreenCallPermissionGranted !=
            false) {
      return;
    }
    _permissionPromptShown = true;
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enable incoming call screen'),
        content: const Text(
          'Allow Darman to show incoming calls over the lock screen. '
          'Without this access, calls can ring but Android will show only a notification.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
    if (openSettings != true || !mounted) return;
    final granted = await PushNotificationService.instance
        .requestFullScreenCallPermission();
    if (!granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Turn on “Allow full-screen notifications” for incoming calls.',
          ),
        ),
      );
    }
  }

  void _subscribe() {
    _retryTimer?.cancel();
    _subscription?.cancel();
    _subscription = _repository.watchIncoming().listen(
      (invites) {
        _retryAttempt = 0;
        _incoming(invites);
      },
      onError: (Object error, StackTrace stackTrace) {
        _scheduleRetry();
      },
      cancelOnError: true,
    );
  }

  void _scheduleRetry() {
    if (!mounted || _retryTimer?.isActive == true) return;
    _retryAttempt = (_retryAttempt + 1).clamp(1, 5);
    final seconds = 1 << _retryAttempt;
    _retryTimer = Timer(Duration(seconds: seconds), () {
      if (mounted) _subscribe();
    });
  }

  Future<void> _incoming(List<VideoCallInvite> invites) async {
    if (!mounted || _showingId != null || invites.isEmpty) return;
    final invite = invites.first;
    if (_pendingCallData?['invite_id']?.toString() == invite.id) {
      _pendingCallData = null;
      _pendingOpenRetryTimer?.cancel();
      _pendingOpenRetryAttempt = 0;
    }
    _showingId = invite.id;
    final initialNativeAction = PushNotificationService.instance
        .takePendingNativeCallAction(invite.id);
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => IncomingVideoCallScreen(
          invite: invite,
          initialNativeAction: initialNativeAction,
        ),
      ),
    );
    _showingId = null;
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _pendingOpenRetryTimer?.cancel();
    _subscription?.cancel();
    _nativeActionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
