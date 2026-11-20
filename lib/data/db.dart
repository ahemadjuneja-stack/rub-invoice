import 'dart:io';
import '../core/app_log.dart';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

/// Local SQLite database. 100% offline.
/// Schema is sync-ready: uuid primary keys, updated_at + is_deleted
/// (tombstones) on every table, dirty flag for the push queue.
///
/// SELF-HEALING OPEN (v0.2.19): every read/write in the app funnels
/// through DB.open(), so a broken open silently killed the bills list
/// (stuck spinner), customer save, bill save AND cloud sync - all with
/// zero visible feedback. The open below is now:
///   * single-flight: one in-flight open, every caller shares it
///     (a boot-timeout can no longer start a second concurrent open)
///   * retried: 4 attempts with small gaps (a transient "database is
///     locked" or a slow first-ever schema creation recovers itself)
///   * self-healing: if the file itself is corrupt (force-close during
///     a write), it is QUARANTINED (renamed .corrupt_<ts>, never
///     deleted - the old data stays on disk) and a fresh database is
///     created, so the app always ends up with a working local DB.
class DB {
  DB._();
  static Database? _handle;
  static Future<Database>? _opening;

  static Future<Database> open() {
    final h = _handle;
    if (h != null) return Future.value(h);
    // Single flight: while one open is running, every caller awaits the
    // SAME future. whenComplete clears the slot so a real failure is
    // retried by the next caller instead of caching the error forever.
    return _opening ??= _openNow().whenComplete(() => _opening = null);
  }

  /// Closes the cached handle and clears the single-flight slot so the
  /// next [open] really reopens the file. The engine tests need this:
  /// each test gets its own temp databases directory, and writing to a
  /// handle whose file was deleted under it makes SQLite fail with
  /// SQLITE_READONLY ("attempt to write a readonly database") - the
  /// stale handle must be dropped between tests. The app itself never
  /// swaps the database file, so production never needs this.
  static Future<void> resetForTest() async {
    final h = _handle;
    _handle = null;
    _opening = null;
    try {
      await h?.close();
    } catch (_) {}
  }

