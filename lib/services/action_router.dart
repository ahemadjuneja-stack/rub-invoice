import 'package:flutter/foundation.dart';

/// GOAL 1 (v0.4.1) - ACTION ROUTER WHITELIST.
///
/// Admin-defined shortcut actions from `app_config/live_ui` are strings.
/// A tampered or typo'd config must NEVER be able to make the app open
/// something unexpected, so this router is a STRICT whitelist:
///
///   open:<screen>   -> only the 11 screens listed in [screens]
///   url:<link>      -> only http:// and https:// with a real host
///   dial:<number>   -> only phone digits, +, spaces and dashes
///   none / anything else / a broken value -> [IgnoredRoute]
///
/// parse() never throws; every unknown, malformed or non-whitelisted
/// action is simply [IgnoredRoute] (silently ignored, as spec'd).
sealed class ShortcutRoute {
  const ShortcutRoute();
}

/// `open:<screen>` with a screen that exists in the whitelist.
class OpenScreenRoute extends ShortcutRoute {
  final String screen;
  const OpenScreenRoute(this.screen);
}

/// `url:<link>` with an http(s) URL only.
class UrlRoute extends ShortcutRoute {
  final String url;
  const UrlRoute(this.url);
}

/// `dial:<number>` with a phone-number-safe payload.
class DialRoute extends ShortcutRoute {
  final String number;
  const DialRoute(this.number);
}

/// Not on the whitelist (or malformed) -> ignore, never navigate.
class IgnoredRoute extends ShortcutRoute {
  const IgnoredRoute();
}

class ActionRouter {
  ActionRouter._();

  /// The ONLY screens an admin shortcut may open. Anything else in an
  /// `open:` action is ignored. Mirrors the in-app menu exactly.
  static const Set<String> screens = {
    'billing', 'customers', 'ledger', 'inventory', 'purchases',
    'returns', 'accounts', 'backup', 'sync', 'settings', 'pdfformat',
  };

  /// Parse an admin action string into a whitelisted route.
  /// Case-insensitive on the scheme prefix (`OPEN:billing` works too);
  /// the payload keeps its original case where it matters (URLs).
  static ShortcutRoute parse(String raw) {
    final action = raw.trim();
    if (action.isEmpty) return const IgnoredRoute();
    // `lower` is only used for prefix DETECTION; the payload is always
    // sliced from the ORIGINAL `action` at fixed indices (5/4/5), so a
    // toLowerCase length change on exotic unicode can never corrupt it.
    final lower = action.toLowerCase();

    if (lower.startsWith('open:')) {
      final screen = action.substring(5).trim().toLowerCase();
      if (screens.contains(screen)) return OpenScreenRoute(screen);
      return const IgnoredRoute();
    }

    if (lower.startsWith('url:')) {
      final url = action.substring(4).trim();
      final uri = Uri.tryParse(url);
      // Strict scheme + host check: `url:ftp://x`, `url:file:///...`,
      // `url:javascript:...` and empty hosts are all rejected here -
      // only http(s) links with a real domain survive.
      if (uri != null &&
          (uri.scheme == 'https' || uri.scheme == 'http') &&
          uri.host.isNotEmpty) {
        return UrlRoute(url);
      }
      return const IgnoredRoute();
    }

    if (lower.startsWith('dial:')) {
      final tel = action.substring(5).trim();
      // Phone numbers only: digits, +, spaces, dashes, parentheses.
      // Blocks `dial:https://...` style abuse; the URI we launch is
      // always built as scheme 'tel' by the caller.
      final safe = RegExp(r'^[0-9+\-() ]{3,20}$').hasMatch(tel);
      if (safe) return DialRoute(tel);
      return const IgnoredRoute();
    }

    // Unknown scheme (`intent:`, `market:`, garbage, `none`) -> ignored.
    return const IgnoredRoute();
  }

  /// Convenience for tests + UI: is this action allowed at all?
  static bool isAllowed(String raw) => parse(raw) is! IgnoredRoute;
}

/// Small pure helper used by the parser and its tests: keep at most
/// [max] visible shortcut rows so a runaway admin config can never
/// flood the menu tab.
List<T> capList<T>(List<T> rows, {int max = 12}) {
  assert(max > 0);
  if (rows.length <= max) return rows;
  debugPrint('action_router: shortcut list capped to $max');
  return rows.sublist(0, max);
}
