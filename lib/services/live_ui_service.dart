import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Color;

import '../core/app_log.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LIVE UI ENGINE - the zero-update channel (WhatsApp / Blinkit style).
///
/// Ruby Key (admin PWA) writes the Firestore document
/// `app_config/live_ui`; every installed phone listens to it live via
/// snapshots() and applies the changes on the next screen rebuild -
/// no APK, no Play Store, nothing to install. The last-known config
/// is cached in SharedPreferences (`live_ui_cache_v1`) so the app
/// works offline and every value has a SAFE DEFAULT.
///
/// Document shape (all fields optional, all defaults safe):
///   maintenance_mode      (bool)   full-screen maintenance gate
///   enable_bilty_upload   (bool)   default true  - billty photo capture
///   enable_gst_fields     (bool)   default true  - GST inputs on bills
///   enable_razorpay_banner(bool)   default false - offer banner on home
///   enable_pdf_share      (bool)   default true  - share PDF buttons
///   banner                (Map)    {enabled, text, bg, fg} announcement
///   primary_color         (String) hex like "#9B111E" - primary buttons
///   primary_label         (String) text under the home + button, '' = icon
///   shortcuts             (List)   admin-defined menu cards:
///                                  {id, label, icon, color, action, visible}
///   updatedAt             (serverTimestamp)
class LiveUiConfig {
  final bool maintenanceMode;
  final bool enableBiltyUpload;
  final bool enableGstFields;
  final bool enableRazorpayBanner;
  final bool enablePdfShare;

  final bool bannerEnabled;
  final String bannerText;
  final Color? bannerBg;
  final Color? bannerFg;

  final Color? primaryColor;
  final String primaryLabel;

  final List<LiveShortcut> shortcuts;

  const LiveUiConfig({
    this.maintenanceMode = false,
    this.enableBiltyUpload = true,
    this.enableGstFields = true,
    this.enableRazorpayBanner = false,
    this.enablePdfShare = true,
    this.bannerEnabled = false,
    this.bannerText = '',
    this.bannerBg,
    this.bannerFg,
    this.primaryColor,
    this.primaryLabel = '',
    this.shortcuts = const [],
  });

  /// Cached config from any source. Missing keys = safe defaults, so a
  /// half-written or old document can never break a phone.
  factory LiveUiConfig.fromMap(Map<String, dynamic> d) {
    bool flag(String key, bool def) {
      final v = d[key];
      if (v is bool) return v;
      return def;
    }

    final banner = (d['banner'] is Map) ? (d['banner'] as Map) : const {};
    final shortcuts = <LiveShortcut>[];
    if (d['shortcuts'] is List) {
      for (final raw in (d['shortcuts'] as List)) {
        try {
          if (raw is Map) {
            final s = LiveShortcut.fromMap(Map<String, dynamic>.from(raw));
            if (s.id.isNotEmpty && s.visible) shortcuts.add(s);
          }
        } catch (_) {
          // A malformed shortcut row is skipped, never fatal.
        }
      }
    }

    return LiveUiConfig(
      maintenanceMode: flag('maintenance_mode', false),
      enableBiltyUpload: flag('enable_bilty_upload', true),
      enableGstFields: flag('enable_gst_fields', true),
      enableRazorpayBanner: flag('enable_razorpay_banner', false),
      enablePdfShare: flag('enable_pdf_share', true),
      bannerEnabled: (banner['enabled'] ?? false) == true,
      bannerText: (banner['text'] ?? '') as String,
      bannerBg: parseHex(banner['bg']?.toString()),
      bannerFg: parseHex(banner['fg']?.toString()),
      primaryColor: parseHex(d['primary_color']?.toString()),
      primaryLabel: (d['primary_label'] ?? '') as String,
      shortcuts: shortcuts,
    );
  }

  Map<String, dynamic> toMap() => {
        'maintenance_mode': maintenanceMode,
        'enable_bilty_upload': enableBiltyUpload,
        'enable_gst_fields': enableGstFields,
        'enable_razorpay_banner': enableRazorpayBanner,
        'enable_pdf_share': enablePdfShare,
        'banner': {
          'enabled': bannerEnabled,
          'text': bannerText,
          'bg': bannerBg?.toHex(),
          'fg': bannerFg?.toHex(),
        },
        'primary_color': primaryColor?.toHex() ?? '',
        'primary_label': primaryLabel,
        'shortcuts': [for (final s in shortcuts) s.toMap()],
      };
}

/// One admin-defined shortcut card on the Menu tab.
class LiveShortcut {
  final String id;
  final String label;
  final String icon; // icon name, mapped in the app (unknown -> link icon)
  final Color? color;
  final String action; // open:* | url:* | dial:* | none
  final bool visible;

  const LiveShortcut({
    required this.id,
    required this.label,
    this.icon = '',
    this.color,
    this.action = 'none',
    this.visible = true,
  });

  factory LiveShortcut.fromMap(Map<String, dynamic> d) => LiveShortcut(
        id: (d['id'] ?? '').toString(),
        label: (d['label'] ?? '').toString(),
        icon: (d['icon'] ?? '').toString(),
        color: parseHex(d['color']?.toString()),
        action: (d['action'] ?? 'none').toString(),
        visible: (d['visible'] ?? true) == true,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'icon': icon,
        'color': color?.toHex() ?? '',
        'action': action,
        'visible': visible,
      };
}

/// "#9B111E" / "9B111E" -> Color; anything else -> null (theme default).
Color? parseHex(String? raw) {
  if (raw == null) return null;
  var s = raw.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 6) s = 'FF$s';
  if (s.length != 8) return null;
  final v = int.tryParse(s, radix: 16);
  if (v == null) return null;
  return Color(v);
}

extension HexColor on Color {
  String toHex() =>
      '#${toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
}

class LiveUiService {
  LiveUiService._();
  static final LiveUiService instance = LiveUiService._();

  final ValueNotifier<LiveUiConfig> config =
      ValueNotifier<LiveUiConfig>(const LiveUiConfig());

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  static const _cacheKey = 'live_ui_cache_v1';

  /// Re-init safe (boot + Firebase background recovery): the old
  /// listener is dropped first so wires are never duplicated. The
  /// cached config is applied BEFORE any network so even a cold
  /// offline start shows the admin's last-known UI.
  Future<void> init({required bool fbReady}) async {
    _sub?.cancel();
    _sub = null;
    try {
      final sp = await SharedPreferences.getInstance();
      final cached = sp.getString(_cacheKey);
      if (cached != null) {
        config.value =
            LiveUiConfig.fromMap(jsonDecode(cached) as Map<String, dynamic>);
      }
    } catch (e) {
      appLog('live ui cache parse failed: $e');
    }
    if (!fbReady) return;
    _sub = FirebaseFirestore.instance
        .collection('app_config')
        .doc('live_ui')
        .snapshots()
        .listen((doc) async {
      final data = doc.data();
      if (data == null) return;
      config.value = LiveUiConfig.fromMap(data);
      try {
        final sp2 = await SharedPreferences.getInstance();
        await sp2.setString(_cacheKey, jsonEncode(data));
      } catch (_) {}
    }, onError: (e) => appLog('live ui listen failed: $e'));
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
