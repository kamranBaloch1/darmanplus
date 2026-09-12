import 'dart:async';

import 'package:darmaan/core/models/user_model.dart';
import 'package:darmaan/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';

/// Convenience helper so callers don't need to construct the dialog
/// themselves. Does nothing if the doctor has no intro video.
///
/// Pass [onViewDetails] to show a "View Details" button under the video that
/// closes the dialog and forwards to your details navigation. Callers that
/// don't pass it (other places this dialog is used) get the plain video
/// dialog with no button, unchanged.
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
    barrierColor: Colors.black87,
    builder: (_) => DoctorVideoDialog(
      doctor: doctor,
      onViewDetails: onViewDetails,
    ),
  );
}

/// Popup that plays a doctor's intro video using `video_player` directly,
/// with a hand-built control bar (play/pause, seek/scrub, elapsed/remaining
/// time, mute, fullscreen). No chewie dependency — requires only
/// `video_player` in pubspec.yaml.
class DoctorVideoDialog extends StatefulWidget {
  final UserModel doctor;

  /// When provided, a "View Details" button is shown below the video.
  /// Tapping it closes the dialog and invokes this callback. Leave null to
  /// keep this dialog exactly as it is used elsewhere in the app.
  final VoidCallback? onViewDetails;

  const DoctorVideoDialog({super.key, required this.doctor, this.onViewDetails});

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
      candidate = VideoPlayerController.networkUrl(
        videoUri,
      );
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
    if (!mounted || controller == null || !controller.value.hasError || _hasError) {
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

  void _handleViewDetails() {
    final onViewDetails = widget.onViewDetails;
    Navigator.of(context).pop();
    if (onViewDetails != null) onViewDetails();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final maxDialogWidth = screenSize.width < 480 ? screenSize.width * 0.9 : 420.0;
    final maxDialogHeight = screenSize.height * 0.6;
    final showViewDetailsButton = widget.onViewDetails != null;

    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxDialogWidth),
          // Fixed total height so the video area can never push the button
          // (or itself) past the bottom of the dialog, regardless of the
          // video's own aspect ratio (portrait clips included).
          child: SizedBox(
            height: maxDialogHeight,
            child: Column(
              children: [
                Expanded(
                  child: _hasError
                      ? _VideoErrorState(onRetry: _retry)
                      : (_isLoading || _controller == null
                          ? const _VideoLoadingState()
                          // Center + AspectRatio here (inside a bounded
                          // Expanded box) letterboxes the video to fit both
                          // the available width and height instead of
                          // forcing height purely from width.
                          : Center(
                              child: AspectRatio(
                                aspectRatio: _controller!.value.aspectRatio,
                                child: _VideoPlayerWithControls(
                                  controller: _controller!,
                                  title: widget.doctor.name,
                                  onClose: () => Navigator.of(context).pop(),
                                ),
                              ),
                            )),
                ),
                if (showViewDetailsButton)
                  Container(
                    width: double.infinity,
                    color: Colors.black,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                    child: Center(
                      child: SizedBox(
                        height: 38,
                        child: FilledButton.icon(
                          onPressed: _handleViewDetails,
                          icon: const Icon(Icons.arrow_forward_rounded, size: 15),
                          label: Text(
                            'View Details',
                            style: GoogleFonts.outfit(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.brand,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            shape: const StadiumBorder(),
                          ),
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
  }
}

/// Custom control surface layered on top of a raw `VideoPlayer`. Handles
/// play/pause, a draggable seek bar, elapsed/remaining time, mute, a
/// fullscreen route, and auto-hiding the control bar during playback.
class _VideoPlayerWithControls extends StatefulWidget {
  final VideoPlayerController controller;
  final String title;
  final VoidCallback onClose;
  final bool isFullscreen;

  const _VideoPlayerWithControls({
    required this.controller,
    required this.title,
    required this.onClose,
    this.isFullscreen = false,
  });

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
    _hideTimer = Timer(const Duration(seconds: 3), () {
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

  void _openFullscreen() {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, __, ___) => _FullscreenVideoPage(
          controller: _controller,
          title: widget.title,
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return d.inHours > 0 ? '${d.inHours}:$minutes:$seconds' : '$minutes:$seconds';
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


          // Dim overlay + controls, only when visible.
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
                      Colors.black.withValues(alpha: 0.45),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.55),
                    ],
                    stops: const [0, 0.25, 0.6, 1],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Top bar: title + close.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (!widget.isFullscreen)
                            _IconCircleButton(
                              icon: Icons.close_rounded,
                              onTap: widget.onClose,
                            )
                          else
                            _IconCircleButton(
                              icon: Icons.fullscreen_exit_rounded,
                              onTap: () => Navigator.of(context).pop(),
                            ),
                        ],
                      ),
                    ),

                    // Center play/pause.
                    _IconCircleButton(
                      icon: value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 30,
                      padding: 14,
                      background: Colors.black45,
                      onTap: _togglePlayPause,
                    ),

                    // Bottom bar: seek + time + mute + fullscreen.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 14, 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 2.5,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 14,
                              ),
                              activeTrackColor: AppColors.brand,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: AppColors.brand,
                              overlayColor: AppColors.brand.withValues(alpha: 0.2),
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
                          Row(
                            children: [
                              Text(
                                _formatDuration(position),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                              const Text(
                                ' / ',
                                style: TextStyle(color: Colors.white54, fontSize: 11),
                              ),
                              Text(
                                _formatDuration(duration),
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                              const Spacer(),
                              InkWell(
                                onTap: _toggleMute,
                                child: Icon(
                                  value.volume == 0
                                      ? Icons.volume_off_rounded
                                      : Icons.volume_up_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 14),
                              InkWell(
                                onTap: widget.isFullscreen
                                    ? () => Navigator.of(context).pop()
                                    : _openFullscreen,
                                child: Icon(
                                  widget.isFullscreen
                                      ? Icons.fullscreen_exit_rounded
                                      : Icons.fullscreen_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ],
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
          child: Icon(icon, color: Colors.white, size: size),
        ),
      ),
    );
  }
}

/// Landscape, edge-to-edge fullscreen route reusing the same controller —
/// playback position and state carry over seamlessly.
class _FullscreenVideoPage extends StatefulWidget {
  final VideoPlayerController controller;
  final String title;

  const _FullscreenVideoPage({required this.controller, required this.title});

  @override
  State<_FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<_FullscreenVideoPage> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (_, __) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: AspectRatio(
            aspectRatio: widget.controller.value.aspectRatio,
            child: _VideoPlayerWithControls(
              controller: widget.controller,
              title: widget.title,
              isFullscreen: true,
              onClose: () => Navigator.of(context).pop(),
            ),
          ),
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
          const Icon(Icons.error_outline_rounded, color: Colors.white70, size: 28),
          const SizedBox(height: 8),
          Text(
            'Video could not load',
            style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: Text('Try again', style: GoogleFonts.outfit()),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }
}