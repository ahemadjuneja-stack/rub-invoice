import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// In-app updater with background APK download (WhatsApp-style).
///
/// Flow: [check] queries GitHub Releases, [downloadApk] streams the
/// release APK into the app cache while exposing progress, and [install]
/// hands the finished file to the Android package installer. The user
/// only ever sees a single "Install" button. (Shorebird Dart-patch OTA
/// is documented in docs/OTA_UPDATES.md.)
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const repoBase =
      'https://github.com/ahemadjuneja-stack/rub-invoice/releases';
  static const repoApi =
      'https://api.github.com/repos/ahemadjuneja-stack/rub-invoice/releases/latest';

  String? _latestTag;
  String? _apkUrl;

  /// Latest release tag without the leading 'v' (after a successful check).
  String? get latestTag => _latestTag;

  /// Direct browser download URL of the release APK (null when no
  /// release is known yet). Used as the "Download in browser" plan B
  /// when the in-app installer cannot open on the phone.
  String? get apkDirectUrl => _apkUrl;

  /// Set when a download attempt failed (used to show a Retry button).
  String? lastError;

  /// 0..1 download progress (meaningful while [downloading] is true).
  final ValueNotifier<double> downloadProgress = ValueNotifier<double>(0);

  /// Set once the APK is fully downloaded (path on disk).
  final ValueNotifier<String?> readyPath = ValueNotifier<String?>(null);

  /// True while the APK is being downloaded in the background.
  final ValueNotifier<bool> downloading = ValueNotifier<bool>(false);

  Future<(bool hasUpdate, String latestTag)> check() async {
    final info = await PackageInfo.fromPlatform();
    String latest = '';
    String? apk;
    // Primary: the GitHub REST API (same as before).
    try {
      final res = await http
          .get(
            Uri.parse(repoApi),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        latest = ((body['tag_name'] ?? '') as String)
            .replaceFirst(RegExp(r'^v'), '')
            .trim();
        apk = _firstApkUrl(body);
      }
    } catch (e) {
      debugPrint('GitHub API check failed, trying atom fallback: $e');
    }
    // RELIABILITY FALLBACK (fix: "naya update nahi aa raha"): the API
    // above is rate-limited per IP (60/hour) - shared mobile CGNAT IPs
    // can silently exhaust it. The releases.atom feed and the
    // expanded_assets page have NO rate limit, so the check survives.
    if (latest.isEmpty) {
      try {
        final (t, a) = await _checkViaAtom();
        latest = t;
        apk = a;
      } catch (e) {
        debugPrint('atom fallback failed too: $e');
      }
    }
    if (latest.isEmpty) {
      throw Exception('Update check failed (no network / GitHub down)');
    }
    _latestTag = latest;
    _apkUrl = apk;
    // Always return the clean tag (no leading 'v') - callers display
    // 'v$tag' themselves and compare it with the installed version.
    return (_isNewer(latest, info.version), latest);
  }

  /// No-rate-limit path: releases.atom lists the newest release first;
  /// the APK URL comes from the public expanded_assets HTML page.
  Future<(String tag, String? apk)> _checkViaAtom() async {
    final res = await http
        .get(
          Uri.parse('$repoBase.atom'),
          headers: {'Accept': 'application/atom+xml'},
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) throw Exception('atom ${res.statusCode}');
    final m = RegExp(r'href="[^"]*/tag/([^"]+)"').firstMatch(res.body);
    final clean = (m?.group(1) ?? '').replaceFirst(RegExp(r'^v'), '').trim();
    if (clean.isEmpty) throw Exception('atom: no release tag found');
    final apk = await _apkUrlFromAssets(clean);
    return (clean, apk);
  }

  /// Scrapes the release's expanded_assets page for the .apk link
  /// (the same page GitHub serves below every release on the web).
  Future<String?> _apkUrlFromAssets(String clean) async {
    if (clean.isEmpty) return null;
    try {
      final res = await http
          .get(Uri.parse('$repoBase/expanded_assets/v$clean'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final m = RegExp(r'href="([^"]*\.apk)"').firstMatch(res.body);
      return m == null ? null : 'https://github.com${m.group(1)}';
    } catch (_) {
      return null;
    }
  }

  String? _firstApkUrl(Map<String, dynamic> body) {
    final assets = (body['assets'] as List?) ?? const [];
    for (final a in assets) {
      if (a is Map && (a['name'] as String? ?? '').endsWith('.apk')) {
        return (a['browser_download_url'] ?? '') as String?;
      }
    }
    return null;
  }

  /// True if [candidate] (e.g. remote min_version) is newer than [current].
  static bool isNewerThan(String candidate, String current) {
    final lp = candidate.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final cp = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final a = i < lp.length ? lp[i] : 0;
      final b = i < cp.length ? cp[i] : 0;
      if (a != b) return a > b;
    }
    return false;
  }

  /// True when the remote-config forced minimum version exceeds the
  /// installed version.
  Future<bool> updateRequired(String minVersion) async {
    if (minVersion.isEmpty) return false;
    final info = await PackageInfo.fromPlatform();
    return isNewerThan(minVersion, info.version);
  }

  /// Re-adopts a previously downloaded APK for [tag] after an app
  /// restart. Never touches the network; returns true when the cached
  /// file is still on disk and [readyPath] has been restored.
  Future<bool> adoptCachedApk(String tag) async {
    final clean = tag.replaceFirst(RegExp(r'^v'), '').trim();
    if (clean.isEmpty) return false;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/ruby_invoice_$clean.apk');
    if (await file.exists() && await file.length() > 0) {
      _latestTag = clean;
      readyPath.value = file.path;
      return true;
    }
    return false;
  }

  /// Streams the latest release APK into the app cache. Safe to call
  /// repeatedly: skips if a download is already running or the file for
  /// this tag is already fully present.
  Future<void> downloadApk() async {
    final tag = _latestTag;
    final url = _apkUrl;
    if (tag == null || url == null) return;
    if (downloading.value || readyPath.value != null) return;

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/ruby_invoice_$tag.apk');
    if (await file.exists() && await file.length() > 0) {
      readyPath.value = file.path;
      return;
    }

    downloading.value = true;
    downloadProgress.value = 0;
    lastError = null;
    try {
      final req = http.Request('GET', Uri.parse(url));
      final res = await http.Client().send(req);
      if (res.statusCode != 200) {
        throw Exception('APK download failed (${res.statusCode})');
      }
      final total = res.contentLength ?? -1;
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in res.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) downloadProgress.value = received / total;
      }
      await sink.flush();
      await sink.close();
      readyPath.value = file.path;
    } catch (e) {
      lastError = e.toString();
      debugPrint('APK download failed: $e');
      if (await file.exists()) await file.delete();
      downloadProgress.value = 0;
    } finally {
      downloading.value = false;
    }
  }

  /// Opens the downloaded APK with the Android package installer.
  Future<bool> install() async {
    final path = readyPath.value;
    if (path == null) return false;
    final res = await OpenFilex.open(
      path,
      type: 'application/vnd.android.package-archive',
    );
    return res.type == ResultType.done;
  }

  /// Drops the cached download (e.g. after the release changed).
  Future<void> reset() async {
    final path = readyPath.value;
    if (path != null) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    lastError = null;
    downloadProgress.value = 0;
    readyPath.value = null;
    downloading.value = false;
  }

  bool _isNewer(String latest, String current) =>
      isNewerThan(latest, current);
}
