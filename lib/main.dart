import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'data/db.dart';
import 'firebase_options.dart';
import 'services/remote_config.dart';
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
      // Offline persistence: Firestore keeps a local cache so the live
      // access-control snapshot (users/{uid}) and every sync query keep
      // working with zero network (spec: persistenceEnabled: true).
      FirebaseFirestore.instance.settings =
          const Settings(persistenceEnabled: true);
      fbReady = true;
    } catch (e) {
      debugPrint('Firebase init failed, continuing offline: $e');
      fbReady = false;
    }
  }
  await SyncService.instance.configure(fbReady: fbReady);

  // Remote feature flags (config/app): notice banner, force-update gate
  // and per-feature toggles - changeable from the Firebase Console
  // without shipping an update (docs/REMOTE_CONTROL.md).
  await RemoteConfigService.instance.init(fbReady: fbReady);

  runApp(const RubyInvoiceApp());
}
