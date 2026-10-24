import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point')
Future<void> campusPlusMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Background push received: ${message.messageId}');
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  static const _channel = AndroidNotificationChannel(
    'campusplus_updates',
    'CampusPlus updates',
    description: 'Updates about campus issues and maintenance tasks.',
    importance: Importance.high,
  );

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Future<void> Function(String? issueId, String? notificationType)? _onOpen;
  String? _pendingIssueId;
  String? _pendingNotificationType;
  bool _hasPendingOpen = false;

  set onOpen(
    Future<void> Function(String? issueId, String? notificationType)? callback,
  ) {
    _onOpen = callback;
    if (callback != null && _hasPendingOpen) {
      _hasPendingOpen = false;
      unawaited(callback(_pendingIssueId, _pendingNotificationType));
      _pendingIssueId = null;
      _pendingNotificationType = null;
    }
  }

  String? _currentToken;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _localNotifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload?.split('|') ?? const <String>[];
        _dispatchOpen(
          payload.isEmpty ? null : payload.first,
          payload.length < 2 ? null : payload[1],
        );
      },
    );
    final androidNotifications =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidNotifications?.createNotificationChannel(_channel);

    FirebaseMessaging.onBackgroundMessage(
      campusPlusMessagingBackgroundHandler,
    );
    _subscriptions.add(FirebaseMessaging.onMessage.listen(
      _showForegroundMessage,
      onError: (Object error) =>
          debugPrint('Foreground push stream failed: $error'),
    ));
    _subscriptions.add(FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _dispatchOpen(
        message.data['issueId'] as String?,
        message.data['notificationType'] as String?,
      ),
      onError: (Object error) =>
          debugPrint('Push navigation stream failed: $error'),
    ));
    // Cloud Functions sends standard FCM registration tokens, not Firebase installation IDs.
    // Keep the token API until the Admin SDK supports the new FID registration flow.
    // ignore: deprecated_member_use
    _subscriptions.add(_messaging.onTokenRefresh.listen(
      (token) => unawaited(_saveToken(token)),
      onError: (Object error) => debugPrint('FCM token refresh failed: $error'),
    ));
    _subscriptions.add(FirebaseAuth.instance.authStateChanges().listen(
      (user) {
        if (user != null) {
          unawaited(
            _syncToken(requestPermission: true).catchError((Object error) {
              debugPrint('Could not register push token: $error');
              return false;
            }),
          );
        }
      },
      onError: (Object error) =>
          debugPrint('Push authentication listener failed: $error'),
    ));
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _dispatchOpen(
        initialMessage.data['issueId'] as String?,
        initialMessage.data['notificationType'] as String?,
      );
    }
  }

  void _dispatchOpen(String? issueId, String? notificationType) {
    final callback = _onOpen;
    if (callback == null) {
      _pendingIssueId = issueId;
      _pendingNotificationType = notificationType;
      _hasPendingOpen = true;
      return;
    }
    unawaited(callback(issueId, notificationType));
  }

  Future<void> setEnabled(bool enabled) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in to change push settings.');

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .update({'pushEnabled': enabled});
    if (enabled) {
      final registered = await _syncToken(requestPermission: true);
      if (!registered) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'pushEnabled': false});
        throw StateError(
          'Notification permission is off. Allow notifications in Android Settings and try again.',
        );
      }
    } else {
      // ignore: deprecated_member_use
      final token = _currentToken ?? await _messaging.getToken();
      if (token != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('fcmTokens')
            .doc(token)
            .delete();
      }
      _currentToken = null;
      // ignore: deprecated_member_use
      await _messaging.deleteToken();
    }
  }

  Future<bool> _syncToken({bool requestPermission = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final profile = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (profile.data()?['pushEnabled'] != true) return false;

    final settings = requestPermission
        ? await _messaging.requestPermission(
            alert: true, badge: true, sound: true)
        : await _messaging.getNotificationSettings();
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      return false;
    }

    // ignore: deprecated_member_use
    final token = await _messaging.getToken();
    if (token == null) return false;
    await _saveToken(token);
    return true;
  }

  Future<void> _saveToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final profile = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (profile.data()?['pushEnabled'] != true) return;
    _currentToken = token;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('fcmTokens')
        .doc(token)
        .set({
      'token': token,
      'platform': defaultTargetPlatform.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _showForegroundMessage(RemoteMessage message) async {
    final title =
        message.notification?.title ?? message.data['title'] as String?;
    final body = message.notification?.body ?? message.data['body'] as String?;
    if (title == null && body == null) return;
    await _localNotifications.show(
      id: message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title: title ?? 'CampusPlus update',
      body: body ?? 'There is an update on your campus issue.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload:
          '${message.data['issueId'] as String? ?? ''}|${message.data['notificationType'] as String? ?? ''}',
    );
  }

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _initialized = false;
  }
}
