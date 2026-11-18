/// Tiny helper so screens can show the app version without importing
/// package_info_plus everywhere.
library;

import 'package:package_info_plus/package_info_plus.dart';

class PackageInfoHelper {
  PackageInfoHelper._();

  static String? _cached;

  static Future<String> version() async {
    final cached = _cached;
    if (cached != null) return cached;
    final info = await PackageInfo.fromPlatform();
    _cached = info.version;
    return _cached!;
  }
}
