import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// An in-progress bill saved automatically (WhatsApp-style draft).
///
/// One global draft slot: whenever the billing screen is left (back
/// press, app minimised, incoming call) with a non-empty cart, the cart
/// is written here; it is cleared when the bill is saved or the cart is
/// emptied. On the next billing session for the same customer the cart
/// is restored exactly where it was - the bill never gets lost.
class BillDraft {
  final String customerId;
  final String customerName;
  final List<CartLine> lines;
  final String payMode; // 'udhar' | 'jama'
  final int paidNowPaise;
  final int billDateMs; // chosen bill date (Miracle-style backdating)
  final int savedAt; // epoch ms

  BillDraft({
    required this.customerId,
    required this.customerName,
    required this.lines,
    this.payMode = 'udhar',
    this.paidNowPaise = 0,
    this.billDateMs = 0,
    required this.savedAt,
  });

  int get totalPaise => lines.fold(0, (s, l) => s + l.amountPaise);

  Map<String, Object?> toMap() => {
        'customer_id': customerId,
        'customer_name': customerName,
        'pay_mode': payMode,
        'paid_now_paise': paidNowPaise,
        'bill_date_ms': billDateMs,
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

  static BillDraft? fromMap(Map<String, Object?> m) {
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
    return BillDraft(
      customerId: cid,
      customerName: (m['customer_name'] ?? '') as String,
      lines: lines,
      payMode: (m['pay_mode'] ?? 'udhar') as String,
      paidNowPaise: ((m['paid_now_paise'] ?? 0) as num).toInt(),
      billDateMs: ((m['bill_date_ms'] ?? 0) as num).toInt(),
      savedAt: ((m['saved_at'] ?? 0) as num).toInt(),
    );
  }
}

class BillDraftService {
  BillDraftService._();
  static final BillDraftService instance = BillDraftService._();

  static const _k = 'bill_draft_v1';

  Future<BillDraft?> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_k);
      if (raw == null || raw.isEmpty) return null;
      return BillDraft.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(BillDraft draft) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_k, jsonEncode(draft.toMap()));
    } catch (_) {
      // draft save must never crash the billing screen
    }
  }

  Future<void> clear() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_k);
    } catch (_) {}
  }
}
