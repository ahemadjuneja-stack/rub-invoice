import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ruby_invoice/data/db.dart';
import 'package:ruby_invoice/data/repo.dart';
import 'package:ruby_invoice/models/models.dart';

/// v0.2.20 regression guards for the two engine bugs that bricked the
/// app ("cannot add customers / bills", partial cloud restore):
///
/// 1. onCreate duplicate index: _createPurchases already creates
///    idx_purchases_day, and the bare duplicate CREATE INDEX threw
///    "index already exists" on EVERY fresh database -> DB.open()
///    always failed -> every save and every list load failed forever.
/// 2. Shared pull cursor: one cursor across all tables let the cursor
///    run ahead to the newest row of an earlier table, so older rows of
///    later tables were skipped FOREVER on a fresh device.
///
/// These tests run on the Dart VM via sqflite_common_ffi (no emulator).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tmp;

  setUp(() async {
    // Drop any handle cached by the previous test FIRST: after tearDown
    // deletes that test's temp directory, the old handle points to an
    // unlinked file and every write fails with SQLITE_READONLY
    // ("attempt to write a readonly database").
    await DB.resetForTest();
    tmp = await Directory.systemTemp.createTemp('ruby_db_test');
    await databaseFactory.setDatabasesPath(tmp.path);
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('fresh database opens and accepts a customer + a bill', () async {
    final c = await Repo.instance.newCustomer(name: 'Fresh Phone', city: 'Rajkot');
    final found = await Repo.instance.searchCustomers('Fresh');
    expect(found, hasLength(1));

    final bill = await Repo.instance.saveBill(
      customerId: c.id,
      customerName: c.name,
      lines: [CartLine(name: 'Kurta', qty: 2, ratePaise: 99000)],
    );
    expect(bill.billNo, 1);
    expect(bill.totalPaise, 198000);

    final days = await Repo.instance.billsForDays([bill.billDay]);
    expect(days[bill.billDay], hasLength(1));
  });

  test('corrupt db file is quarantined and a working db is created',
      () async {
    // seed a good db, then smash the file. resetForTest() closes AND
    // clears the cached handle - a plain handle.close() would leave
    // DB._open() handing back the closed instance instead of reopening.
    await Repo.instance.newCustomer(name: 'Before Crash');
    await DB.resetForTest();

    final path = p.join(await getDatabasesPath(), 'ruby_invoice.db');
    File(path).writeAsStringSync('NOT A DATABASE');

    // must quarantine the broken file and end with a working database
    final healed = await DB.open();
    final tables = await healed
        .rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
    expect(tables, isNotEmpty);

    final c = await Repo.instance.newCustomer(name: 'After Heal');
    expect((await Repo.instance.getCustomer(c.id))!.name, 'After Heal');

    // the smashed file must survive next to the new one (never deleted)
    final quarantined = Directory(await getDatabasesPath())
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('.corrupt_'))
        .toList();
    expect(quarantined, isNotEmpty, reason: 'corrupt file must be quarantined, not deleted');
  });

  test('every save path leaves dirty=1 for the sync push', () async {
    final c = await Repo.instance.newCustomer(name: 'Dirty Check');
    final bill = await Repo.instance.saveBill(
      customerId: c.id,
      customerName: c.name,
      lines: [CartLine(name: 'Saree', qty: 1, ratePaise: 50000)],
    );
    await Repo.instance.saveDispatch(billId: bill.id, mode: 'transport');
    await Repo.instance.savePurchase(
      supplierId: 'sup-1',
      supplierName: 'Supplier',
      lines: [PurchaseCartLine(name: 'Maal', qty: 2, ratePaise: 35000)],
    );
    await Repo.instance.saveSalesReturn(
      customerId: c.id,
      customerName: c.name,
      lines: [CartLine(name: 'Saree', qty: 1, ratePaise: 50000)],
    );
    await Repo.instance.addPayment(customerId: c.id, amountPaise: 20000, mode: 'upi', date: DateTime.now());
    final ec = await Repo.instance.getCustomer(c.id);
    await Repo.instance.upsertCustomer(ec!.copyWith(name: 'Dirty Check 2'));

    final db = await DB.open();
    for (final t in [
      'customers', 'bills', 'bill_items', 'bill_dispatch', 'purchases',
      'purchase_items', 'payments', 'sales_returns', 'sales_return_items',
    ]) {
      final rows = await db.rawQuery('SELECT COUNT(*) c FROM $t WHERE dirty = 1');
      expect((rows.first['c'] as int?) ?? 0, greaterThan(0), reason: '$t must have dirty rows to push');
    }
  });
}
