import 'package:firebase_core/firebase_core.dart';

/// Real Firebase config for the Ruby Invoice Android app.
///
/// Generated from android/app/google-services.json (Firebase project
/// `ruby-invoice-c17bd`, Android package `com.rubyinvoice.ruby_invoice`).
/// Because the keys are real, `firebaseConfigured` is true and the app
/// connects to Firestore sync on startup.
class DefaultFirebaseOptions {
  static const FirebaseOptions current = FirebaseOptions(
    apiKey: 'AIzaSyCBPMZrOqIN8mO3lEWknvK_LnuzakpeWjU',
    appId: '1:972758775225:android:73cf3536b6d2a33e54f268',
    messagingSenderId: '972758775225',
    projectId: 'ruby-invoice-c17bd',
    storageBucket: 'ruby-invoice-c17bd.firebasestorage.app',
  );
}

/// True only after the stub has been replaced with real Firebase keys.
bool get firebaseConfigured =>
    !DefaultFirebaseOptions.current.apiKey.contains('PASTE_');
