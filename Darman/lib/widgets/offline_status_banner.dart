import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:darmaan/widgets/app_icon.dart';

class OfflineStatusBanner extends StatefulWidget {
  const OfflineStatusBanner({super.key, required this.child});

  final Widget child;

  @override
  State<OfflineStatusBanner> createState() => _OfflineStatusBannerState();
}

class _OfflineStatusBannerState extends State<OfflineStatusBanner> {
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _restoredTimer;
  bool _offline = false;
  bool _showRestored = false;

  @override
  void initState() {
    super.initState();
    _check();
    _subscription = Connectivity().onConnectivityChanged.listen(_changed);
  }

  Future<void> _check() async {
    try {
      _changed(await Connectivity().checkConnectivity());
    } catch (_) {}
  }

  void _changed(List<ConnectivityResult> results) {
    final offline =
        results.isEmpty ||
        results.every((item) => item == ConnectivityResult.none);
    if (!mounted || offline == _offline) return;

    final restored = _offline && !offline;
    _restoredTimer?.cancel();
    setState(() {
      _offline = offline;
      _showRestored = restored;
    });

    if (restored) {
      _restoredTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _showRestored = false);
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _restoredTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    final bottom = keyboardHeight > 0
        ? keyboardHeight + 12
        : MediaQuery.paddingOf(context).bottom + 82;
    final visible = _offline || _showRestored;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned(
          left: 16,
          right: 16,
          bottom: bottom,
          child: IgnorePointer(
            ignoring: !visible,
            child: AnimatedSlide(
              offset: visible ? Offset.zero : const Offset(0, 1.4),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Semantics(
                  liveRegion: true,
                  label: _offline
                      ? 'You are offline. Showing saved data.'
                      : 'Back online. Updating data.',
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
                      decoration: BoxDecoration(
                        color: _offline
                            ? const Color(0xFF1D2939)
                            : const Color(0xFF067647),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 18,
                            offset: const Offset(0, 7),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.13),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: AppIcon(
                              _offline
                                  ? Icons.wifi_off_rounded
                                  : Icons.wifi_rounded,
                              color: Colors.white,
                              size: 17,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _offline ? 'You’re offline' : 'Back online',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    height: 1.1,
                                    fontWeight: FontWeight.w500,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _offline
                                      ? 'Showing your last saved data'
                                      : 'Updating with the latest data',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.76),
                                    fontSize: 11,
                                    height: 1.1,
                                    fontWeight: FontWeight.w400,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          AppIcon(
                            _offline
                                ? Icons.info_outline_rounded
                                : Icons.check_circle_outline_rounded,
                            color: Colors.white.withValues(alpha: 0.78),
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}