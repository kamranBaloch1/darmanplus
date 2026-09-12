import 'package:darmaan/core/constants/images.dart';
import 'package:darmaan/core/helpers/push_notification_service.dart';
import 'package:darmaan/core/theme/app_colors.dart';
import 'package:darmaan/core/utils/auth_navigator.dart';
import 'package:darmaan/core/services/offline_cache_service.dart';
import 'package:darmaan/presentation/home/patient/screens/patient_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _scale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    _controller.forward();
    _decideNextScreen();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _decideNextScreen() async {
    // Small delay so the splash is actually visible instead of flashing
    if (!PushNotificationService.instance.hasPendingAcceptedIncomingCall) {
      await Future.delayed(const Duration(milliseconds: 1200));
    }

    if (!mounted) return;

    final auth = Supabase.instance.client.auth;
    var session = auth.currentSession;
    final cachedUser = session == null
        ? await OfflineCacheService.instance.readUser()
        : null;

    // On a cold app start, persisted authentication can take a moment to be
    // restored. Do not classify the user as a guest during that window.
    if (session == null && cachedUser == null) {
      try {
        await auth.onAuthStateChange.first.timeout(
          const Duration(seconds: 3),
        );
      } catch (_) {
        // A genuinely signed-out user may not produce another auth event.
      }
      session = auth.currentSession;
    }

    // A verified phone session may reopen with an expired access token while
    // its refresh token is still valid. Refresh it before routing.
    if (session?.isExpired == true) {
      try {
        final response = await auth.refreshSession();
        session = response.session;
      } catch (_) {
        // Keep the last locally-restored identity when the device is offline.
        // Repositories will serve encrypted cached data until Supabase can
        // refresh the session after connectivity returns.
      }
    }

    if (!mounted) return;

    if (session == null) {
      if (cachedUser != null && mounted) {
        await AuthNavigator.goToCorrectScreen(context);
        return;
      }
      // Guests can browse doctors and are asked to log in only when they
      // access a protected feature.
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PatientHomeScreen()),
      );
      return;
    }

    // Returning user -> figure out patient / doctor / pending / home
    await AuthNavigator.goToCorrectScreen(context);
  }

  @override
  Widget build(BuildContext context) {
    if (PushNotificationService.instance.hasPendingAcceptedIncomingCall) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B141A),
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF24343C), Color(0xFF0B141A)],
            ),
          ),
          child: SizedBox.expand(
            child: SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.videocam_rounded, color: Colors.white, size: 42),
                    SizedBox(height: 22),
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 20),
                    Text(
                      'Joining video consultation…',
                      style: TextStyle(color: Colors.white, fontSize: 17),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
        return Scaffold(
      backgroundColor: AppColors.brand,
      body: Stack(
        children: [
          Center(
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Image.asset(
                  splash_icon,
                  width: 150,
                  height: 150,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: FadeTransition(
              opacity: _fade,
              child: const Center(
                child: Text(
                  'From FindUs',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  
  }
}
