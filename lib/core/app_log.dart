import 'package:flutter/foundation.dart';

/// RELEASE-SAFE LOGGING (security hardening).
///
/// Every log line in the app must go through [appLog] instead of a bare
/// debugPrint/print. In debug builds it behaves exactly like debugPrint
/// (same output, same throttling). In RELEASE builds it is compiled out
/// completely - kDebugMode is a compile-time constant, so the whole body
/// (and its string interpolation, which can carry customer names, phone
/// numbers and sync errors) is tree-shaken away and nothing ever reaches
/// the Android Logcat.
///
/// Never log secrets, tokens, PINs or raw customer data - even in debug
/// builds. This hook exists so a release build leaks nothing.
void appLog(String message, [Object? error, StackTrace? stackTrace]) {
  if (!kDebugMode) return;
  if (error != null) {
    debugPrint('$message error=$error');
    if (stackTrace != null) debugPrint('$stackTrace');
  } else {
    debugPrint(message);
  }
}
