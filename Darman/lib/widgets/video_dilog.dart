import 'dart:async';

import 'package:darmaan/core/models/user_model.dart';
import 'package:darmaan/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:darmaan/widgets/app_icon.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';

/// Convenience helper so callers don't need to construct the dialog
/// themselves. Does nothing if the doctor has no intro video.
///
/// [onViewDetails] remains in the public signature for existing callers, but
/// the compact player intentionally contains no secondary profile action.
Future<void> showDoctorVideoDialog(
  BuildContext context,
  UserModel doctor, {
  VoidCallback? onViewDetails,
}) {
  if (doctor.introVideoUrl == null || doctor.introVideoUrl!.trim().isEmpty) {
    return Future.value();
  }

  return showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.78),
    builder: (_) =>
        DoctorVideoDialog(doctor: doctor, onViewDetails: onViewDetails),
  );
}

/// Popup that plays a doctor's intro video using `video_player` directly,
/// with a hand-built control bar (play/pause, seek/scrub, elapsed/remaining
/// time, mute, fullscreen). No chewie dependency — requires only
/// `video_player` in pubspec.yaml.
class DoctorVideoDialog extends StatefulWidget {
  final UserModel doctor;

  /// Retained for source compatibility with existing call sites. The compact
  /// player deliberately keeps profile navigation outside the video frame.
  final VoidCallback? onViewDetails;

  const DoctorVideoDialog({
    super.key,
    required this.doctor,
    this.onViewDetails,
  });

  @override
  State<DoctorVideoDialog> createState() => _DoctorVideoDialogState();
}

