import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return android;
    }
    throw UnsupportedError(
      'CampusPlus Firebase configuration is currently set up for Android only.',
    );
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDHpZALwPrfgBkFwZgxcDVh4rykeRU9rSc',
    appId: '1:1002162949752:android:3fa3fc9e4d33a2c500278d',
    messagingSenderId: '1002162949752',
    projectId: 'campusplus-210d8',
    storageBucket: 'campusplus-210d8.firebasestorage.app',
  );
}
