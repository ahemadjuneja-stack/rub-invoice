import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'data/db.dart';
import 'firebase_options.dart';
import 'services/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Open the local database first - the app must boot fully offline.
  await DB.open();

  // Firebase is optional on first run. After docs/FIREBASE_SETUP.md is
  // completed, sync + OTP turn on automatically.
  bool fbReady = false;
  if (firebaseConfigured) {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.current);
      fbReady = true;
    } catch (e) {
      debugPrint('Firebase init failed, continuing offline: $e');
      fbReady = false;
    }
  }
  await SyncService.instance.configure(fbReady: fbReady);

  runApp(const RubyInvoiceApp());
}
