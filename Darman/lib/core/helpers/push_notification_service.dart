import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:darmaan/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum NativeIncomingCallAction { accept, decline }

class NativeIncomingCallEvent {
  const NativeIncomingCallEvent({
    required this.inviteId,
    required this.action,
  });

  final String inviteId;
  final NativeIncomingCallAction action;
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await PushNotificationService.handleBackgroundMessage(message);
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _openedAppSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<CallEvent?>? _callKitSubscription;
  final StreamController<NativeIncomingCallEvent> _callKitActions =
      StreamController<NativeIncomingCallEvent>.broadcast();
  final Map<String, NativeIncomingCallAction> _pendingCallKitActions = {};
  RemoteMessage? _launchMessage;
  Map<String, dynamic>? _foregroundTapData;
  final Map<String, int> _openChatBookings = {};
  bool? _fullScreenCallPermissionGranted;

  static const int _activeConsultationNotificationId = 47201;
  static const MethodChannel _nativeIncomingCallBridge = MethodChannel(
    'com.user.darman/incoming_call',
  );
  // Android notification-channel sounds are immutable after the channel is
  // first created. Keep this versioned whenever the call sound changes.
  static const String _incomingCallChannelId = 'incoming_calls_v3';
  static const String _consultationChannelId = 'consultation_requests_v2';
  static const String _chatChannelId = 'chat_messages_v2';
  static const AndroidNotificationSound _customNotificationSound =
      RawResourceAndroidNotificationSound('darman_notification');
  static const AndroidNotificationSound _systemRingtone =
      UriAndroidNotificationSound('content://settings/system/ringtone');

  static const AndroidNotificationChannel _incomingCallChannel =
      AndroidNotificationChannel(
        _incomingCallChannelId,
        'Incoming video calls',
        description: 'Incoming Darman video consultation calls',
        importance: Importance.max,
        playSound: true,
        sound: _systemRingtone,
        enableVibration: true,
        showBadge: false,
        audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
      );

  static int _callNotificationId(String inviteId) {
    var hash = 0x811c9dc5;
    for (final codeUnit in inviteId.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  static Future<void> _initializeBackgroundNotifications(
    FlutterLocalNotificationsPlugin notifications,
  ) async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await notifications.initialize(settings: settings);
    final android = notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_incomingCallChannel);
  }

  static Future<void> _showIncomingCallNotification(
    FlutterLocalNotificationsPlugin notifications,
    Map<String, dynamic> data, {
    String? title,
    String? body,
    bool launchFullScreen = true,
  }) async {
    final inviteId = data['invite_id']?.toString().trim() ?? '';
    if (inviteId.isEmpty) return;
    final callerName = data['caller_name']?.toString().trim();
    final displayName = callerName?.isNotEmpty == true
        ? callerName!
        : 'Darman user';
    await notifications.show(
      id: _callNotificationId(inviteId),
      title: title?.trim().isNotEmpty == true
          ? title
          : 'Video call from $displayName',
      body: body?.trim().isNotEmpty == true
          ? body
          : '$displayName is calling you',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _incomingCallChannelId,
          'Incoming video calls',
          channelDescription: 'Incoming Darman video consultation calls',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: launchFullScreen,
          playSound: true,
          sound: _systemRingtone,
          enableVibration: true,
          ongoing: true,
          autoCancel: false,
          visibility: NotificationVisibility.public,
          audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
          additionalFlags: Int32List.fromList(<int>[4]),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
      payload: jsonEncode(data),
    );
  }

