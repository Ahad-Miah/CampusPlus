import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app.dart';
import 'firebase_options.dart';
import 'services/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const CampusPlusApp());
  unawaited(
    PushNotificationService.instance.initialize().catchError(
      (Object error, StackTrace stackTrace) {
        debugPrint('Could not initialize push notifications: $error');
      },
    ),
  );
}
