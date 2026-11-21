import 'app_log.dart';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// CRASH ISOLATION + ZERO-DATA-LOSS GUARANTEE.
///
/// A shopkeeper's billing app must NEVER die with an unhandled error,
/// and one broken feature must never take the whole app down:
///
///   * RubyErrorGuard.install()  - call once in main(). Wires
///     FlutterError.onError + PlatformDispatcher.onError (async errors)
///     into a small local crash log and makes release builds show a
///     clean grey card instead of the red developer screen.
///   * ErrorBoundary             - a per-module wrapper. If the module
///     (PDF share, billty upload, ledger, sync chip...) throws while
///     building, ONLY that card shows "Module temporarily unavailable -
///     Retry"; bills, customers and the rest of the app keep working.
///   * guard()                   - fire-and-forget async work wrapped in
///     try/catch + crash log, for one-off operations like share/upload.
///
/// Crash log: last 20 entries in SharedPreferences (`crash_log_v1`),
/// readable in Settings -> App Diagnostics (no network needed).
class RubyErrorGuard {
  RubyErrorGuard._();

  static const _logKey = 'crash_log_v1';
  static const _maxEntries = 20;

  /// Whether install() has already run (idempotent).
  static bool _installed = false;

  /// GOAL 3 (v0.4.1): pluggable crash reporter. main.dart wires this to
  /// Firebase Crashlytics the moment Firebase.initializeApp succeeds
  /// (boot OR background recovery). Debug builds keep it null - the
  /// local crash log works everywhere, the cloud reporter only ships in
  /// release. Every call is swallowed so a reporter bug can never crash
  /// the app (GOAL 2).
  static void Function(String source, Object error, StackTrace? stack)?
      reporter;

  /// Enable Crashlytics forwarding (release builds). Safe to call
  /// multiple times and safe when Firebase init failed.
  static void enableCrashlytics() {
    reporter = (source, error, stack) {
      try {
        FirebaseCrashlytics.instance
          ..setCrashlyticsCollectionEnabled(true)
          ..recordError(error, stack, information: ['ruby_source: $source']);
      } catch (_) {
        // Crashlytics not ready (offline boot, init failure) - the
        // local crash log already has the entry.
      }
    };
  }

  static void install() {
    if (_installed) return;
    _installed = true;

    // 1) Framework (build/layout/paint) errors.
    final originalFlutterOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      logCrash('flutter', details.exception, details.stack);
      // Still forward to the chain so debug tools keep working.
      originalFlutterOnError?.call(details);
    };

    // 2) Uncaught async errors (futures / streams outside a zone).
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      logCrash('async', error, stack);
      // Returning true = "handled" -> the isolate keeps running and
      // the app never crashes out of the screen the user is on.
      return true;
    };

    // 3) Release UI: a clean grey card instead of the red error screen.
    ErrorWidget.builder = (FlutterErrorDetails details) {
      if (kDebugMode) {
        // Developers keep the loud red screen.
        return ErrorWidget(details.exceptionAsString());
      }
      return const _ErrorCard();
    };
  }

  /// Append one crash line to the local ring buffer (never throws).
  /// v0.4.1: also forwards to the cloud reporter (Crashlytics) when
  /// enableCrashlytics() was called - failures there are ignored.
  static Future<void> logCrash(
      String source, Object error, StackTrace? stack) async {
    appLog('[$source] crash: $error');
    try {
      reporter?.call(source, error, stack);
    } catch (_) {}
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getStringList(_logKey) ?? const <String>[];
      final ts = DateTime.now().toIso8601String();
      final line =
          '$ts | $source | ${error.toString().split('\n').first.takeChars(180)}';
      final next = [...raw, line];
      await sp.setStringList(
        _logKey,
        next.length > _maxEntries ? next.sublist(next.length - _maxEntries) : next,
      );
    } catch (_) {
      // Logging must never crash the logger.
    }
  }

  static Future<List<String>> crashLog() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.getStringList(_logKey) ?? const <String>[];
    } catch (_) {
      return const <String>[];
    }
  }

  static Future<void> clearCrashLog() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_logKey);
    } catch (_) {}
  }

  /// Fire-and-forget async work that must never bubble up: uploads,
  /// share intents, cleanup jobs. Errors land in the crash log only.
  static Future<void> guard(Future<void> Function() body,
      {String where = ''}) async {
    try {
      await body();
    } catch (e, s) {
      logCrash(where.isEmpty ? 'guard' : where, e, s);
    }
  }
}

extension _TakeChars on String {
  String takeChars(int n) => length <= n ? this : substring(0, n);
}

/// The widget ErrorWidget.builder renders in release builds: small,
/// quiet, retryable - never the whole screen.
class _ErrorCard extends StatelessWidget {
  const _ErrorCard();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF3F4F6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.grey.shade600, size: 30),
            const SizedBox(height: 8),
            Text(
              'Something went wrong here.\nThe rest of the app keeps working.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }
}

/// Per-module error boundary. Wrap ANY screen section or widget:
///
///   ErrorBoundary(
///     module: 'Billty photo upload',
///     retryHeight: 120,
///     builder: (context) => BilltySection(...),
///   )
///
/// If `builder` throws synchronously (bad data, a null!, a range
/// check), only this module's card is replaced by a clean retry card -
/// the rest of the screen keeps building. A tap on RETRY rebuilds it.
class ErrorBoundary extends StatefulWidget {
  const ErrorBoundary({
    super.key,
    required this.builder,
    this.module = 'Module',
    this.compact = false,
  });

  final WidgetBuilder builder;
  final String module;

  /// compact = inline row card (for banners/chips); false = full card.
  final bool compact;

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  int _generation = 0;
  Object? _error;

  void _retry() {
    setState(() {
      _error = null;
      _generation++;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _ModuleUnavailableCard(
        module: widget.module,
        compact: widget.compact,
        error: _error,
        onRetry: _retry,
      );
    }
    Widget child;
    try {
      child = widget.builder(context);
    } catch (e, s) {
      // Caught BEFORE it can propagate into the framework and take
      // the whole screen down. Report + remember + show the card.
      RubyErrorGuard.logCrash('boundary:${widget.module}', e, s);
      _error = e;
      return _ModuleUnavailableCard(
        module: widget.module,
        compact: widget.compact,
        error: e,
        onRetry: _retry,
      );
    }
    // Rebuild on every retry generation so a stale child never lingers.
    return KeyedSubtree(
      key: ValueKey('eb_${widget.module}_$_generation'),
      child: child,
    );
  }
}

class _ModuleUnavailableCard extends StatelessWidget {
  const _ModuleUnavailableCard({
    required this.module,
    required this.error,
    required this.onRetry,
    this.compact = false,
  });

  final String module;
  final Object? error;
  final VoidCallback onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Card(
        color: const Color(0xFFF3F4F6),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFFD1D5DB)),
        ),
        child: ListTile(
          dense: true,
          leading: Icon(Icons.settings_suggest_outlined,
              color: Colors.grey.shade600, size: 20),
          title: Text(
            '$module temporarily unavailable',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          trailing: TextButton(onPressed: onRetry, child: const Text('RETRY')),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.settings_suggest_outlined,
                color: Colors.grey.shade600, size: 40),
            const SizedBox(height: 12),
            Text(
              '$module temporarily unavailable',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87),
            ),
            const SizedBox(height: 6),
            Text(
              'Your data is safe. Everything else in the app keeps working.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
