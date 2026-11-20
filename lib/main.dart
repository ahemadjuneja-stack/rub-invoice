import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'data/db.dart';
import 'data/repo.dart';
import 'firebase_options.dart';
import 'services/remote_config.dart';
import 'services/sync_service.dart';

/// SPLASH FAILSAFE (fix: app stuck on the splash after Clear Data).
///
/// The whole boot sequence below runs under a HARD 3-second budget.
/// Every startup await gets only the time LEFT in that budget, so
/// runApp() ALWAYS executes within 3 seconds - even if the local
/// database, Firebase.initializeApp or Google Play Services take
/// forever on a dead-slow network (or after Clear Data, when Play
/// Services re-verifies the app and can hang the auth handshake).
/// Anything that did not finish in time simply continues in the
/// background / degrades to offline mode - it can never block the UI.
const Duration _bootBudget = Duration(seconds: 3);

Future<void> main() async {
  final bootWatch = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Time LEFT in the 3-second boot budget (never negative).
  Duration left() {
    final l = _bootBudget - bootWatch.elapsed;
    return l > Duration.zero ? l : Duration.zero;
  }

  // Open the local database first - the app must boot fully offline.
  // Timeout-guarded: a slow/hung DB open can no longer hold the
  // splash forever; later DB.open() calls reuse the same in-flight
  // future, so nothing is lost by cutting the await short.
  try {
    await DB.open().timeout(left());
  } catch (e) {
    debugPrint('DB open slow or failed - continuing: $e');
  }

  // Billty (lorry receipt) photos expire after 45 days: expired files
  // delete themselves quietly at every app start, boot never waits.
  unawaited(Repo.instance.cleanExpiredBillties());

  // Firebase is optional on first run. After Clear Data Google Play
  // Services can hang the init handshake on a slow network - the
  // timeout below turns that into offline mode instead of an
  // infinite splash. The next app start retries normally.
  bool fbReady = false;
  if (firebaseConfigured) {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.current)
          .timeout(left());
      // Offline persistence: Firestore keeps a local cache so the live
      // access-control snapshot (users/{uid}) and every sync query keep
      // working with zero network (spec: persistenceEnabled: true).
      FirebaseFirestore.instance.settings =
          const Settings(persistenceEnabled: true);
      fbReady = true;
    } catch (e) {
      debugPrint('Firebase init failed or too slow, continuing offline: $e');
      fbReady = false;
      // v0.2.19: boot failed on a dead-slow network? The app used to
      // stay offline (no login, no cloud sync) for the WHOLE session.
      // Now Firebase is retried in the background; the moment it is
      // ready the login screen / sync appear automatically.
      unawaited(_recoverFirebaseInBackground());
    }
  }

  // Sync wiring (pure listener setup - but still budget-guarded).
  try {
    await SyncService.instance.configure(fbReady: fbReady).timeout(left());
  } catch (e) {
    debugPrint('Sync configure skipped (boot budget): $e');
  }

  // Remote feature flags (config/app): notice banner, force-update gate
  // and per-feature toggles - changeable from the Firebase Console
  // without shipping an update (docs/REMOTE_CONTROL.md). Listener
  // setup only; if the budget is gone it still installs, just later.
  try {
    await RemoteConfigService.instance.init(fbReady: fbReady).timeout(left());
  } catch (e) {
    debugPrint('RemoteConfig init skipped (boot budget): $e');
  }

  // FAILSAFE GUARANTEE: first frame - and therefore the end of the
  // native splash - is reached within the 3-second budget no matter
  // what happened above.
  runApp(const RubyInvoiceApp());
}

/// Boot-time Firebase init failed or was cut by the 3s budget.
/// Retry in the background with generous timeouts; when it succeeds,
/// re-wire sync + remote config and notify the UI (AuthGate listens
/// to SyncService.fbReadyNotifier and shows the login screen).
Future<void> _recoverFirebaseInBackground() async {
  for (int i = 1; i <= 3; i++) {
    await Future<void>.delayed(Duration(seconds: 4 * i));
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.current)
          .timeout(const Duration(seconds: 12));
      FirebaseFirestore.instance.settings =
          const Settings(persistenceEnabled: true);
      await SyncService.instance.configure(fbReady: true);
      await RemoteConfigService.instance.init(fbReady: true);
      debugPrint('Firebase recovered in background - login + sync live');
      return;
    } catch (e) {
      debugPrint('Firebase background retry $i failed: $e');
    }
  }
}
