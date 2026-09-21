import 'dart:async';

import 'package:darmaan/core/models/video_call_invite.dart';
import 'package:darmaan/core/helpers/push_notification_service.dart';
import 'package:darmaan/presentation/home/video_call/video_call_invite_repository.dart';
import 'package:darmaan/presentation/home/video_call/video_call_screen.dart';
import 'package:darmaan/widgets/app_icon.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:darmaan/core/utils/app_error_message.dart';
import 'package:permission_handler/permission_handler.dart';

class IncomingVideoCallScreen extends StatefulWidget {
  const IncomingVideoCallScreen({
    super.key,
    required this.invite,
    this.initialNativeAction,
  });
  final VideoCallInvite invite;
  final NativeIncomingCallAction? initialNativeAction;
  @override
  State<IncomingVideoCallScreen> createState() =>
      _IncomingVideoCallScreenState();
}

class _IncomingVideoCallScreenState extends State<IncomingVideoCallScreen> {
  final _repository = VideoCallInviteRepository();
  StreamSubscription<VideoCallInvite>? _subscription;
  StreamSubscription<NativeIncomingCallEvent>? _nativeActionSubscription;
  Timer? _timeout;
  Timer? _watchRetryTimer;
  bool _busy = false;
  late bool _joiningFromNativeAccept;
  bool _signalReconnecting = false;
  CallParticipantProfile? _callerProfile;

  String get _callerName {
    final currentName = _callerProfile?.name?.trim();
    return currentName?.isNotEmpty == true
        ? currentName!
        : widget.invite.callerName;
  }

