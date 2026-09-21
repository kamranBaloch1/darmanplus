import 'dart:async';
import 'package:darmaan/core/models/video_call_invite.dart';
import 'package:darmaan/presentation/home/video_call/video_call_invite_repository.dart';
import 'package:darmaan/presentation/home/video_call/video_call_screen.dart';
import 'package:darmaan/widgets/app_icon.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class OutgoingVideoCallScreen extends StatefulWidget {
  const OutgoingVideoCallScreen({
    super.key,
    required this.invite,
    required this.isDoctor,
    this.peerDisplayName,
    this.peerAvatarUrl,
    this.peerSubtitle = '',
    this.peerVerified = false,
  });
  final VideoCallInvite invite;
  final bool isDoctor;
  final String? peerDisplayName;
  final String? peerAvatarUrl;
  final String peerSubtitle;
  final bool peerVerified;
  @override
  State<OutgoingVideoCallScreen> createState() =>
      _OutgoingVideoCallScreenState();
}

class _OutgoingVideoCallScreenState extends State<OutgoingVideoCallScreen> {
  final _repository = VideoCallInviteRepository();
  StreamSubscription<VideoCallInvite>? _subscription;
  Timer? _timeout;
  Timer? _watchRetryTimer;
  bool _finished = false;
  bool _signalReconnecting = false;

  String get _peerName {
    final profileName = widget.peerDisplayName?.trim();
    return profileName?.isNotEmpty == true
        ? profileName!
        : widget.invite.calleeName;
  }
  @override
  void initState() {
    super.initState();
    _subscribeToInvite();
    final remaining = widget.invite.expiresAt.difference(
      DateTime.now().toUtc(),
    );
    _timeout = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      () => _cancel(timedOut: true),
    );
  }

  void _subscribeToInvite() {
    if (_finished || !mounted) return;
    _watchRetryTimer?.cancel();
    _subscription?.cancel();
    _subscription = _repository.watchInvite(widget.invite.id).listen(
      (invite) {
        if (mounted && _signalReconnecting) {
          setState(() => _signalReconnecting = false);
        }
        _changed(invite);
      },
      onError: (_) {
        if (_finished || !mounted) return;
        setState(() => _signalReconnecting = true);
        _watchRetryTimer = Timer(
          const Duration(seconds: 2),
          _subscribeToInvite,
        );
      },
    );
  }

  Future<void> _changed(VideoCallInvite invite) async {
    if (_finished || !mounted) return;
    if (invite.status == VideoCallInviteStatus.accepted) {
      _finished = true;
      _timeout?.cancel();
      _watchRetryTimer?.cancel();
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => VideoCallScreen(
            bookingId: invite.bookingId,
            peerName: _peerName,
            isDoctor: widget.isDoctor,
            peerAvatarUrl: widget.peerAvatarUrl,
            peerSubtitle: widget.peerSubtitle,
            peerVerified: widget.peerVerified,
          ),
        ),
      );
    } else if (invite.status != VideoCallInviteStatus.ringing) {
      _finished = true;
      _timeout?.cancel();
      _watchRetryTimer?.cancel();
      final message = switch (invite.status) {
        VideoCallInviteStatus.declined =>
          '$_peerName declined the call.',
        VideoCallInviteStatus.expired => 'No answer. The call timed out.',
        VideoCallInviteStatus.cancelled => 'The call was cancelled.',
        _ => 'The call ended before it connected.',
      };
      Navigator.pop(context, message);
    }
  }

  Future<void> _cancel({bool timedOut = false}) async {
    if (_finished) return;
    _finished = true;
    _timeout?.cancel();
    _watchRetryTimer?.cancel();
    _subscription?.cancel();
    unawaited(_repository.cancel(widget.invite.id).catchError((_) {}));
    if (mounted) {
      Navigator.pop(
        context,
        timedOut
            ? 'No answer. The call timed out.'
            : 'The call was cancelled.',
      );
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _timeout?.cancel();
    _watchRetryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
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
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
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
                  backgroundImage: widget.peerAvatarUrl?.trim().isNotEmpty == true
                      ? CachedNetworkImageProvider(widget.peerAvatarUrl!)
                      : null,
                  child: widget.peerAvatarUrl?.trim().isNotEmpty == true
                      ? null
                      : const AppIcon(Icons.person, size: 62, color: Colors.white70),
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
                      _peerName,
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
                  if (widget.peerVerified) ...[
                    const SizedBox(width: 6),
                    const AppIcon(
                      Icons.verified_rounded,
                      size: 21,
                      color: Color(0xFF64B5F6),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: Text(
                _signalReconnecting ? 'Reconnecting call…' : 'Calling…',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ),
            const Spacer(),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: const Color(0xFFE53935),
                    child: IconButton(
                      tooltip: 'Cancel call',
                      onPressed: _cancel,
                      icon: const AppIcon(
                        Icons.call_end,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Cancel', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
            const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
      ),
    ),
  );
}
