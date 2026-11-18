import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../models/settlement.dart';
import 'db.dart';

/// Single repository for every read/write. All amounts are integer paise.
class Repo {
  Repo._();
  static final Repo instance = Repo._();
  static const _uuid = Uuid();

  Future<Database> get _db => DB.open();

  int _now() => DateTime.now().millisecondsSinceEpoch;

  // ---------------- meta (settings / sync cursor) ----------------

  Future<String?> getMeta(String key) async {
    final db = await _db;
    final rows = await db.rawQuery('SELECT value FROM meta WHERE key = ?', [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setMeta(String key, String value) async {
    final db = await _db;
    await db.insert(
      'meta',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> getPendingDirtyCount() async {
    final db = await _db;
    int n = 0;
    for (final t in ['customers', 'products', 'bills', 'payments']) {
      final r = await db.rawQuery('SELECT COUNT(*) c FROM $t WHERE dirty = 1');
      n += (r.first['c'] as int?) ?? 0;
    }
    return n;
  }

  // ---------------- customers ----------------

  /// Search by name or city; returns rows with computed balance:
  /// balance = opening + billed - payments (+ve = udhar, -ve = advance).
  Future<List<Map<String, Object?>>> searchCustomers(String query) async {
    final db = await _db;
    final q = query.trim();
    final like = '%$q%';
    final rows = await db.rawQuery('''
      SELECT c.id, c.name, c.city, c.phone, c.opening_balance_paise,
             IFNULL(bt.billed, 0) AS billed_paise,
             IFNULL(pt.paid, 0) AS paid_paise,
             c.opening_balance_paise + IFNULL(bt.billed, 0) - IFNULL(pt.paid, 0) AS balance_paise
      FROM customers c
      LEFT JOIN (
        SELECT customer_id, SUM(total_paise) AS billed
        FROM bills WHERE is_deleted = 0 GROUP BY customer_id
      ) bt ON bt.customer_id = c.id
      LEFT JOIN (
        SELECT customer_id, SUM(amount_paise) AS paid
        FROM payments WHERE is_deleted = 0 GROUP BY customer_id
      ) pt ON pt.customer_id = c.id
      WHERE c.is_deleted = 0 AND (c.name LIKE ? OR c.city LIKE ? OR c.phone LIKE ?)
      ORDER BY c.name COLLATE NOCASE
    ''', [like, like, like]);
    return rows;
  }

  Future<Customer?> getCustomer(String id) async {
    final db = await _db;
    final rows = await db.rawQuery('SELECT * FROM customers WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return Customer.fromMap(rows.first);
  }

  Future<void> upsertCustomer(Customer c) async {
    final db = await _db;
    final map = c.copyWith(updatedAt: _now()).toMap();
    await db.insert('customers', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Customer> newCustomer({
    required String name,
    String city = '',
    String phone = '',
    int openingBalancePaise = 0,
  }) async {
    final now = _now();
    final c = Customer(
      id: _uuid.v4(),
      name: name.trim(),
      city: city.trim(),
      phone: phone.trim(),
      openingBalancePaise: openingBalancePaise,
      createdAt: now,
      updatedAt: now,
    );
    final db = await _db;
    await db.insert('customers', c.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    return c;
  }

  Future<void> deleteCustomer(String id) async {
    final db = await _db;
    await db.rawUpdate('UPDATE customers SET is_deleted = 1, updated_at = ?, dirty = 1 WHERE id = ?', [_now(), id]);
  }

  // ---------------- products (inventory) ----------------

  Future<List<Product>> searchProducts(String query) async {
    final db = await _db;
    final q = query.trim().toLowerCase();
    final rows = q.isEmpty
        ? await db.rawQuery("SELECT * FROM products WHERE is_deleted = 0 ORDER BY name COLLATE NOCASE")
        : await db.rawQuery(
            "SELECT * FROM products WHERE is_deleted = 0 AND LOWER(name) LIKE ? ORDER BY name COLLATE NOCASE",
            ['%$q%']);
    return rows.map(Product.fromMap).toList();
  }

  /// Exact (case-insensitive) product by name - used for dedupe on save.
  Future<Product?> productByName(String name) async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT * FROM products WHERE is_deleted = 0 AND LOWER(name) = ? LIMIT 1',
      [name.trim().toLowerCase()],
    );
    if (rows.isEmpty) return null;
    return Product.fromMap(rows.first);
  }

  Future<void> upsertProduct(Product prod) async {
    final db = await _db;
    final map = prod.copyWith(updatedAt: _now()).toMap();
    await db.insert('products', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Product> newProduct({
    required String name,
    String unit = 'Pcs',
    double defaultQty = 1,
    int defaultPricePaise = 0,
    int trackStock = 0,
    double stockQty = 0,
    double lowStock = 0,
  }) async {
    final now = _now();
    final prod = Product(
      id: _uuid.v4(),
      name: name.trim(),
      unit: unit,
      defaultQty: defaultQty,
      defaultPricePaise: defaultPricePaise,
      trackStock: trackStock,
      stockQty: stockQty,
      lowStock: lowStock,
      createdAt: now,
      updatedAt: now,
    );
    await upsertProduct(prod.copyWith(updatedAt: now));
    return prod;
  }

  Future<void> deleteProduct(String id) async {
    final db = await _db;
    await db.rawUpdate('UPDATE products SET is_deleted = 1, updated_at = ?, dirty = 1 WHERE id = ?', [_now(), id]);
  }

  // ---------------- billing ----------------

  /// Saves a bill + its items atomically, records "received now" as a
  /// payment, and adjusts stock for tracked products. Exact math:
  /// each line amount = round(qty * ratePaise), total = sum of line amounts.
  Future<Bill> saveBill({
    required String customerId,
    required String customerName,
    required List<CartLine> lines,
    int paidNowPaise = 0,
    String note = '',
    String payMode = 'cash',
  }) async {
    final db = await _db;
    final now = _now();
    final billId = _uuid.v4();
    final dayKey = _dayKey(now);

    return db.transaction<Bill>((txn) async {
      final noRows = await txn.rawQuery('SELECT COALESCE(MAX(bill_no), 0) + 1 AS next FROM bills');
      final billNo = (noRows.first['next'] as int?) ?? 1;

      int subtotal = 0;
      for (final l in lines) {
        subtotal += l.amountPaise;
      }

      final bill = Bill(
        id: billId,
        billNo: billNo,
        customerId: customerId,
        customerName: customerName,
        billDate: now,
        billDay: dayKey,
        subtotalPaise: subtotal,
        totalPaise: subtotal,
        note: note,
        createdAt: now,
        updatedAt: now,
      );
      await txn.insert('bills', bill.toMap());

      for (final l in lines) {
        final item = BillItem(
          id: _uuid.v4(),
          billId: billId,
          productId: l.productId,
          productName: l.name,
          qty: l.qty,
          ratePaise: l.ratePaise,
          amountPaise: l.amountPaise,
          createdAt: now,
        );
        await txn.insert('bill_items', item.toMap());

        if (l.productId != null) {
          await txn.rawUpdate('''
            UPDATE products SET stock_qty = MAX(0, stock_qty - ?), updated_at = ?, dirty = 1
            WHERE id = ? AND track_stock = 1
          ''', [l.qty, now, l.productId]);
        }
      }

      if (paidNowPaise > 0) {
        final p = Payment(
          id: _uuid.v4(),
          customerId: customerId,
          billId: billId,
          amountPaise: paidNowPaise,
          payDate: now,
          payDay: dayKey,
          mode: payMode,
          note: 'Received with bill #$billNo',
          createdAt: now,
          updatedAt: now,
        );
        await txn.insert('payments', p.toMap());
      }

      return bill;
    });
  }

  Future<(Bill, List<BillItem>)> billWithItems(String billId) async {
    final db = await _db;
    final b = await db.rawQuery('SELECT * FROM bills WHERE id = ?', [billId]);
    if (b.isEmpty) throw StateError('Bill not found');
    final items = await db.rawQuery(
      'SELECT * FROM bill_items WHERE bill_id = ? AND is_deleted = 0 ORDER BY created_at, product_name',
      [billId],
    );
    return (Bill.fromMap(b.first), items.map(BillItem.fromMap).toList());
  }

  /// Bills for a list of local day keys (home screen: today + yesterday).
  Future<Map<String, List<Bill>>> billsForDays(List<String> dayKeys) async {
    final db = await _db;
    if (dayKeys.isEmpty) return {};
    final placeholders = List.filled(dayKeys.length, '?').join(', ');
    final rows = await db.rawQuery(
      'SELECT * FROM bills WHERE is_deleted = 0 AND bill_day IN ($placeholders) ORDER BY bill_date DESC',
      dayKeys,
    );
    final out = <String, List<Bill>>{};
    for (final r in rows) {
      final bill = Bill.fromMap(r);
      out.putIfAbsent(bill.billDay, () => []).add(bill);
    }
    return out;
  }

  Future<Map<String, (int, int)>> dayTotals(List<String> dayKeys) async {
    final db = await _db;
    if (dayKeys.isEmpty) return {};
    final placeholders = List.filled(dayKeys.length, '?').join(', ');
    final rows = await db.rawQuery('''
      SELECT bill_day, COUNT(*) AS cnt, SUM(total_paise) AS total
      FROM bills WHERE is_deleted = 0 AND bill_day IN ($placeholders)
      GROUP BY bill_day
    ''', dayKeys);
    final out = <String, (int, int)>{};
    for (final r in rows) {
      out[r['bill_day'] as String] = ((r['cnt'] as int?) ?? 0, (r['total'] as int?) ?? 0);
    }
    return out;
  }

  Future<void> deleteBill(String billId) async {
    final db = await _db;
    final now = _now();
    await db.transaction((txn) async {
      // restore stock for tracked products
      final items = await txn.rawQuery(
        'SELECT * FROM bill_items WHERE bill_id = ? AND is_deleted = 0',
        [billId],
      );
      for (final it in items) {
        final pid = it['product_id'] as String?;
        final qty = ((it['qty'] ?? 0) as num).toDouble();
        if (pid != null) {
          await txn.rawUpdate('''
            UPDATE products SET stock_qty = stock_qty + ?, updated_at = ?, dirty = 1
            WHERE id = ? AND track_stock = 1
          ''', [qty, now, pid]);
        }
      }
      await txn.rawUpdate('UPDATE bill_items SET is_deleted = 1, updated_at = ?, dirty = 1 WHERE bill_id = ?', [now, billId]);
      await txn.rawUpdate('UPDATE payments SET is_deleted = 1, updated_at = ?, dirty = 1 WHERE bill_id = ?', [now, billId]);
      await txn.rawUpdate('UPDATE bills SET is_deleted = 1, updated_at = ?, dirty = 1 WHERE id = ?', [now, billId]);
    });
  }

  // ---------------- payments ----------------

  Future<Payment> addPayment({
    required String customerId,
    required int amountPaise,
    required String mode,
    required DateTime date,
    String note = '',
    String? billId,
  }) async {
    final db = await _db;
    final now = _now();
    final p = Payment(
      id: _uuid.v4(),
      customerId: customerId,
      billId: billId,
      amountPaise: amountPaise,
      payDate: date.millisecondsSinceEpoch,
      payDay: _dayKey(date.millisecondsSinceEpoch),
      mode: mode,
      note: note,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('payments', p.toMap());
    return p;
  }

  Future<void> deletePayment(String id) async {
    final db = await _db;
    await db.rawUpdate('UPDATE payments SET is_deleted = 1, updated_at = ?, dirty = 1 WHERE id = ?', [_now(), id]);
  }

  // ---------------- ledger ----------------

  /// Full customer account: opening + every bill (+) and payment (-),
  /// chronological with a running balance. Positive running = udhar
  /// (customer owes), negative = advance (shop owes customer).
  Future<(int balancePaise, List<LedgerEntry> entries)> ledger(String customerId) async {
    final db = await _db;
    final custRows = await db.rawQuery(
      'SELECT opening_balance_paise FROM customers WHERE id = ?',
      [customerId],
    );
    final opening = custRows.isEmpty ? 0 : ((custRows.first['opening_balance_paise'] ?? 0) as int);

    final billRows = await db.rawQuery('''
      SELECT id, bill_no, bill_date, total_paise FROM bills
      WHERE customer_id = ? AND is_deleted = 0
    ''', [customerId]);
    final payRows = await db.rawQuery('''
      SELECT id, pay_date, amount_paise, mode, note, is_deleted FROM payments
      WHERE customer_id = ? AND is_deleted = 0
    ''', [customerId]);

    final entries = <LedgerEntry>[];
    int running = opening;

    if (opening != 0) {
      final earliest = [
        ...billRows.map((r) => (r['bill_date'] as int?) ?? 0),
        ...payRows.map((r) => (r['pay_date'] as int?) ?? 0),
      ].fold<int>(DateTime.now().millisecondsSinceEpoch, (a, b) => b < a ? b : a);
      entries.add(LedgerEntry(
        kind: 'opening',
        refId: '',
        title: 'Opening balance',
        date: DateTime.fromMillisecondsSinceEpoch(earliest).subtract(const Duration(seconds: 1)),
        debitPaise: opening > 0 ? opening : 0,
        creditPaise: opening < 0 ? -opening : 0,
        runningBalancePaise: running,
      ));
    }

    final merged = <(int, int, Map<String, Object?>, String)>[];
    for (final r in billRows) {
      merged.add((
        (r['bill_date'] as int?) ?? 0,
        0,
        r,
        'bill',
      ));
    }
    for (final r in payRows) {
      merged.add((
        (r['pay_date'] as int?) ?? 0,
        1,
        r,
        'payment',
      ));
    }
    merged.sort((a, b) {
      final c = a.$1.compareTo(b.$1);
      if (c != 0) return c;
      return a.$2.compareTo(b.$2);
    });

    for (final (_, _, r, kind) in merged) {
      if (kind == 'bill') {
        final total = (r['total_paise'] as int?) ?? 0;
        running += total;
        entries.add(LedgerEntry(
          kind: 'bill',
          refId: r['id'] as String,
          title: 'Bill #${r['bill_no']}',
          date: DateTime.fromMillisecondsSinceEpoch((r['bill_date'] as int?) ?? 0),
          debitPaise: total,
          creditPaise: 0,
          runningBalancePaise: running,
        ));
      } else {
        final amt = (r['amount_paise'] as int?) ?? 0;
        running -= amt;
        final mode = (r['mode'] ?? 'cash') as String;
        final note = (r['note'] ?? '') as String;
        entries.add(LedgerEntry(
          kind: 'payment',
          refId: r['id'] as String,
          title: note.isNotEmpty ? 'Payment ($mode) - $note' : 'Payment received ($mode)',
          date: DateTime.fromMillisecondsSinceEpoch((r['pay_date'] as int?) ?? 0),
          debitPaise: 0,
          creditPaise: amt,
          runningBalancePaise: running,
        ));
      }
    }

    return (running, entries);
  }

  /// FIFO settlement view: which bills are settled / partial / unpaid and
  /// how the customer's payments were applied (oldest first). Pure read -
  /// nothing is stored, so it can never drift out of sync with the books.
  Future<Settlement> settlement(String customerId) async {
    final db = await _db;
    final custRows = await db.rawQuery(
      'SELECT opening_balance_paise FROM customers WHERE id = ?',
      [customerId],
    );
    final opening = custRows.isEmpty
        ? 0
        : ((custRows.first['opening_balance_paise'] ?? 0) as int);
    final billRows = await db.rawQuery(
      'SELECT * FROM bills WHERE customer_id = ? AND is_deleted = 0',
      [customerId],
    );
    final payRows = await db.rawQuery(
      'SELECT * FROM payments WHERE customer_id = ? AND is_deleted = 0',
      [customerId],
    );
    return Settlement.allocate(
      bills: billRows.map(Bill.fromMap).toList(),
      payments: payRows.map(Payment.fromMap).toList(),
      openingBalancePaise: opening,
    );
  }

  // ---------------- reports ----------------

  /// Sales grouped by month inside a day range (inclusive), e.g.
  /// startDay "2026-04-01", endDay "2027-03-31" for an Indian FY.
  Future<List<(String, int, int)>> salesByMonth(String startDay, String endDay) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT substr(bill_day, 1, 7) AS ym, COUNT(*) AS cnt, SUM(total_paise) AS total
      FROM bills
      WHERE is_deleted = 0 AND bill_day >= ? AND bill_day <= ?
      GROUP BY ym ORDER BY ym
    ''', [startDay, endDay]);
    return rows
        .map((r) => (
              r['ym'] as String,
              (r['cnt'] as int?) ?? 0,
              (r['total'] as int?) ?? 0,
            ))
        .toList();
  }

  /// Sales grouped by DAY inside a day range (month drill-down).
  Future<List<(String, int, int)>> salesByDay(String startDay, String endDay) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT bill_day, COUNT(*) AS cnt, SUM(total_paise) AS total
      FROM bills
      WHERE is_deleted = 0 AND bill_day >= ? AND bill_day <= ?
      GROUP BY bill_day ORDER BY bill_day
    ''', [startDay, endDay]);
    return rows
        .map((r) => (
              r['bill_day'] as String,
              (r['cnt'] as int?) ?? 0,
              (r['total'] as int?) ?? 0,
            ))
        .toList();
  }

  /// Customer-wise purchases inside a day range (who bought how much).
  Future<List<Map<String, Object?>>> customerSummaries(String startDay, String endDay) async {
    final db = await _db;
    return db.rawQuery('''
      SELECT c.id, c.name, c.city,
             IFNULL(SUM(b.total_paise), 0) AS period_total,
             MAX(b.bill_date) AS last_bill
      FROM customers c
      JOIN bills b ON b.customer_id = c.id AND b.is_deleted = 0
          AND b.bill_day >= ? AND b.bill_day <= ?
      WHERE c.is_deleted = 0
      GROUP BY c.id
      ORDER BY period_total DESC
    ''', [startDay, endDay]);
  }

  /// Item-wise sales inside a day range (which stock sold how much).
  Future<List<Map<String, Object?>>> topProducts(String startDay, String endDay) async {
    final db = await _db;
    return db.rawQuery('''
      SELECT i.product_name AS name, SUM(i.qty) AS qty, SUM(i.amount_paise) AS amt
      FROM bill_items i
      JOIN bills b ON b.id = i.bill_id
      WHERE b.is_deleted = 0 AND i.is_deleted = 0
            AND b.bill_day >= ? AND b.bill_day <= ?
      GROUP BY LOWER(i.product_name)
      ORDER BY amt DESC
      LIMIT 50
    ''', [startDay, endDay]);
  }


  // ---------------- shop profile ----------------

  Future<Map<String, String>> shopProfile() async {
    final keys = ['shop_name', 'shop_addr', 'shop_phone', 'gstin', 'bill_format'];
    final out = <String, String>{};
    for (final k in keys) {
      out[k] = await getMeta(k) ?? (k == 'bill_format' ? 't80' : '');
    }
    return out;
  }

  Future<void> saveShopProfile(Map<String, String> values) async {
    for (final e in values.entries) {
      await setMeta(e.key, e.value);
    }
  }

  String _dayKey(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}

extension _ProductCopy on Product {
  Product copyWith({int? updatedAt}) => Product(
        id: id,
        name: name,
        unit: unit,
        defaultQty: defaultQty,
        defaultPricePaise: defaultPricePaise,
        trackStock: trackStock,
        stockQty: stockQty,
        lowStock: lowStock,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        isDeleted: isDeleted,
        dirty: 1,
      );
}
