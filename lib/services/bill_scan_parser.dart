import '../models/models.dart';

/// Scan of one paper purchase bill: everything the purchase form can
/// pre-fill. AI suggests - the owner reviews and saves.
class BillScanResult {
  final String partyBillNo;
  final List<PurchaseCartLine> lines;
  final int parcelPaise; // parcel / freight / transport charge found
  final int totalPaise; // grand total printed on the bill (best effort)

  BillScanResult({
    required this.partyBillNo,
    required this.lines,
    required this.parcelPaise,
    required this.totalPaise,
  });
}

/// Bill-shaped parser for on-device OCR output (pure Dart, zero plugin
/// dependencies - fully unit-tested in test/bill_scan_parser_test.dart).
///
/// Parsing printed shop bills is inherently fuzzy: the parser is
/// deliberately conservative - it only fills what it is confident about
/// and the purchase form stays fully editable, so a wrong read is fixed
/// by the user in one tap before saving.
class BillScanParser {
  BillScanParser._();

  /// Numbers found in a line (handles 1,250.00 / 12,50 / ₹-prefixed).
  static List<double> numbersIn(String line) {
    final cleaned = line.replaceAll(RegExp(r'[₹]'), ' ');
    final matches =
        RegExp(r'(\d+(?:[,\d]*)?(?:\.\d+)?)').allMatches(cleaned);
    return matches
        .map((m) => double.tryParse(m.group(1)!.replaceAll(',', '')) ?? 0)
        .where((n) => n >= 0)
        .toList();
  }

  /// Parses the OCR text lines of a paper bill into the scan result.
  static BillScanResult parse(List<String> rawLines) {
    final lines = rawLines
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList(growable: false);

    String partyBillNo = '';
    int parcelPaise = 0;
    int totalPaise = 0;
    final items = <PurchaseCartLine>[];

    final billNoRe = RegExp(
        r'(bill|invoice|memo)\s*(no|number)?[\s\.:#-]*([A-Za-z0-9][A-Za-z0-9\/\-]{0,20})',
        caseSensitive: false);
    final parcelRe = RegExp(
        r'(parcel|freight|transport|delivery|courier|postage|carriage)',
        caseSensitive: false);
    final totalRe = RegExp(
        r'(grand\s*total|net\s*amount|net\s*total|total\s*amount|round\s*off|total)',
        caseSensitive: false);

    for (final l in lines) {
      final lower = l.toLowerCase();

      // ---- party bill number (first match wins) ----
      if (partyBillNo.isEmpty) {
        final m = billNoRe.firstMatch(l);
        if (m != null) {
          final no = (m.group(3) ?? '').trim();
          if (no.isNotEmpty &&
              !lower.contains('phone') &&
              !lower.contains('mobile') &&
              !lower.contains('gst') &&
              !lower.contains('date')) {
            partyBillNo = no;
          }
        }
      }

      // ---- parcel / freight charge ----
      if (parcelRe.hasMatch(lower)) {
        final nums = numbersIn(l);
        if (nums.isNotEmpty) {
          final v = nums.last;
          if (v > 0 && v < 100000) {
            parcelPaise = (v * 100).round();
          }
        }
      }

      // ---- printed grand total (keep the largest seen) ----
      if (totalRe.hasMatch(lower) && !parcelRe.hasMatch(lower)) {
        final nums = numbersIn(l);
        if (nums.isNotEmpty) {
          final paise = (nums.last * 100).round();
          if (paise > totalPaise) totalPaise = paise;
        }
      }

      // ---- item lines: name ... qty rate amount [gst%] ----
      // Two shapes:
      //   "COMPACT 1,250.00 x 2 2,500.00"  (explicit x between rate/qty)
      //   "EARING PAIR 2 45 90 18%"        (plain tail: qty rate amount)
      final nums = numbersIn(l);
      double? gst;
      final gstM = RegExp(r'(\d{1,2}(?:\.\d+)?)\s*%').firstMatch(l);
      if (gstM != null) {
        final g = double.tryParse(gstM.group(1)!);
        if (g != null && g >= 0 && g <= 28) gst = g;
      }

      (double, double, double)? triple;
      final xMatch = _explicitX(l);
      if (xMatch != null) {
        triple = xMatch;
      } else if (nums.length >= 3) {
        var tail = nums;
        if (gst != null && tail.isNotEmpty && tail.last == gst) {
          tail = tail.sublist(0, tail.length - 1);
        }
        if (tail.length >= 3) {
          triple = (
            tail[tail.length - 3], // qty
            tail[tail.length - 2], // rate
            tail.last,             // amount
          );
        }
      }

      if (triple != null) {
        final (qty, rate, amount) = triple;
        if (qty > 0 && rate > 0 && amount > 0) {
          // Plausibility: amount ~= qty*rate (5% tolerance).
          final expected = qty * rate;
          if ((expected - amount).abs() <= expected * 0.05) {
            final name = _nameBeforeNumbers(l);
            if (name.length >= 2 && name.length <= 60) {
              items.add(PurchaseCartLine(
                name: name,
                qty: qty,
                ratePaise: (rate * 100).round(),
                gstPercent: gst ?? 0,
              ));
            }
          }
        }
      }
    }

    return BillScanResult(
      partyBillNo: partyBillNo,
      lines: items,
      parcelPaise: parcelPaise,
      totalPaise: totalPaise,
    );
  }

  /// Detects the explicit "x" shape: "COMPACT 1,250.00 x 2 2,500.00" ->
  /// (qty=2, rate=1250, amount=2500). Returns null when the line does
  /// not carry a standalone x token.
  static (double, double, double)? _explicitX(String line) {
    final words = line
        .replaceAll(RegExp(r'[₹|]+'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    for (var k = 0; k < words.length; k++) {
      final w = words[k].toLowerCase().replaceAll('.', '');
      if (w != 'x') continue;
      if (k >= 1 && k + 1 < words.length) {
        final rate = double.tryParse(words[k - 1].replaceAll(',', ''));
        final qty = double.tryParse(words[k + 1].replaceAll(',', ''));
        final numsAfter = numbersIn(words.sublist(k + 1).join(' '));
        if (rate != null && qty != null && numsAfter.isNotEmpty) {
          final amount = numsAfter.last;
          if (amount != rate && amount != qty) {
            return (qty, rate, amount);
          }
        }
      }
    }
    return null;
  }

  /// "EARING PAIR 2 45 90" -> "EARING PAIR"; keeps letter words only.
  static String _nameBeforeNumbers(String line) {
    final words = line
        .replaceAll(RegExp(r'[₹|]+'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final nameWords = <String>[];
    for (final w in words) {
      final isNumber = RegExp(r'^[\d,]+(\.\d+)?%?$').hasMatch(w);
      if (isNumber && nameWords.isNotEmpty) break;
      if (w.contains(RegExp(r'[A-Za-z\u0900-\u097F]'))) {
        nameWords.add(w);
      }
    }
    return nameWords.join(' ').trim();
  }
}
