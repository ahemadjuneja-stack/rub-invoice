import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// An in-progress SALES RETURN saved automatically (same idea as the
/// billing draft - the return must never be lost on back press, phone
/// call or app switch).
///
/// One global draft slot: the return entry screen writes the cart here
/// whenever it is left with non-empty lines; it is cleared when the
/// return is saved or the lines are emptied. The Sales Return list
/// shows a "Resume unfinished return" banner exactly like the billing
/// home screen does for bills.
class ReturnDraft {
  final String customerId;
  final String customerName;
  final List<CartLine> lines;
  final int returnDateMs; // chosen return date
  final String note;
  final int savedAt; // epoch ms

  ReturnDraft({
    required this.customerId,
    required this.customerName,
    required this.lines,
    this.returnDateMs = 0,
    this.note = '',
    required this.savedAt,
  });

  int get totalPaise => lines.fold(0, (s, l) => s + l.amountPaise);

  Map<String, Object?> toMap() => {
        'customer_id': customerId,
        'customer_name': customerName,
        'return_date_ms': returnDateMs,
        'note': note,
        'saved_at': savedAt,
        'lines': [
          for (final l in lines)
            {
              'product_id': l.productId,
              'name': l.name,
              'qty': l.qty,
              'rate_paise': l.ratePaise,
            }
        ],
      };

  static ReturnDraft? fromMap(Map<String, Object?> m) {
    final cid = (m['customer_id'] ?? '') as String;
    if (cid.isEmpty) return null;
    final raw = (m['lines'] as List?) ?? const [];
    final lines = <CartLine>[];
    for (final e in raw) {
      if (e is! Map) continue;
      lines.add(CartLine(
        productId: e['product_id'] as String?,
        name: (e['name'] ?? '') as String,
        qty: ((e['qty'] ?? 0) as num).toDouble(),
        ratePaise: ((e['rate_paise'] ?? 0) as num).toInt(),
      ));
    }
    return ReturnDraft(
      customerId: cid,
      customerName: (m['customer_name'] ?? '') as String,
      lines: lines,
      returnDateMs: ((m['return_date_ms'] ?? 0) as num).toInt(),
      note: (m['note'] ?? '') as String,
      savedAt: ((m['saved_at'] ?? 0) as num).toInt(),
    );
  }
}

class ReturnDraftService {
  ReturnDraftService._();
  static final ReturnDraftService instance = ReturnDraftService._();

  static const _k = 'sales_return_draft_v1';

  Future<ReturnDraft?> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_k);
      if (raw == null || raw.isEmpty) return null;
      return ReturnDraft.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(ReturnDraft draft) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_k, jsonEncode(draft.toMap()));
    } catch (_) {
      // draft save must never crash the return screen
    }
  }

  Future<void> clear() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_k);
    } catch (_) {}
  }
}
