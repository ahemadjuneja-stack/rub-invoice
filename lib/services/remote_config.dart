import 'dart:async';
import 'dart:convert';
import '../core/app_log.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remote feature configuration - the WhatsApp/Blinkit-style channel to
/// flip app behaviour WITHOUT shipping an update.
///
/// Backed by the Firestore document `config/app` (see docs/REMOTE_CONTROL.md):
///   notice       (String) announcement banner, '' hides it
///   min_version  (String) force-update gate, e.g. "0.2.2", '' = off
///   features     (Map<String, bool>) overrides: {reports: false, ...}
///   auto_approve (bool)   new registrations activate themselves without
///                         waiting for the Admin. Defaults to TRUE while
///                         the field/doc is missing.
///
/// The admin edits the document from the Firebase Console on their phone;
/// every installed app picks it up live via snapshots() and caches the
/// last-known values in SharedPreferences so offline starts still honour
/// the most recent flags.
class RemoteConfig {
  final String notice;
  final String minVersion;
  final Map<String, bool> features;
  final bool autoApprove;

  /// Support WhatsApp number (10 digits, editable from the Ruby Key
  /// Remote Control panel). When empty the lock screens show the
  /// Gmail/email button instead. Remote value wins over the
  /// compile-time AppConstants.supportWhatsApp fallback.
  final String supportMobile;
  const RemoteConfig({
    this.notice = '',
    this.minVersion = '',
    this.features = const {},
    this.autoApprove = true,
    this.supportMobile = '',
  });

  /// Flags default to ON - the admin only lists overrides for features
  /// they want to hide.
  bool feature(String key) => features[key] ?? true;

  factory RemoteConfig.fromMap(Map<String, dynamic> data) => RemoteConfig(
        notice: (data['notice'] ?? '') as String,
        minVersion: (data['min_version'] ?? '') as String,
        features: ((data['features'] ?? const {}) as Map)
            .map((k, v) => MapEntry(k.toString(), v == true)),
        autoApprove: (data['auto_approve'] ?? true) == true,
        supportMobile: (data['support_mobile'] ?? '') as String,
      );
}

class RemoteConfigService {
  RemoteConfigService._();
  static final RemoteConfigService instance = RemoteConfigService._();

  final ValueNotifier<RemoteConfig> config =
      ValueNotifier<RemoteConfig>(const RemoteConfig());

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  Future<void> init({required bool fbReady}) async {
    // Re-init safe (boot + background recovery): drop the old listener
    // first so wires are never duplicated.
    _sub?.cancel();
    _sub = null;
    // Offline-first: restore the last-known config before any network.
    final sp = await SharedPreferences.getInstance();
    final cached = sp.getString('remote_config_v1');
    if (cached != null) {
      try {
        config.value =
            RemoteConfig.fromMap(jsonDecode(cached) as Map<String, dynamic>);
      } catch (e) {
        appLog('remote config cache parse failed: $e');
      }
    }
    if (!fbReady) return;
    _sub = FirebaseFirestore.instance
        .collection('config')
        .doc('app')
        .snapshots()
        .listen((doc) async {
      final data = doc.data();
      if (data == null) return;
      config.value = RemoteConfig.fromMap(data);
      try {
        final sp2 = await SharedPreferences.getInstance();
        await sp2.setString('remote_config_v1', jsonEncode(data));
      } catch (_) {}
    }, onError: (e) => appLog('remote config listen failed: $e'));
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