  static CallKitParams _callKitParams(Map<String, dynamic> data) {
    final inviteId = data['invite_id']?.toString().trim() ?? '';
    final callerName = data['caller_name']?.toString().trim();
    final displayName = callerName?.isNotEmpty == true
        ? callerName!
        : 'Darman user';
    final callerVerified =
        data['caller_verified']?.toString().toLowerCase() == 'true';
    final callerSubtitle = data['caller_subtitle']?.toString().trim() ?? '';
    return CallKitParams(
      id: inviteId,
      nameCaller: displayName,
      appName: 'Darman',
      avatar: data['caller_avatar']?.toString().trim(),
      handle: callerSubtitle.isNotEmpty
          ? callerSubtitle
          : 'Incoming video consultation',
      type: 1,
      duration: 60000,
      extra: Map<String, dynamic>.from(data),
      missedCallNotification: const NotificationParams(
        showNotification: false,
        isShowCallback: false,
      ),
      android: AndroidParams(
        isCustomNotification: true,
        isShowLogo: callerVerified,
        isShowCallID: true,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0B141A',
        actionColor: '#25D366',
        textColor: '#FFFFFF',
        incomingCallNotificationChannelName: 'Incoming video calls',
        missedCallNotificationChannelName: 'Missed video calls',
        isShowFullLockedScreen: true,
        isFullScreen: true,
        textAccept: 'Accept',
        textDecline: 'Decline',
      ),
    );
  }