  static Future<Database> _openNow() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'ruby_invoice.db');
    Object? last;
    for (int attempt = 1; attempt <= 4; attempt++) {
      try {
        final db = await openDatabase(
          path,
          version: 5,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onUpgrade: _onUpgrade,
          onCreate: _onCreate,
        );
        _handle = db;
        return db;
      } catch (e) {
        last = e;
        appLog('[db] open attempt $attempt failed: $e');
        if (attempt < 4) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      }
    }
    appLog('[db] file seems broken - quarantining: $last');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      try {
        final f = File('$path$suffix');
        if (await f.exists()) {
          await f.rename('$path$suffix.corrupt_$stamp');
        }
      } catch (e) {
        appLog('[db] quarantine rename failed for $suffix: $e');
      }
    }
    final db = await openDatabase(
      path,
      version: 5,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onUpgrade: _onUpgrade,
      onCreate: _onCreate,
    );
    _handle = db;
    return db;
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v2: customers gained shop_name + address.
    if (oldVersion < 2) {
      try {
        await db.execute("ALTER TABLE customers ADD COLUMN shop_name TEXT DEFAULT ''");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE customers ADD COLUMN address TEXT DEFAULT ''");
      } catch (_) {}
    }
    // v3: purchase invoices (supplier bills with optional photo).
    if (oldVersion < 3) {
      await _createPurchases(db);
    }
    // v4: payments can keep an optional payment-proof screenshot
    // (UPI transfer screenshot etc.) on this phone.
    if (oldVersion < 4) {
      try {
        await db.execute("ALTER TABLE payments ADD COLUMN proof_path TEXT DEFAULT ''");
      } catch (_) {}
    }
    // v5: delivery (transport) details per bill - how the goods went,
    // the billty photo (45-day retention, auto-deleted) and a note.
    if (oldVersion < 5) {
      await _createDispatch(db);
    }
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
          CREATE TABLE customers (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            shop_name TEXT DEFAULT '',
            city TEXT DEFAULT '',
            phone TEXT DEFAULT '',
            address TEXT DEFAULT '',
            opening_balance_paise INTEGER DEFAULT 0,
            created_at INTEGER DEFAULT 0,
            updated_at INTEGER DEFAULT 0,
            is_deleted INTEGER DEFAULT 0,
            dirty INTEGER DEFAULT 1
          )
        ''');
    await db.execute('''
          CREATE TABLE products (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            unit TEXT DEFAULT 'Pcs',
            default_qty REAL DEFAULT 1,
            default_price_paise INTEGER DEFAULT 0,
            track_stock INTEGER DEFAULT 0,
            stock_qty REAL DEFAULT 0,
            low_stock REAL DEFAULT 0,
            created_at INTEGER DEFAULT 0,
            updated_at INTEGER DEFAULT 0,
            is_deleted INTEGER DEFAULT 0,
            dirty INTEGER DEFAULT 1
          )
        ''');
    await db.execute('''
          CREATE TABLE bills (
            id TEXT PRIMARY KEY,
            bill_no INTEGER DEFAULT 0,
            customer_id TEXT NOT NULL,
            customer_name TEXT DEFAULT '',
            bill_date INTEGER DEFAULT 0,
            bill_day TEXT DEFAULT '',
            subtotal_paise INTEGER DEFAULT 0,
            discount_paise INTEGER DEFAULT 0,
            total_paise INTEGER DEFAULT 0,
            note TEXT DEFAULT '',
            created_at INTEGER DEFAULT 0,
            updated_at INTEGER DEFAULT 0,
            is_deleted INTEGER DEFAULT 0,
            dirty INTEGER DEFAULT 1
          )
        ''');
    await db.execute('''
          CREATE TABLE bill_items (
            id TEXT PRIMARY KEY,
            bill_id TEXT NOT NULL,
            product_id TEXT,
            product_name TEXT NOT NULL,
            qty REAL DEFAULT 0,
            rate_paise INTEGER DEFAULT 0,
            amount_paise INTEGER DEFAULT 0,
            created_at INTEGER DEFAULT 0,
            updated_at INTEGER DEFAULT 0,
            is_deleted INTEGER DEFAULT 0,
            dirty INTEGER DEFAULT 1
          )
        ''');
    await db.execute('''
          CREATE TABLE payments (
            id TEXT PRIMARY KEY,
            customer_id TEXT NOT NULL,
            bill_id TEXT,
            amount_paise INTEGER DEFAULT 0,
            pay_date INTEGER DEFAULT 0,
            pay_day TEXT DEFAULT '',
            mode TEXT DEFAULT 'cash',
            note TEXT DEFAULT '',
            proof_path TEXT DEFAULT '',
            created_at INTEGER DEFAULT 0,
            updated_at INTEGER DEFAULT 0,
            is_deleted INTEGER DEFAULT 0,
            dirty INTEGER DEFAULT 1
          )
        ''');
    await db.execute("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT DEFAULT '')");

    await _createPurchases(db);

    await _createDispatch(db);

    // v0.2.20 FIX: every index here uses IF NOT EXISTS. _createPurchases
    // already creates idx_purchases_day, so the bare duplicate
    // "CREATE INDEX idx_purchases_day" below used to THROW
    // ("index idx_purchases_day already exists") during onCreate ->
    // openDatabase failed on EVERY fresh database -> 4 retries failed
    // the same way -> quarantine created a new file -> same crash again
    // -> DB.open() threw -> every customer/bill save and every list
    // load failed forever ("Cannot add customers", "Data could not
    // load + RETRY"). The engine tests reproduce it 100%.
    await db.execute('CREATE INDEX IF NOT EXISTS idx_bills_day ON bills (bill_day)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_bills_customer ON bills (customer_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_items_bill ON bill_items (bill_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_payments_customer ON payments (customer_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_customers_name ON customers (name)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_products_name ON products (name)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_purchases_day ON purchases (purchase_day)');
  }

  /// Purchase invoices table: supplier bills with an optional photo of
  /// the paper bill. Same sync-ready shape as every other table.
  static Future<void> _createPurchases(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchases (
        id TEXT PRIMARY KEY,
        purchase_no INTEGER DEFAULT 0,
        supplier_name TEXT NOT NULL DEFAULT '',
        supplier_phone TEXT DEFAULT '',
        amount_paise INTEGER DEFAULT 0,
        note TEXT DEFAULT '',
        photo_path TEXT DEFAULT '',
        purchase_date INTEGER DEFAULT 0,
        purchase_day TEXT DEFAULT '',
        created_at INTEGER DEFAULT 0,
        updated_at INTEGER DEFAULT 0,
        is_deleted INTEGER DEFAULT 0,
        dirty INTEGER DEFAULT 1
      )
    ''');
    try {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_purchases_day ON purchases (purchase_day)');
    } catch (_) {}
  }

  /// v5: bill_dispatch table - one row per bill with the delivery mode
  /// (transport / in hand / courier / pending), the billty photo path
  /// and its capture time (45-day auto-delete clock) plus a note.
  /// Same sync-ready shape as every other table.
  static Future<void> _createDispatch(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS bill_dispatch (
        id TEXT PRIMARY KEY,
        bill_id TEXT NOT NULL,
        mode TEXT DEFAULT '',
        billty_path TEXT DEFAULT '',
        billty_at INTEGER DEFAULT 0,
        note TEXT DEFAULT '',
        created_at INTEGER DEFAULT 0,
        updated_at INTEGER DEFAULT 0,
        is_deleted INTEGER DEFAULT 0,
        dirty INTEGER DEFAULT 1
      )
    ''');
    try {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_dispatch_bill ON bill_dispatch (bill_id)');
    } catch (_) {}
  }
}
