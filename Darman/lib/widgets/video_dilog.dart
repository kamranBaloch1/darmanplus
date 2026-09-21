import 'dart:async';
import 'dart:io';

import 'package:darmaan/core/models/user_model.dart';
import 'package:darmaan/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:darmaan/widgets/app_icon.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

bool isDoctorIntroAudio(String url) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
  return const ['.mp3', '.m4a', '.aac', '.wav', '.ogg', '.flac', '.opus']
      .any(path.endsWith);
}

Future<File> _cachedIntroFile(String url) async {
  final cache = DefaultCacheManager();
  final existing = await cache.getFileFromCache(url);
  if (existing != null && await existing.file.exists()) return existing.file;
  return cache.getSingleFile(url);
}

Future<void> showDoctorIntroDialog(
  BuildContext context, {
  required String url,
  required String doctorName,
  UserModel? doctor,
  VoidCallback? onViewDetails,
}) {
  if (url.trim().isEmpty) return Future.value();
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.78),
    builder: (_) => isDoctorIntroAudio(url)
        ? _DoctorAudioDialog(
            url: url,
            doctorName: doctorName,
            doctor: doctor,
            onViewDetails: onViewDetails,
          )
        : DoctorVideoDialog.fromUrl(videoUrl: url),
  );
}

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

  return showDoctorIntroDialog(
    context,
    url: doctor.introVideoUrl!,
    doctorName: doctor.name,
    doctor: doctor,
    onViewDetails: onViewDetails,
  );
}

class _DoctorAudioDialog extends StatefulWidget {
  const _DoctorAudioDialog({
    required this.url,
    required this.doctorName,
    this.doctor,
    this.onViewDetails,
  });

  final String url;
  final String doctorName;
  final UserModel? doctor;
  final VoidCallback? onViewDetails;

  @override
  State<_DoctorAudioDialog> createState() => _DoctorAudioDialogState();
}

class _DoctorAudioDialogState extends State<_DoctorAudioDialog> {
  final AudioPlayer _player = AudioPlayer();
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final cachedFile = await _cachedIntroFile(widget.url);
      await _player.setFilePath(cachedFile.path);
      await _player.setLoopMode(LoopMode.off);
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _togglePlayback() async {
    if (_player.playing) {
      await _player.pause();
      return;
    }
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }
    await _player.play();
  }

  void _viewProfile() {
    Navigator.pop(context);
    widget.onViewDetails?.call();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        elevation: 0,
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      top: 14,
                      right: 30,
                      bottom: 8,
                      left: 4,
                    ),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onViewDetails == null ? null : _viewProfile,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipOval(
                        child: SizedBox(
                          width: 64,
                          height: 64,
                          child: widget.doctor?.profileImage != null
                              ? CachedNetworkImage(
                                  imageUrl: widget.doctor!.profileImage!,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, _, _) => const _AudioAvatarFallback(),
                                )
                              : const _AudioAvatarFallback(),
                        ),
                      ),
                      Positioned(
                        right: 2,
                        bottom: 3,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.doctorName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF101828),
                                ),
                              ),
                            ),
                            if (widget.doctor?.isDoctorVerified == true) ...[
                              const SizedBox(width: 6),
                              const AppIcon(
                                Icons.verified_rounded,
                                color: AppColors.brand,
                                size: 16,
                              ),
                            ],
                          ],
                        ),
                        Text(
                          widget.doctor?.specialization ?? 'Doctor',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            color: const Color(0xFF667085),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F8EF),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const AppIcon(
                                Icons.headphones_rounded,
                                color: Color(0xFF12B76A),
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Audio Introduction',
                                style: GoogleFonts.outfit(
                                  color: const Color(0xFF12B76A),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
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
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 30,
                        height: 30,
                      ),
                      icon: const AppIcon(
                        Icons.close_rounded,
                        size: 21,
                        color: Color(0xFF667085),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_loading)
                const SizedBox(
                  height: 120,
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.brand),
                  ),
                )
              else if (_error)
                SizedBox(
                  height: 120,
                  child: Center(
                    child: Text(
                      'Audio could not load',
                      style: GoogleFonts.outfit(color: Colors.redAccent),
                    ),
                  ),
                )
              else
                _DoctorAudioPlayer(
                  player: _player,
                  formatDuration: _formatDuration,
                  onToggle: _togglePlayback,
                ),
                 


             
            ],
          ),
        ),
      ),
    );
  }
}

class _AudioAvatarFallback extends StatelessWidget {
  const _AudioAvatarFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEAF2FF),
      alignment: Alignment.center,
      child: const AppIcon(
        Icons.person_rounded,
        color: AppColors.brand,
        size: 42,
      ),
    );
  }
}

class _DoctorAudioPlayer extends StatelessWidget {
  const _DoctorAudioPlayer({
    required this.player,
    required this.formatDuration,
    required this.onToggle,
  });

  final AudioPlayer player;
  final String Function(Duration value) formatDuration;
  final Future<void> Function() onToggle;

  static const _bars = <double>[
    7, 10, 15, 22, 31, 20, 36, 46, 28, 18, 12, 8, 14, 24, 38, 50,
    30, 18, 11, 8, 14, 24, 34, 27, 18, 12, 8,
  ];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: player.playerStateStream,
      builder: (context, stateSnapshot) {
        final state = stateSnapshot.data;
        final playing = state?.playing == true &&
            state?.processingState != ProcessingState.completed;
        return StreamBuilder<Duration>(
          stream: player.positionStream,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            final duration = player.duration ?? Duration.zero;
            final progress = duration.inMilliseconds > 0
                ? (position.inMilliseconds / duration.inMilliseconds)
                    .clamp(0.0, 1.0)
                : 0.0;
            final activeBars = (_bars.length * progress).round();

            return Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 9),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F6FF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Material(
                    color: AppColors.brand,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: onToggle,
                      customBorder: const CircleBorder(),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: AppIcon(
                            playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 42,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: List.generate(_bars.length, (index) {
                              return Expanded(
                                child: Center(
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 120),
                                    width: 3,
                                    height: (_bars[index] * .72)
                                        .clamp(4, 36)
                                        .toDouble(),
                                    decoration: BoxDecoration(
                                      color: index < activeBars
                                          ? AppColors.brand
                                          : const Color(0xFFA9CCFA),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              formatDuration(position),
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                color: const Color(0xFF667085),
                              ),
                            ),
                            Text(
                              formatDuration(duration),
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                color: const Color(0xFF667085),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Popup that plays a doctor's intro video using `video_player` directly,
/// with a hand-built control bar (play/pause, seek/scrub, elapsed/remaining
/// time, mute, fullscreen). No chewie dependency — requires only
/// `video_player` in pubspec.yaml.
class DoctorVideoDialog extends StatefulWidget {
  final UserModel? doctor;
  final String? videoUrl;

  /// Retained for source compatibility with existing call sites. The compact
  /// player deliberately keeps profile navigation outside the video frame.
  final VoidCallback? onViewDetails;

  const DoctorVideoDialog({
    super.key,
    required this.doctor,
    this.onViewDetails,
  }) : videoUrl = null;

  const DoctorVideoDialog.fromUrl({
    super.key,
    required this.videoUrl,
  })  : doctor = null,
        onViewDetails = null;

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
    final videoUri = Uri.tryParse(
      (widget.videoUrl ?? widget.doctor?.introVideoUrl)?.trim() ?? '',
    );
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
      final cachedFile = await _cachedIntroFile(videoUri.toString());
      if (!mounted || attempt != _loadAttempt) return;
      candidate = VideoPlayerController.file(cachedFile);
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