class _DoctorVideoDialogState extends State<DoctorVideoDialog> {
  VideoPlayerController? _controller;
  bool _isLoading = true;
  bool _hasError = false;
  int _loadAttempt = 0;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    final attempt = ++_loadAttempt;
    final videoUri = Uri.tryParse(widget.doctor.introVideoUrl?.trim() ?? '');
    if (videoUri == null || !videoUri.hasScheme) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
      return;
    }

    VideoPlayerController? candidate;
    try {
      candidate = VideoPlayerController.networkUrl(videoUri);
      await candidate.initialize().timeout(const Duration(seconds: 25));
      await candidate.setLooping(false);
      await candidate.play();

      if (!mounted || attempt != _loadAttempt) {
        await candidate.dispose();
        return;
      }

      candidate.addListener(_onPlayerStateChanged);
      setState(() {
        _controller = candidate;
        _isLoading = false;
        _hasError = false;
      });
      candidate = null;
    } catch (_) {
      await candidate?.dispose();
      if (!mounted || attempt != _loadAttempt) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  void _onPlayerStateChanged() {
    final controller = _controller;
    if (!mounted ||
        controller == null ||
        !controller.value.hasError ||
        _hasError) {
      return;
    }
    setState(() => _hasError = true);
  }

  Future<void> _retry() async {
    if (_isLoading) return;
    final previous = _controller;
    if (mounted) {
      setState(() {
        _controller = null;
        _hasError = false;
        _isLoading = true;
      });
    }
    if (previous != null) {
      previous.removeListener(_onPlayerStateChanged);
      await previous.dispose();
    }
    await _initializePlayer();
  }

  @override
  void dispose() {
    _loadAttempt++;
    _controller?.removeListener(_onPlayerStateChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final availableWidth = screenSize.width * 0.78;
    final maxDialogWidth = availableWidth > 340 ? 340.0 : availableWidth;
    final maxDialogHeight = screenSize.height * 0.56;
    final videoAspectRatio =
        _controller?.value.isInitialized == true &&
            (_controller?.value.aspectRatio ?? 0) > 0
        ? _controller!.value.aspectRatio
        : 9 / 16;

    var dialogWidth = maxDialogWidth;
    var dialogHeight = dialogWidth / videoAspectRatio;
    if (dialogHeight > maxDialogHeight) {
      dialogHeight = maxDialogHeight;
      dialogWidth = dialogHeight * videoAspectRatio;
    }

    return PopScope(
      canPop: false,
      child: Dialog(
        elevation: 0,
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 64),
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: dialogWidth,
        height: dialogHeight,
        decoration: BoxDecoration(
          color: const Color(0xFF090B0F),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x52000000),
              blurRadius: 32,
              offset: Offset(0, 18),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(31),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_hasError)
                _VideoErrorState(onRetry: _retry)
              else if (_isLoading || _controller == null)
                const _VideoLoadingState()
              else
                _VideoPlayerWithControls(controller: _controller!),
              Positioned(
                top: 12,
                right: 12,
                child: _IconCircleButton(
                  icon: Icons.close_rounded,
                  size: 20,
                  padding: 9,
                  background: Colors.black.withValues(alpha: 0.42),
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

/// Custom control surface layered on top of a raw `VideoPlayer`. Handles
/// play/pause, a draggable seek bar, mute, and auto-hiding controls.
class _VideoPlayerWithControls extends StatefulWidget {
  final VideoPlayerController controller;

  const _VideoPlayerWithControls({required this.controller});

  @override
  State<_VideoPlayerWithControls> createState() =>
      _VideoPlayerWithControlsState();
}

class _VideoPlayerWithControlsState extends State<_VideoPlayerWithControls> {
  bool _showControls = true;
  bool _isDragging = false;
  double _dragValue = 0;
  Timer? _hideTimer;

  VideoPlayerController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerUpdate);
    _resetHideTimer();
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 2400), () {
      if (mounted && _controller.value.isPlaying && !_isDragging) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _resetHideTimer();
  }

  void _togglePlayPause() {
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
      _resetHideTimer();
    }
    setState(() {});
  }

  void _toggleMute() {
    _controller.setVolume(_controller.value.volume == 0 ? 1 : 0);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.value;
    final duration = value.duration;
    final position = _isDragging
        ? Duration(milliseconds: _dragValue.round())
        : value.position;
    final maxMs = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;
    final currentMs = position.inMilliseconds
        .clamp(0, duration.inMilliseconds)
        .toDouble();

    return GestureDetector(
      onTap: _toggleControls,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        alignment: Alignment.center,
        fit: StackFit.expand,
        children: [
          VideoPlayer(_controller),

          // Buffering indicator — soft dark backdrop, brand-colored spinner,
          // fades in/out instead of popping so brief stalls don't flicker.
          // Wrapped in Align so StackFit.expand doesn't stretch the circular
          // decoration to fill the whole video frame.
          Align(
            alignment: Alignment.center,
            child: AnimatedOpacity(
              opacity: value.isBuffering ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: AppColors.brand,
                      strokeWidth: 2.5,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // A light-touch overlay keeps the video itself as the focus.
          AnimatedOpacity(
            opacity: _showControls ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_showControls,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.18),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.42),
                    ],
                    stops: const [0, 0.22, 0.62, 1],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Center(
                        child: _IconCircleButton(
                          icon: value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 28,
                          padding: 13,
                          background: Colors.black.withValues(alpha: 0.34),
                          onTap: _togglePlayPause,
                        ),
                      ),
                    ),

                    // Minimal bottom controls: progress and sound only.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 12, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 2,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 5,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 12,
                              ),
                              activeTrackColor: AppColors.brand,
                              inactiveTrackColor: Colors.white30,
                              thumbColor: AppColors.brand,
                              overlayColor: AppColors.brand.withValues(
                                alpha: 0.2,
                              ),
                            ),
                            child: Slider(
                              min: 0,
                              max: maxMs,
                              value: currentMs.clamp(0, maxMs),
                              onChangeStart: (_) {
                                _isDragging = true;
                                _hideTimer?.cancel();
                              },
                              onChanged: (v) => setState(() => _dragValue = v),
                              onChangeEnd: (v) {
                                _controller.seekTo(
                                  Duration(milliseconds: v.round()),
                                );
                                _isDragging = false;
                                _resetHideTimer();
                              },
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: _IconCircleButton(
                              icon: value.volume == 0
                                  ? Icons.volume_off_rounded
                                  : Icons.volume_up_rounded,
                              onTap: _toggleMute,
                              size: 17,
                              padding: 8,
                              background: Colors.black.withValues(alpha: 0.28),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final double padding;
  final Color background;

  const _IconCircleButton({
    required this.icon,
    required this.onTap,
    this.size = 18,
    this.padding = 8,
    this.background = Colors.black45,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: AppIcon(icon, color: Colors.white, size: size),
        ),
      ),
    );
  }
}

class _VideoLoadingState extends StatelessWidget {
  const _VideoLoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Preparing video',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoErrorState extends StatelessWidget {
  const _VideoErrorState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppIcon(
            Icons.error_outline_rounded,
            color: Colors.white70,
            size: 28,
          ),
          const SizedBox(height: 8),
          Text(
            'Video could not load',
            style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const AppIcon(Icons.refresh_rounded, size: 17),
            label: Text('Try again', style: GoogleFonts.outfit()),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }
}
