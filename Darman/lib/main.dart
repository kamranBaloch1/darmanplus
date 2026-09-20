import 'package:darmaan/presentation/auth/screens/login/splash_screen.dart';
import 'package:darmaan/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_in_app_messaging/firebase_in_app_messaging.dart';
import 'package:darmaan/core/helpers/push_notification_service.dart';
import 'package:darmaan/widgets/offline_status_banner.dart';
import 'package:darmaan/core/services/secure_supabase_local_storage.dart';
import 'package:darmaan/core/services/server_clock_service.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Restore authentication and Firebase concurrently to keep cold-start call
  // acceptance as short as possible.
  await Future.wait<Object?>([
    Supabase.initialize(
      url: 'https://bnwvwlkiwgbtmvltzenp.supabase.co',
      publishableKey: 'sb_publishable_1Xfj4nBTsS8dkoLrlIZbTA_5h7eJEOQ',
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        localStorage: SecureSupabaseLocalStorage(
          persistSessionKey: 'sb-bnwvwlkiwgbtmvltzenp-auth-token',
        ),
      ),
    ),
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
  ]);

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
  };
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await Future.wait([
    FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true),
    FirebaseInAppMessaging.instance.setAutomaticDataCollectionEnabled(true),
    FirebaseInAppMessaging.instance.setMessagesSuppressed(false),
    PushNotificationService.instance.initialize(),
    ServerClockService.instance.initialize(),
  ]);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ServerClockService.instance,
      builder: (_, __) => ScreenUtilInit(
        designSize: const Size(375, 812),
        minTextAdapt: true,
        splitScreenMode: true,
        ensureScreenSize: true,
        fontSizeResolver: FontSizeResolvers.radius,
        builder: (_, __) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'darman',
          theme: AppTheme.light(),
          builder: (context, child) {
            if (child == null) return const SizedBox.shrink();
            return OfflineStatusBanner(
              child: MediaQuery.withClampedTextScaling(
                minScaleFactor: .9,
                maxScaleFactor: 1.2,
                child: child,
              ),
            );
          },
          home: const SplashScreen(),
        ),
      ),
    );
  }
}
