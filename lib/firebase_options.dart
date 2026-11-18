import 'package:firebase_core/firebase_core.dart';

/// STUB CONFIG - REPLACE THIS FILE (see docs/FIREBASE_SETUP.md).
///
/// Run `flutterfire configure` after creating your Firebase project and
/// this file will be regenerated with your real keys. Until then the app
/// runs 100% offline and sync stays disabled (detected via the PASTE_
/// markers below, so no crash and no wasted network calls).
class DefaultFirebaseOptions {
  static const FirebaseOptions current = FirebaseOptions(
    apiKey: 'PASTE_ANDROID_API_KEY',
    appId: 'PASTE_ANDROID_APP_ID',
    messagingSenderId: 'PASTE_SENDER_ID',
    projectId: 'PASTE_PROJECT_ID',
    storageBucket: 'PASTE_STORAGE_BUCKET',
  );
}

/// True only after the stub has been replaced with real Firebase keys.
bool get firebaseConfigured =>
    !DefaultFirebaseOptions.current.apiKey.contains('PASTE_');
