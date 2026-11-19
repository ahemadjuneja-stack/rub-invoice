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

  static const repoApi =
      'https://api.github.com/repos/ahemadjuneja-stack/rub-invoice/releases/latest';

  String? _latestTag;
  String? _apkUrl;

  /// Latest release tag without the leading 'v' (after a successful check).
  String? get latestTag => _latestTag;

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
    final res = await http.get(
      Uri.parse(repoApi),
      headers: {'Accept': 'application/vnd.github+json'},
    );
    if (res.statusCode != 200) {
      throw Exception('GitHub API error ${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = (body['tag_name'] ?? '') as String;
    final latest = tag.replaceFirst(RegExp(r'^v'), '').trim();
    _latestTag = latest.isEmpty ? null : latest;
    _apkUrl = _firstApkUrl(body);
    return (_isNewer(latest, info.version), tag.isEmpty ? latest : tag);
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
