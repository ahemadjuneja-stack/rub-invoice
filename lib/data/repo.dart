import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../core/sanitize.dart';
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
    for (final t in ['customers', 'products', 'bills', 'payments', 'purchases']) {
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
      SELECT c.id, c.name, c.shop_name, c.city, c.phone, c.opening_balance_paise,
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
    // Same choke-point cleaning as newCustomer (edit path).
    final map = c.copyWith(updatedAt: _now()).toMap();
    map['name'] = Sanitize.text(c.name);
    map['shop_name'] = Sanitize.text(c.shopName);
    map['city'] = Sanitize.text(c.city);
    map['phone'] = Sanitize.digits(c.phone);
    map['address'] = Sanitize.multiline(c.address);
    await db.insert('customers', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Customer> newCustomer({
    required String name,
    String shopName = '',
    String city = '',
    String phone = '',
    String address = '',
    int openingBalancePaise = 0,
  }) async {
    final now = _now();
    final c = Customer(
      id: _uuid.v4(),
      // XSS hardening: user-typed text is cleaned at the single write
      // choke point (Repo), so no screen can forget it.
      name: Sanitize.text(name),
      shopName: Sanitize.text(shopName),
      city: Sanitize.text(city),
      phone: Sanitize.digits(phone),
      address: Sanitize.multiline(address),
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

  /// City snapshot for the given customer ids (home bill tiles).
  Future<Map<String, String>> citiesFor(Iterable<String> ids) async {
    final list = ids.toSet().toList();
    if (list.isEmpty) return {};
    final placeholders = List.filled(list.length, '?').join(', ');
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT id, city FROM customers WHERE id IN ($placeholders)',
      list,
    );
    return {for (final r in rows) r['id'] as String: (r['city'] ?? '') as String};
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

  // ---------------- purchases (maal kharida) ----------------

  /// The invoice number the NEXT saved purchase will get. Mirrors
  /// nextBillNo(): MAX + 1 across all rows, deleted ones included, so a
  /// number is never reused.
  Future<int> nextPurchaseNo() async {
    final db = await _db;
    final rows = await db.rawQuery('SELECT COALESCE(MAX(purchase_no), 0) + 1 AS next FROM purchases');
    return (rows.first['next'] as int?) ?? 1;
  }

  /// Saves one purchase invoice. [date] may be back-dated like bills.
  /// [photoPath] is a local file copied into the app's documents folder
  /// (picture of the paper bill, clicked or picked from gallery).
  Future<Purchase> savePurchase({
    required String supplierName,
    String supplierPhone = '',
    required int amountPaise,
    String note = '',
    String photoPath = '',
    DateTime? date,
  }) async {
    final db = await _db;
    final now = _now();
    final chosen = date ?? DateTime.now();
    final ms = chosen.millisecondsSinceEpoch;

    final noRows = await db.rawQuery('SELECT COALESCE(MAX(purchase_no), 0) + 1 AS next FROM purchases');
    final no = (noRows.first['next'] as int?) ?? 1;

    final purchase = Purchase(
      id: _uuid.v4(),
      purchaseNo: no,
      supplierName: Sanitize.text(supplierName),
      supplierPhone: Sanitize.digits(supplierPhone),
      amountPaise: amountPaise,
      note: Sanitize.text(note),
      photoPath: photoPath,
      purchaseDate: ms,
      purchaseDay: _dayKey(ms),
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('purchases', purchase.toMap());
    return purchase;
  }

  /// All purchase invoices, newest date first.
  Future<List<Purchase>> purchases() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT * FROM purchases WHERE is_deleted = 0 ORDER BY purchase_date DESC, created_at DESC',
    );
    return rows.map(Purchase.fromMap).toList();
  }

  Future<void> deletePurchase(String id) async {
    final db = await _db;
    await db.rawUpdate('UPDATE purchases SET is_deleted = 1, updated_at = ?, dirty = 1 WHERE id = ?', [_now(), id]);
  }

  // ---------------- billing ----------------

  /// The invoice number the NEXT saved bill will get (shown in the
  /// billing header before saving). Consistent with saveBill(), which
  /// uses MAX(bill_no) + 1 across ALL bills (deleted ones too, so a
  /// number is never reused).
  Future<int> nextBillNo() async {
    final db = await _db;
    final rows = await db.rawQuery('SELECT COALESCE(MAX(bill_no), 0) + 1 AS next FROM bills');
    return (rows.first['next'] as int?) ?? 1;
  }

  /// Saves a bill + its items atomically, records "received now" as a
  /// payment, and adjusts stock for tracked products. Exact math:
  /// each line amount = round(qty * ratePaise), total = sum of line amounts.
  /// [billDate] lets the user back-date / pre-date a bill (Miracle-style);
  /// the received-now payment inherits the same date so the ledger stays
  /// in chronological order.
  Future<Bill> saveBill({
    required String customerId,
    required String customerName,
    required List<CartLine> lines,
    int paidNowPaise = 0,
    String note = '',
    String payMode = 'cash',
    DateTime? billDate,
  }) async {
    final db = await _db;
    final now = _now();
    final billId = _uuid.v4();
    final chosen = billDate ?? DateTime.now();
    final billMs = chosen.millisecondsSinceEpoch;
    final dayKey = _dayKey(billMs);

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
        customerName: Sanitize.text(customerName),
        billDate: billMs,
        billDay: dayKey,
        subtotalPaise: subtotal,
        totalPaise: subtotal,
        note: Sanitize.text(note),
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
          payDate: billMs,
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

  /// Total "received now" recorded with this bill (its linked payments).
  /// Used when the bill is opened for editing so the received amount
  /// comes back exactly as it was saved.
  Future<int> paidWithBill(String billId) async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(amount_paise), 0) AS paid FROM payments '
      'WHERE bill_id = ? AND is_deleted = 0',
      [billId],
    );
    return (rows.first['paid'] as int?) ?? 0;
  }

  /// Edits an already-saved bill (the pen icon on the bill view):
  /// same bill id and invoice number, items replaced, total recomputed,
  /// stock re-adjusted (old restored, new deducted) and the "received
  /// now" payment replaced. The ledger is derived from bills + payments,
  /// so it is automatically correct after the edit. [billDate] may move
  /// the bill to another day, time of day preserved.
  Future<Bill> updateBill({
    required Bill existing,
    required List<CartLine> lines,
    int paidNowPaise = 0,
    String note = '',
    DateTime? billDate,
  }) async {
    final db = await _db;
    final now = _now();
    final chosen =
        billDate ?? DateTime.fromMillisecondsSinceEpoch(existing.billDate);
    final billMs = chosen.millisecondsSinceEpoch;
    final dayKey = _dayKey(billMs);

    return db.transaction<Bill>((txn) async {
      // restore stock for the OLD items, then retire them (tombstones
      // keep the sync history intact)
      final oldItems = await txn.rawQuery(
        'SELECT * FROM bill_items WHERE bill_id = ? AND is_deleted = 0',
        [existing.id],
      );
      for (final it in oldItems) {
        final pid = it['product_id'] as String?;
        final qty = ((it['qty'] ?? 0) as num).toDouble();
        if (pid != null) {
          await txn.rawUpdate('''
            UPDATE products SET stock_qty = stock_qty + ?, updated_at = ?, dirty = 1
            WHERE id = ? AND track_stock = 1
          ''', [qty, now, pid]);
        }
      }
      await txn.rawUpdate(
        'UPDATE bill_items SET is_deleted = 1, updated_at = ?, dirty = 1 WHERE bill_id = ?',
        [now, existing.id],
      );

      int subtotal = 0;
      for (final l in lines) {
        subtotal += l.amountPaise;
      }

      await txn.update(
        'bills',
        {
          'bill_date': billMs,
          'bill_day': dayKey,
          'subtotal_paise': subtotal,
          'total_paise': subtotal,
          'note': note.isNotEmpty ? note : existing.note,
          'updated_at': now,
          'dirty': 1,
        },
        where: 'id = ?',
        whereArgs: [existing.id],
      );

      for (final l in lines) {
        final item = BillItem(
          id: _uuid.v4(),
          billId: existing.id,
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

      // replace the "received with bill" payment so the ledger and the
      // customer balance follow the edited amount
      await txn.rawUpdate(
        'UPDATE payments SET is_deleted = 1, updated_at = ?, dirty = 1 WHERE bill_id = ?',
        [now, existing.id],
      );
      if (paidNowPaise > 0) {
        final p = Payment(
          id: _uuid.v4(),
          customerId: existing.customerId,
          billId: existing.id,
          amountPaise: paidNowPaise,
          payDate: billMs,
          payDay: dayKey,
          mode: 'cash',
          note: 'Received with bill #${existing.billNo}',
          createdAt: now,
          updatedAt: now,
        );
        await txn.insert('payments', p.toMap());
      }

      return Bill(
        id: existing.id,
        billNo: existing.billNo,
        customerId: existing.customerId,
        customerName: existing.customerName,
        billDate: billMs,
        billDay: dayKey,
        subtotalPaise: subtotal,
        discountPaise: existing.discountPaise,
        totalPaise: subtotal,
        note: note.isNotEmpty ? note : existing.note,
        createdAt: existing.createdAt,
        updatedAt: now,
        isDeleted: 0,
        dirty: 1,
      );
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
  /// Newest first: the bill saved most recently always lands on top,
  /// even when several share the same chosen date (e.g. midnight ties).
  Future<Map<String, List<Bill>>> billsForDays(List<String> dayKeys) async {
    final db = await _db;
    if (dayKeys.isEmpty) return {};
    final placeholders = List.filled(dayKeys.length, '?').join(', ');
    final rows = await db.rawQuery(
      'SELECT * FROM bills WHERE is_deleted = 0 AND bill_day IN ($placeholders) '
      'ORDER BY bill_date DESC, created_at DESC, bill_no DESC',
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

  // ---------------- accounts (hisab) ----------------

  /// Net udhaar of ALL customers right now: opening balances + every
  /// bill - every payment (soft-deleted rows excluded).
  Future<int> totalUdhaar() async {
    final db = await _db;
    final r = await db.rawQuery('''
      SELECT
        (SELECT COALESCE(SUM(opening_balance_paise), 0) FROM customers WHERE is_deleted = 0) +
        (SELECT COALESCE(SUM(total_paise), 0) FROM bills WHERE is_deleted = 0) -
        (SELECT COALESCE(SUM(amount_paise), 0) FROM payments WHERE is_deleted = 0)
        AS bal
    ''');
    return ((r.first['bal'] as num?) ?? 0).toInt();
  }

  /// All-time purchases total (every non-deleted purchase invoice).
  Future<int> totalPurchases() async {
    final db = await _db;
    final r = await db.rawQuery(
      'SELECT COALESCE(SUM(amount_paise), 0) AS t FROM purchases WHERE is_deleted = 0',
    );
    return ((r.first['t'] as num?) ?? 0).toInt();
  }

  /// Money IN (payments received) and money OUT (purchase invoices)
  /// between [startMs, endMs) - end exclusive. Feeds the month and
  /// financial-year aaya / gaya totals on the Accounts screen.
  Future<(int moneyIn, int moneyOut)> inOutForRange(int startMs, int endMs) async {
    final db = await _db;
    final pay = await db.rawQuery(
      'SELECT COALESCE(SUM(amount_paise), 0) AS t FROM payments '
      'WHERE is_deleted = 0 AND pay_date >= ? AND pay_date < ?',
      [startMs, endMs],
    );
    final pur = await db.rawQuery(
      'SELECT COALESCE(SUM(amount_paise), 0) AS t FROM purchases '
      'WHERE is_deleted = 0 AND purchase_date >= ? AND purchase_date < ?',
      [startMs, endMs],
    );
    return (
      ((pay.first['t'] as num?) ?? 0).toInt(),
      ((pur.first['t'] as num?) ?? 0).toInt(),
    );
  }

  /// Earliest transaction timestamp across bills, payments and purchases
  /// (0 when the shop has no data yet). Year / FY lists start from this,
  /// so an old year shows up only after old-dated data was entered.
  Future<int> firstTransactionMs() async {
    final db = await _db;
    final r = await db.rawQuery('''
      SELECT MIN(m) AS t FROM (
        SELECT MIN(bill_date) AS m FROM bills WHERE is_deleted = 0
        UNION ALL
        SELECT MIN(pay_date) AS m FROM payments WHERE is_deleted = 0
        UNION ALL
        SELECT MIN(purchase_date) AS m FROM purchases WHERE is_deleted = 0
      )
    ''');
    return ((r.first['t'] as num?) ?? 0).toInt();
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

  // ---------------- delivery (billty) details ----------------

  /// How long a billty (lorry receipt) photo stays on the phone before
  /// it deletes itself. 45 days, Miracle-style proof retention.
  static const billtyRetentionDays = 45;

  /// The delivery details saved for one bill (null when none yet).
  Future<BillDispatch?> dispatchFor(String billId) async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT * FROM bill_dispatch WHERE bill_id = ? AND is_deleted = 0 LIMIT 1',
      [billId],
    );
    if (rows.isEmpty) return null;
    return BillDispatch.fromMap(rows.first);
  }

  /// Saves (insert or update) the delivery details of one bill.
  /// [billtyPath] is the EFFECTIVE photo path: '' clears a photo, the
  /// same old path keeps it untouched, a new path replaces it (the old
  /// file is deleted from disk). The 45-day retention clock restarts
  /// whenever a new photo is saved.
  Future<BillDispatch> saveDispatch({
    required String billId,
    required String mode,
    String note = '',
    String billtyPath = '',
  }) async {
    final db = await _db;
    final now = _now();
    final rows = await db.rawQuery(
      'SELECT * FROM bill_dispatch WHERE bill_id = ? AND is_deleted = 0 LIMIT 1',
      [billId],
    );
    if (rows.isNotEmpty) {
      final old = BillDispatch.fromMap(rows.first);
      if (old.billtyPath != billtyPath) _deletePhotoFile(old.billtyPath);
      final d = BillDispatch(
        id: old.id,
        billId: billId,
        mode: mode,
        billtyPath: billtyPath,
        billtyAt: billtyPath.isEmpty
            ? 0
            : (old.billtyPath == billtyPath ? old.billtyAt : now),
        note: Sanitize.text(note),
        createdAt: old.createdAt,
        updatedAt: now,
        isDeleted: 0,
        dirty: 1,
      );
      await db.update('bill_dispatch', d.toMap(), where: 'id = ?', whereArgs: [old.id]);
      return d;
    }
    final d = BillDispatch(
      id: _uuid.v4(),
      billId: billId,
      mode: mode,
      billtyPath: billtyPath,
      billtyAt: billtyPath.isEmpty ? 0 : now,
      note: Sanitize.text(note),
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('bill_dispatch', d.toMap());
    return d;
  }

  /// Deletes every billty photo older than 45 days from disk and clears
  /// its path (the mode + note stay as the bill's history). Called once
  /// per app start - fire-and-forget, boot never waits on it.
  Future<int> cleanExpiredBillties() async {
    final db = await _db;
    final cutoff = DateTime.now().millisecondsSinceEpoch - billtyRetentionDays * 86400000;
    final rows = await db.rawQuery(
      "SELECT id, billty_path FROM bill_dispatch WHERE is_deleted = 0 "
      "AND billty_path != '' AND billty_at > 0 AND billty_at < ?",
      [cutoff],
    );
    var n = 0;
    for (final r in rows) {
      _deletePhotoFile((r['billty_path'] ?? '') as String);
      await db.update(
        'bill_dispatch',
        {'billty_path': '', 'billty_at': 0, 'updated_at': _now(), 'dirty': 1},
        where: 'id = ?',
        whereArgs: [r['id'] as String],
      );
      n++;
    }
    return n;
  }

  /// Deletes a billty photo from disk (45-day cleanup or replacement).
  /// Only files inside the app's own billty_photos folder are touched.
  void _deletePhotoFile(String path) {
    if (path.isEmpty || !path.contains('billty_photos')) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  // ---------------- payments ----------------

  Future<Payment> addPayment({
    required String customerId,
    required int amountPaise,
    required String mode,
    required DateTime date,
    String note = '',
    String proofPath = '',
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
      note: Sanitize.text(note),
      proofPath: proofPath,
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
      SELECT id, pay_date, amount_paise, mode, note, proof_path, is_deleted FROM payments
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
          proofPath: (r['proof_path'] ?? '') as String,
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
      await setMeta(e.key, e.key == 'shop_phone'
          ? Sanitize.digits(e.value)
          : Sanitize.text(e.value, maxLen: 200));
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
