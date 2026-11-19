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
      version: 2,
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
            created_at INTEGER DEFAULT 0,
            updated_at INTEGER DEFAULT 0,
            is_deleted INTEGER DEFAULT 0,
            dirty INTEGER DEFAULT 1
          )
        ''');
        await db.execute("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT DEFAULT '')");

        await db.execute('CREATE INDEX idx_bills_day ON bills (bill_day)');
        await db.execute('CREATE INDEX idx_bills_customer ON bills (customer_id)');
        await db.execute('CREATE INDEX idx_items_bill ON bill_items (bill_id)');
        await db.execute('CREATE INDEX idx_payments_customer ON payments (customer_id)');
        await db.execute('CREATE INDEX idx_customers_name ON customers (name)');
        await db.execute('CREATE INDEX idx_products_name ON products (name)');
      },
    );
    return _handle!;
  }
}