  @pragma('vm:entry-point')
  static Future<void> handleBackgroundMessage(RemoteMessage message) async {
    final type = message.data['type']?.toString() ?? '';
    if (type == 'incoming_video_call') {
      if (Platform.isAndroid) {
        final inviteId = message.data['invite_id']?.toString().trim() ?? '';
        if (inviteId.isNotEmpty) {
          // The native full-screen activity is intentionally separate from
          // its ringtone. With isFullScreen enabled the callkit activity does
          // not start its notification sound, so keep one silent-launch local
          // call notification responsible for the looping system ringtone.
          final notifications = FlutterLocalNotificationsPlugin();
          await _initializeBackgroundNotifications(notifications);
          await _showIncomingCallNotification(
            notifications,
            message.data,
            title: message.data['title']?.toString(),
            body: message.data['body']?.toString(),
            launchFullScreen: false,
          );
          await FlutterCallkitIncoming.showCallkitIncoming(
            _callKitParams(message.data),
          );
          return;
        }
      }
      final notifications = FlutterLocalNotificationsPlugin();
      await _initializeBackgroundNotifications(notifications);
      await _showIncomingCallNotification(
        notifications,
        message.data,
        title: message.data['title']?.toString(),
        body: message.data['body']?.toString(),
      );
      return;
    }
    if (type == 'incoming_video_call_ended') {
      final inviteId = message.data['invite_id']?.toString() ?? '';
      if (inviteId.isNotEmpty) {
        if (Platform.isAndroid) {
          try {
            await FlutterCallkitIncoming.endCall(inviteId);
          } catch (_) {}
        }
        final notifications = FlutterLocalNotificationsPlugin();
        await _initializeBackgroundNotifications(notifications);
        await notifications.cancel(id: _callNotificationId(inviteId));
      }
      return;
    }
    if (type != 'session_start_accepted' &&
        type != 'consultation_completed' &&
        type != 'patient_cancelled_appointment') {
      return;
    }

    final notifications = FlutterLocalNotificationsPlugin();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await notifications.initialize(settings: settings);

    if (type == 'consultation_completed' ||
        type == 'patient_cancelled_appointment') {
      await notifications.cancel(id: _activeConsultationNotificationId);
      return;
    }

    const channel = AndroidNotificationChannel(
      'active_consultation',
      'Active consultation',
      description: 'Shows when a Darmaan consultation is currently in progress',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
      showBadge: false,
    );
    final android = notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(channel);

    final patientName = message.data['patient_name']?.toString().trim();
    await notifications.show(
      id: _activeConsultationNotificationId,
      title: 'Consultation in progress',
      body: 'Your consultation with ${patientName?.isNotEmpty == true ? patientName : 'your patient'} is active.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'active_consultation',
          'Active consultation',
          channelDescription:
              'Shows when a Darmaan consultation is currently in progress',
          importance: Importance.low,
          priority: Priority.low,
          playSound: false,
          enableVibration: false,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          visibility: NotificationVisibility.private,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: false,
          threadIdentifier: 'active_consultation',
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  RemoteMessage? get launchMessage => _launchMessage;
  Map<String, dynamic>? get foregroundTapData => _foregroundTapData;
  bool? get fullScreenCallPermissionGranted =>
      _fullScreenCallPermissionGranted;
  Stream<NativeIncomingCallEvent> get nativeIncomingCallActions =>
      _callKitActions.stream;
  bool get hasPendingAcceptedIncomingCall => _pendingCallKitActions.values
      .contains(NativeIncomingCallAction.accept);

  NativeIncomingCallAction? takePendingNativeCallAction(String inviteId) =>
      _pendingCallKitActions.remove(inviteId);

  void markChatOpen(String bookingId) {
    final id = bookingId.trim();
    if (id.isEmpty) return;
    _openChatBookings[id] = (_openChatBookings[id] ?? 0) + 1;
  }

  void markChatClosed(String bookingId) {
    final id = bookingId.trim();
    if (id.isEmpty) return;
    final remaining = (_openChatBookings[id] ?? 0) - 1;
    if (remaining > 0) {
      _openChatBookings[id] = remaining;
    } else {
      _openChatBookings.remove(id);
    }
  }

  bool _isChatOpen(Map<String, dynamic> data) {
    final bookingId = data['booking_id']?.toString().trim() ?? '';
    return bookingId.isNotEmpty && _openChatBookings.containsKey(bookingId);
  }

  Future<void> initialize() async {
    if (Platform.isAndroid) {
      _nativeIncomingCallBridge.setMethodCallHandler((call) async {
        if (call.method != 'acceptedCall') return null;
        final arguments = call.arguments;
        final inviteId = arguments is Map
            ? arguments['invite_id']?.toString().trim() ?? ''
            : '';
        if (inviteId.isEmpty) return null;
        _rememberNativeCallAction(
          inviteId,
          NativeIncomingCallAction.accept,
          <String, dynamic>{},
        );
        return true;
      });
    }

    const consultationChannel = AndroidNotificationChannel(
      _consultationChannelId,
      'Consultation updates',
      description: 'Consultation requests, responses and status updates',
      importance: Importance.high,
      playSound: true,
      sound: _customNotificationSound,
      enableVibration: true,
    );
    const chatChannel = AndroidNotificationChannel(
      _chatChannelId,
      'Consultation messages',
      description: 'New messages from your doctor or patient',
      importance: Importance.high,
      playSound: true,
      sound: _customNotificationSound,
      enableVibration: true,
    );
    const activeConsultationChannel = AndroidNotificationChannel(
      'active_consultation',
      'Active consultation',
      description: 'Shows when a Darmaan consultation is currently in progress',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
      showBadge: false,
    );

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
   await _localNotifications.initialize(
  settings: initializationSettings,
  onDidReceiveNotificationResponse: (response) {
    final payload = response.payload;

    if (payload == null || payload.isEmpty) return;

    try {
      _foregroundTapData = Map<String, dynamic>.from(
        jsonDecode(payload) as Map,
      );
    } catch (_) {}
  },
);

    // A full-screen local notification starts the Android activity directly.
    // Unlike an FCM notification tap, that launch is reported by the local
    // notifications plugin, so preserve its payload for the incoming-call
    // coordinator after authentication has been restored.
    final localLaunchDetails =
        await _localNotifications.getNotificationAppLaunchDetails();
    final localLaunchPayload =
        localLaunchDetails?.notificationResponse?.payload;
    if (localLaunchDetails?.didNotificationLaunchApp == true &&
        localLaunchPayload != null &&
        localLaunchPayload.isNotEmpty) {
      try {
        _foregroundTapData = Map<String, dynamic>.from(
          jsonDecode(localLaunchPayload) as Map,
        );
      } catch (_) {}
    }

    final androidNotifications = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidNotifications?.createNotificationChannel(
      _incomingCallChannel,
    );
    await androidNotifications?.createNotificationChannel(consultationChannel);
    await androidNotifications?.createNotificationChannel(chatChannel);
    await androidNotifications?.createNotificationChannel(
      activeConsultationChannel,
    );

    if (Platform.isAndroid) {
      _callKitSubscription ??= FlutterCallkitIncoming.onEvent.listen(
        _handleCallKitEvent,
      );
      await _recoverAcceptedNativeLaunch();
      await _recoverAcceptedCallKitAction();
    }

    await _messaging.setAutoInitEnabled(true);
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );
    _launchMessage = await _messaging.getInitialMessage();

    _openedAppSubscription ??=
        FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _launchMessage = message;
    });

