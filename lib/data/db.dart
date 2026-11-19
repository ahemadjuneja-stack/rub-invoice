import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

/// Local SQLite database. 100% offline.
/// Schema is sync-ready: uuid primary keys, updated_at + is_deleted
/// (tombstones) on every table, dirty flag for the push queue.
class DB {
  DB._();
  static Database? _handle;

  static Future<Database> open() async {
    if (_handle != null) return _handle!;
    final dir = await getDatabasesPath();
    _handle = await openDatabase(
      p.join(dir, 'ruby_invoice.db'),
      version: 5,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onUpgrade: (db, oldVersion, newVersion) async {
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
      },
      onCreate: (db, version) async {
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

        await db.execute('CREATE INDEX idx_bills_day ON bills (bill_day)');
        await db.execute('CREATE INDEX idx_bills_customer ON bills (customer_id)');
        await db.execute('CREATE INDEX idx_items_bill ON bill_items (bill_id)');
        await db.execute('CREATE INDEX idx_payments_customer ON payments (customer_id)');
        await db.execute('CREATE INDEX idx_customers_name ON customers (name)');
        await db.execute('CREATE INDEX idx_products_name ON products (name)');
        await db.execute('CREATE INDEX idx_purchases_day ON purchases (purchase_day)');
      },
    );
    return _handle!;
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