  @override
  void initState() {
    super.initState();
    _joiningFromNativeAccept =
        widget.initialNativeAction == NativeIncomingCallAction.accept;
    _loadCallerProfile();
    _subscribeToInvite();
    _nativeActionSubscription = PushNotificationService
        .instance
        .nativeIncomingCallActions
        .listen(_handleNativeCallAction);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final action = widget.initialNativeAction ??
          PushNotificationService.instance
              .takePendingNativeCallAction(widget.invite.id);
      if (action != null) {
        unawaited(_applyNativeCallAction(action));
      }
    });
    final remaining = widget.invite.expiresAt.difference(
      DateTime.now().toUtc(),
    );
    _timeout = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      if (mounted && !_busy) {
        unawaited(
          PushNotificationService.instance.cancelIncomingCall(
            widget.invite.id,
          ),
        );
        Navigator.pop(context);
      }
    });
  }

  void _handleNativeCallAction(NativeIncomingCallEvent event) {
    if (event.inviteId != widget.invite.id) return;
    PushNotificationService.instance.takePendingNativeCallAction(event.inviteId);
    unawaited(_applyNativeCallAction(event.action));
  }

  Future<void> _applyNativeCallAction(NativeIncomingCallAction action) async {
    if (!mounted || _busy) return;
    if (action == NativeIncomingCallAction.accept) {
      if (!_joiningFromNativeAccept) {
        setState(() => _joiningFromNativeAccept = true);
      }
      await _accept();
    } else {
      await _decline();
    }
  }

  void _subscribeToInvite() {
    if (!mounted || _busy) return;
    _watchRetryTimer?.cancel();
    _subscription?.cancel();
    _subscription = _repository.watchInvite(widget.invite.id).listen(
      (invite) {
        if (!mounted || _busy) return;
        if (_signalReconnecting) {
          setState(() => _signalReconnecting = false);
        }
        if (invite.status != VideoCallInviteStatus.ringing) {
          unawaited(
            PushNotificationService.instance.cancelIncomingCall(invite.id),
          );
          Navigator.pop(context);
        }
      },
      onError: (_) {
        if (!mounted || _busy) return;
        setState(() => _signalReconnecting = true);
        _watchRetryTimer = Timer(
          const Duration(seconds: 2),
          _subscribeToInvite,
        );
      },
    );
  }

  Future<void> _loadCallerProfile() async {
    try {
      final profile = await _repository.getParticipantProfile(
        widget.invite.callerId,
      );
      if (mounted) setState(() => _callerProfile = profile);
    } catch (_) {
      // The invite name remains a safe fallback if profile loading fails.
    }
  }

  Future<void> _decline() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _repository.respond(widget.invite.id, false);
      await PushNotificationService.instance.cancelIncomingCall(
        widget.invite.id,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppErrorMessage.from(e))));
      }
    }
  }

  @override
  void dispose() {
    unawaited(
      PushNotificationService.instance.cancelIncomingCall(widget.invite.id),
    );
    _subscription?.cancel();
    _nativeActionSubscription?.cancel();
    _timeout?.cancel();
    _watchRetryTimer?.cancel();
    super.dispose();
  }

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    final permissions = await [
      Permission.camera,
      Permission.microphone,
    ].request();
    if (permissions.values.any((s) => !s.isGranted)) {
      if (mounted) {
        setState(() {
          _busy = false;
          _joiningFromNativeAccept = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera and microphone permissions are required.'),
          ),
        );
      }
      return;
    }
    try {
      await _repository.respond(widget.invite.id, true);
      await PushNotificationService.instance.cancelIncomingCall(
        widget.invite.id,
      );
      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => VideoCallScreen(
            bookingId: widget.invite.bookingId,
            peerName: _callerName,
            isDoctor: widget.invite.calleeIsDoctor,
            peerAvatarUrl: _callerProfile?.photoUrl,
            peerSubtitle: _callerProfile?.subtitle.isNotEmpty == true
                ? _callerProfile!.subtitle
                : (widget.invite.callerIsDoctor ? 'Doctor' : 'Patient'),
            peerVerified: _callerProfile?.verified == true,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _joiningFromNativeAccept = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppErrorMessage.from(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && !_busy) _decline();
    },
    child: Scaffold(
      backgroundColor: const Color(0xFF0B141A),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF24343C), Color(0xFF0B141A)],
          ),
        ),
        child: SafeArea(
          child: SizedBox.expand(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
              const Text(
                'Darman video call',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const Spacer(),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 2),
                  ),
                  child: CircleAvatar(
                    radius: 58,
                    backgroundColor: const Color(0xFF35464F),
                    backgroundImage:
                        _callerProfile?.photoUrl?.trim().isNotEmpty == true
                            ? CachedNetworkImageProvider(
                                _callerProfile!.photoUrl!,
                              )
                            : null,
                    child: _callerProfile?.photoUrl?.trim().isNotEmpty == true
                        ? null
                        : const AppIcon(
                            Icons.person,
                            size: 62,
                            color: Colors.white70,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        _callerName,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 27,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (_callerProfile?.verified == true) ...[
                      const SizedBox(width: 6),
                      const AppIcon(
                        Icons.verified_rounded,
                        size: 21,
                        color: Color(0xFFBBDEFB),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: Text(
                  _signalReconnecting
                      ? 'Reconnecting incoming call…'
                      : _joiningFromNativeAccept
                      ? 'Joining video consultation…'
                      : 'Incoming video consultation',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ),
              const Spacer(),
              if (_joiningFromNativeAccept)
                const SizedBox(
                  height: 72,
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                    _CallAction(
                      color: Colors.red,
                      icon: Icons.call_end,
                      label: 'Decline',
                      onTap: _busy ? null : _decline,
                    ),
                    _CallAction(
                      color: Colors.green,
                      icon: Icons.videocam,
                      label: 'Accept',
                      onTap: _busy ? null : _accept,
                    ),
                    ],
                  ),
                ),
              const SizedBox(height: 36),
              ],
            ),
          ),
        ),
      ),
      ),
    ),
  );
}

class _CallAction extends StatelessWidget {
  const _CallAction({
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 96,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
      CircleAvatar(
        radius: 32,
        backgroundColor: color,
        child: IconButton(
          tooltip: label,
          onPressed: onTap,
          icon: AppIcon(icon, color: Colors.white, size: 30),
        ),
      ),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(color: Colors.white)),
      ],
    ),
  );
}