    _foregroundSubscription ??= FirebaseMessaging.onMessage.listen(
      _showForegroundNotification,
    );
  }

  Future<void> showConsultationInProgress({
    required String bookingId,
    required String peerName,
    required bool isDoctor,
    DateTime? startedAt,
  }) async {
    final cleanName = peerName.trim().isEmpty
        ? (isDoctor ? 'your patient' : 'your doctor')
        : peerName.trim();
    await _localNotifications.show(
      id: _activeConsultationNotificationId,
      title: 'Consultation in progress',
      body: isDoctor
          ? 'Your consultation with $cleanName is active.'
          : 'Your consultation with $cleanName is active.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'active_consultation',
          'Active consultation',
          channelDescription:
              'Shows when a Darmaan consultation is currently in progress',
          importance: Importance.low,
          priority: Priority.low,
          playSound: false,
          enableVibration: false,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          showWhen: true,
          when: startedAt?.millisecondsSinceEpoch,
          usesChronometer: startedAt != null,
          visibility: NotificationVisibility.private,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: false,
          threadIdentifier: 'active_consultation',
        ),
      ),
      payload: jsonEncode({
        'type': 'consultation_in_progress',
        'booking_id': bookingId,
      }),
    );
  }

  Future<void> cancelConsultationInProgress() =>
      _localNotifications.cancel(id: _activeConsultationNotificationId);

  Future<void> cancelIncomingCall(String inviteId) async {
    final cleanId = inviteId.trim();
    if (cleanId.isEmpty) return;
    if (Platform.isAndroid) {
      try {
        await FlutterCallkitIncoming.endCall(cleanId);
      } catch (_) {}
    }
    await _localNotifications.cancel(id: _callNotificationId(cleanId));
  }

  void _handleCallKitEvent(CallEvent? event) {
    late final CallKitParams params;
    late final NativeIncomingCallAction action;
    if (event is CallEventActionCallAccept) {
      params = event.callKitParams;
      action = NativeIncomingCallAction.accept;
    } else if (event is CallEventActionCallDecline) {
      params = event.callKitParams;
      action = NativeIncomingCallAction.decline;
    } else {
      return;
    }
    final inviteId =
        params.extra?['invite_id']?.toString().trim() ?? params.id.trim();
    if (inviteId.isEmpty) return;
    _rememberCallKitAction(params, action);
  }

  void _rememberCallKitAction(
    CallKitParams params,
    NativeIncomingCallAction action,
  ) {
    final inviteId =
        params.extra?['invite_id']?.toString().trim() ?? params.id.trim();
    if (inviteId.isEmpty) return;
    _rememberNativeCallAction(
      inviteId,
      action,
      Map<String, dynamic>.from(params.extra ?? const {}),
    );
  }

  void _rememberNativeCallAction(
    String inviteId,
    NativeIncomingCallAction action,
    Map<String, dynamic> extra,
  ) {
    _pendingCallKitActions[inviteId] = action;
    unawaited(
      _localNotifications.cancel(id: _callNotificationId(inviteId)),
    );
    extra['type'] = 'incoming_video_call';
    extra['invite_id'] = inviteId;
    _foregroundTapData = extra;
    _callKitActions.add(
      NativeIncomingCallEvent(inviteId: inviteId, action: action),
    );
  }

  Future<void> _recoverAcceptedNativeLaunch() async {
    try {
      final data = await _nativeIncomingCallBridge
          .invokeMapMethod<String, dynamic>('takePendingAcceptedCall');
      final inviteId = data?['invite_id']?.toString().trim() ?? '';
      if (inviteId.isEmpty) return;
      _rememberNativeCallAction(
        inviteId,
        NativeIncomingCallAction.accept,
        <String, dynamic>{},
      );
    } catch (_) {
      // Non-Android platforms and older installs have no native bridge.
    }
  }

  Future<void> _recoverAcceptedCallKitAction() async {
    if (hasPendingAcceptedIncomingCall) return;
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      for (final call in calls) {
        if (call.isAccepted) {
          _rememberCallKitAction(call, NativeIncomingCallAction.accept);
          return;
        }
      }
    } catch (_) {}
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final type = message.data['type']?.toString() ?? '';
    if (type == 'chat_message' && _isChatOpen(message.data)) {
      return;
    }
    if (type == 'incoming_video_call_ended') {
      final inviteId = message.data['invite_id']?.toString() ?? '';
      if (inviteId.isNotEmpty) await cancelIncomingCall(inviteId);
      return;
    }

    final notification = message.notification;
    final title = notification?.title ?? message.data['title']?.toString();
    final body = notification?.body ?? message.data['body']?.toString();
    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      return;
    }

    if (type == 'consultation_completed' ||
        type == 'patient_cancelled_appointment') {
      await cancelConsultationInProgress();
    }
    if (type == 'session_start_accepted') {
      await showConsultationInProgress(
        bookingId: message.data['booking_id']?.toString() ?? '',
        peerName: message.data['patient_name']?.toString() ?? 'your patient',
        isDoctor: true,
      );
      return;
    }
    final isIncomingCall = type == 'incoming_video_call';
    if (isIncomingCall) {
      await _showIncomingCallNotification(
        _localNotifications,
        message.data,
        title: title,
        body: body,
      );
      return;
    }
    final isChatMessage = type == 'chat_message';
    final channelId =
        isChatMessage ? _chatChannelId : _consultationChannelId;
    final channelName =
        isChatMessage ? 'Consultation messages' : 'Consultation updates';

    final notificationId = message.messageId?.hashCode ??
        DateTime.now().millisecondsSinceEpoch;

  await _localNotifications.show(
  id: notificationId,
  title: title,
  body: body,
  notificationDetails: NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: isChatMessage
          ? 'New messages from your doctor or patient'
          : 'Consultation requests, responses and status updates',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      sound: _customNotificationSound,
      enableVibration: true,
      visibility: NotificationVisibility.private,
    ),
    iOS: const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'darman_notification.caf',
    ),
  ),
  payload: jsonEncode(message.data),
);
  
  }

  Future<bool> activateForSignedInUser() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return false;

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    final allowed =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;

    if (!allowed) return false;

    if (Platform.isAndroid) {
      try {
        _fullScreenCallPermissionGranted =
            await FlutterCallkitIncoming.canUseFullScreenIntent();
      } catch (_) {
        _fullScreenCallPermissionGranted = false;
        // Android falls back to a persistent heads-up call notification.
      }
    }

    final token = await _messaging.getToken();
    if (token != null && token.trim().isNotEmpty) {
      await _registerToken(token.trim());
    }

    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen(
      (token) async {
        try {
          await _registerToken(token);
        } catch (_) {}
      },
    );

    return true;
  }

  Map<String, dynamic>? takePendingIncomingCallData() {
    final localData = _foregroundTapData;
    if (localData?['type']?.toString() == 'incoming_video_call') {
      _foregroundTapData = null;
      return Map<String, dynamic>.from(localData!);
    }

    final remoteData = _launchMessage?.data;
    if (remoteData?['type']?.toString() == 'incoming_video_call') {
      _launchMessage = null;
      return Map<String, dynamic>.from(remoteData!);
    }
    return null;
  }

  Future<bool> requestFullScreenCallPermission() async {
    if (!Platform.isAndroid) return true;
    final granted = await FlutterCallkitIncoming.requestFullIntentPermission();
    _fullScreenCallPermissionGranted = granted;
    return _fullScreenCallPermissionGranted!;
  }

  Future<void> _registerToken(String token) async {
    await Supabase.instance.client.rpc(
      'register_push_token',
      params: {
        'p_token': token,
        'p_platform': Platform.isAndroid ? 'android' : 'ios',
      },
    );
  }

  Future<void> deactivateBeforeSignOut() async {
    await cancelConsultationInProgress();
    final token = await _messaging.getToken();

    if (token != null &&
        token.trim().isNotEmpty &&
        Supabase.instance.client.auth.currentUser != null) {
      try {
        await Supabase.instance.client.rpc(
          'unregister_push_token',
          params: {'p_token': token.trim()},
        );
      } catch (_) {}
    }

    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    await _openedAppSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _callKitSubscription?.cancel();
    await _callKitActions.close();
  }
}
