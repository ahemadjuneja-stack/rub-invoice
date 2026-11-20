/// Input sanitization for every free-text field the user can type
/// (security hardening, XSS defence in depth).
///
/// Ruby Invoice text travels to three renderers that must never execute
/// anything the user typed:
///   * the Flutter app itself (safe - it draws strings as text),
///   * generated PDFs (safe - pdf draws raw glyphs),
///   * the Ruby Key admin PWA (renders user fields into HTML; app.js
///     escapes on output, but the input must be clean anyway) and any
///     future web surface.
///
/// So every stored string is cleaned ONCE at the single write choke
/// point (Repo.* + AccessService registration) instead of at every
/// screen: HTML/script delimiters are stripped, control characters are
/// removed, whitespace is collapsed and the length is capped - all
/// without touching normal Hindi/English/Gujarati text, digits,
/// punctuation or emoji.
library;

class Sanitize {
  Sanitize._();

  /// Characters that make it possible to smuggle markup into any HTML
  /// renderer. Normal shop/customer text never contains them.
  static final RegExp _htmlDelimiters = RegExp(r'[<>]');

  /// Control characters (except nothing - tabs are collapsed later too).
  /// 0x00-0x1F + 0x7F: never legitimate in these fields.
  static final RegExp _controlChars = RegExp('[\x00-\x1F\x7F]');

  /// Runs of whitespace/newlines collapse to one space; multi-line
  /// addresses therefore still read naturally after cleaning.
  static final RegExp _whitespace = RegExp(r'\s+');

  /// Clean a single-line field (names, mobile, city, GST, PIN, notes).
  static String text(Object? raw, {int maxLen = 120}) =>
      _clean(raw, maxLen: maxLen);

  /// Clean a multi-line field (full addresses keep their line breaks).
  static String multiline(Object? raw, {int maxLen = 400}) {
    final s = (raw?.toString() ?? '')
        .replaceAll(_htmlDelimiters, '')
        .replaceAll(_controlChars, ' ')
        .trim();
    final lines = s
        .split(RegExp(r'\n+'))
        .map((l) => l.replaceAll(_whitespace, ' ').trim())
        .where((l) => l.isNotEmpty)
        .take(6);
    final out = lines.join('\n');
    return out.length > maxLen ? out.substring(0, maxLen).trim() : out;
  }

  /// Digits only (mobile / OTP style fields).
  static String digits(Object? raw, {int maxLen = 10}) {
    final d = (raw?.toString() ?? '').replaceAll(RegExp(r'\D'), '');
    return d.length > maxLen ? d.substring(0, maxLen) : d;
  }

  static String _clean(Object? raw, {required int maxLen}) {
    final s = (raw?.toString() ?? '')
        .replaceAll(_htmlDelimiters, '')
        .replaceAll(_controlChars, ' ')
        .replaceAll(_whitespace, ' ')
        .trim();
    return s.length > maxLen ? s.substring(0, maxLen).trim() : s;
  }
}
