import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Maintains an estimate of the Supabase clock for client-side UX decisions.
///
/// The database remains authoritative. Once synchronized, a monotonic
/// [Stopwatch] advances the server timestamp so changing the phone clock cannot
/// open or lock a follow-up inside the running app. The last known offset is
/// cached as an offline fallback and refreshed after sign-in or app resume.
class ServerClockService extends ChangeNotifier with WidgetsBindingObserver {
  ServerClockService._();

  static final ServerClockService instance = ServerClockService._();

  static const _offsetKey = 'darman.server_clock.offset_ms';
  static const _pakistanOffset = Duration(hours: 5);
  static const _resyncInterval = Duration(minutes: 15);

  StreamSubscription<AuthState>? _authSubscription;
  Timer? _midnightTimer;
  DateTime? _serverAnchorUtc;
  Stopwatch? _anchorElapsed;
  Duration _cachedOffset = Duration.zero;
  bool _hasEstimate = false;
  bool _initialized = false;
  bool _syncing = false;

  bool get hasServerEstimate => _hasEstimate;

  DateTime get nowUtc {
    final anchor = _serverAnchorUtc;
    final elapsed = _anchorElapsed;
    if (anchor != null && elapsed != null) {
      return anchor.add(elapsed.elapsed);
    }
    return DateTime.now().toUtc().add(_cachedOffset);
  }

  DateTime get pakistanToday {
    final pakistanNow = nowUtc.add(_pakistanOffset);
    return DateTime.utc(
      pakistanNow.year,
      pakistanNow.month,
      pakistanNow.day,
    );
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final preferences = await SharedPreferences.getInstance();
      final cachedMilliseconds = preferences.getInt(_offsetKey);
      if (cachedMilliseconds != null) {
        _cachedOffset = Duration(milliseconds: cachedMilliseconds);
        _hasEstimate = true;
      }
    } catch (_) {
      // A cache failure should never prevent the application from starting.
    }

    WidgetsBinding.instance.addObserver(this);
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (state) {
        if (state.session != null &&
            (state.event == AuthChangeEvent.signedIn ||
                state.event == AuthChangeEvent.initialSession)) {
          unawaited(synchronize(force: true));
        }
      },
    );
    _schedulePakistanMidnightRefresh();

    if (Supabase.instance.client.auth.currentUser != null) {
      // Let the splash screen render immediately; synchronization completes
      // before normal navigation in the common case and notifies the UI when
      // it arrives. Offline startup must never wait on a network timeout.
      unawaited(synchronize(force: true));
    }
  }

  Future<void> synchronize({bool force = false}) async {
    if (_syncing || Supabase.instance.client.auth.currentUser == null) return;
    final elapsed = _anchorElapsed;
    if (!force &&
        elapsed != null &&
        elapsed.elapsed < _resyncInterval) {
      return;
    }

    _syncing = true;
    try {
      final localBefore = DateTime.now().toUtc();
      final value = await Supabase.instance.client.rpc(
        'consultation_server_now',
      );
      final localAfter = DateTime.now().toUtc();
      final serverAtRequest = DateTime.tryParse(value.toString())?.toUtc();
      if (serverAtRequest == null) return;

      final roundTrip = localAfter.difference(localBefore);
      final estimatedServerAtResponse = serverAtRequest.add(
        Duration(microseconds: roundTrip.inMicroseconds ~/ 2),
      );
      _serverAnchorUtc = estimatedServerAtResponse;
      _anchorElapsed = Stopwatch()..start();
      _cachedOffset = estimatedServerAtResponse.difference(localAfter);
      _hasEstimate = true;

      try {
        final preferences = await SharedPreferences.getInstance();
        await preferences.setInt(_offsetKey, _cachedOffset.inMilliseconds);
      } catch (_) {
        // The live monotonic clock remains usable if persistence fails.
      }

      _schedulePakistanMidnightRefresh();
      notifyListeners();
    } catch (_) {
      // Offline mode uses the last known offset. Server-side RPCs still enforce
      // the real date when the user attempts a follow-up action.
    } finally {
      _syncing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    notifyListeners();
    _schedulePakistanMidnightRefresh();
    unawaited(synchronize());
  }

  void _schedulePakistanMidnightRefresh() {
    _midnightTimer?.cancel();
    final pakistanNow = nowUtc.add(_pakistanOffset);
    final nextMidnight = DateTime.utc(
      pakistanNow.year,
      pakistanNow.month,
      pakistanNow.day + 1,
    );
    final delay = nextMidnight.difference(pakistanNow);
    _midnightTimer = Timer(delay + const Duration(milliseconds: 100), () {
      notifyListeners();
      _schedulePakistanMidnightRefresh();
    });
  }
}
