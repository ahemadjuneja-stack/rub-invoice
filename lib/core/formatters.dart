import 'package:intl/intl.dart';

/// Money helpers. IMPORTANT: every amount in the database is an INTEGER
/// number of paise. No floating point is ever stored or summed, so the
/// ledger is mathematically exact (the "1% bhi galati nahi" rule).
class Money {
  Money._();

  /// Converts a rupees text field ("1250", "1250.5", "1,250.50") to paise.
  static int parsePaise(String input) {
    var s = input.trim().replaceAll(RegExp(r'[₹,\s]'), '');
    if (s.isEmpty) return 0;
    final v = double.tryParse(s);
    if (v == null || v < 0) return 0;
    return (v * 100).round();
  }

  /// Formats paise as Indian-grouped rupees, e.g. 1250000 -> "₹ 12,500".
  static String fmt(int paise, {bool withSymbol = true}) {
    final neg = paise < 0;
    final a = paise.abs();
    final rupees = a ~/ 100;
    final ps = (a % 100).toString().padLeft(2, '0');
    final body = '${_group(rupees.toString())}.$ps';
    return '${neg ? "-" : ""}${withSymbol ? "\u{20B9} " : ""}$body';
  }

  /// Whole rupees only (used to echo a paise value back into a rate field).
  static String fmtRupeesInput(int paise) {
    if (paise % 100 == 0) return (paise ~/ 100).toString();
    final v = paise / 100;
    return v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  static String _group(String digits) {
    if (digits.length <= 3) return digits;
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '${parts.join(",")},$last3';
  }
}

/// Date helpers. Bills carry both an epoch timestamp and a local-day key
/// ("2026-11-19") so that day/month grouping is always in the shop's own
/// timezone, never UTC.
class Dt {
  Dt._();

  static const List<String> months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime fromDayKey(String k) {
    final p = k.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  static String ymOf(String dayKey) => dayKey.substring(0, 7);

  static DateTime todayStart() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static String todayKey() => dayKey(DateTime.now());

  static String yesterdayKey() => dayKey(todayStart().subtract(const Duration(days: 1)));

  /// Section label for a day key: Today / Yesterday / 19 Nov.
  static String labelFor(String key) {
    final t = todayKey();
    final y = yesterdayKey();
    if (key == t) return 'Today';
    if (key == y) return 'Yesterday';
    final d = fromDayKey(key);
    return '${d.day} ${months[d.month - 1]}';
  }

  static String fmtDayKey(String key) {
    final d = fromDayKey(key);
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  static String fmtTime(DateTime d) => DateFormat('hh:mm a').format(d);

  static String fmtDateTime(DateTime d) => DateFormat('d MMM yyyy, hh:mm a').format(d);

  static String fmtDate(DateTime d) => DateFormat('d MMM yyyy').format(d);
}
