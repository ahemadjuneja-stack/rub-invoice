import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// In-app update checker against GitHub Releases.
/// The release pipeline (.github/workflows/android.yml) attaches the
/// release APK to every v* tag; this service compares versions and opens
/// the release page for download. (Shorebird Dart-patch OTA is documented
/// in docs/OTA_UPDATES.md.)
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const repoApi =
      'https://api.github.com/repos/ahemadjuneja-stack/rub-invoice/releases/latest';

  Future<(bool hasUpdate, String latestTag, String releaseUrl)> check() async {
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
    final url = (body['html_url'] ?? '') as String;
    final latest = tag.replaceFirst(RegExp(r'^v'), '').trim();
    return (_isNewer(latest, info.version), tag.isEmpty ? latest : tag, url);
  }

  bool _isNewer(String latest, String current) {
    final lp = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final cp = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final a = i < lp.length ? lp[i] : 0;
      final b = i < cp.length ? cp[i] : 0;
      if (a != b) return a > b;
    }
    return false;
  }

  Future<void> openRelease(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
