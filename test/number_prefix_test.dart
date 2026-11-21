import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ruby_invoice/data/db.dart';
import 'package:ruby_invoice/data/repo.dart';
import 'package:ruby_invoice/services/access_service.dart';

/// BLOCKER 2 (v0.4.3): PER-DEVICE NUMBER SLOTS.
///
/// bill_no / purchase_no / return_no are allocated inside a slot of
/// 100000 numbers owned by THIS registered device, so two offline
/// phones in the same shop can never pick the same number:
///   slot 0 -> 1..99,999     (legacy rows + single-device shops)
///   slot 1 -> 100,000..199,999
///   slot 2 -> 200,000..299,999
///   slot 9 -> 900,000..999,999 (unregistered fallback)
/// Existing (legacy) numbers are NEVER rewritten.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tmp;

  setUp(() async {
    await DB.resetForTest();
    tmp = await Directory.systemTemp.createTemp('ruby_slot_test');
    await databaseFactory.setDatabasesPath(tmp.path);
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('slot resolver (pure)', () {
    test('single registered device -> slot 0 (legacy numbering continues)',
        () {
      expect(AccessService.numberSlotFor('devA', ['devA']), 0);
    });

    test('two devices get distinct slots 1 and 2', () {
      expect(AccessService.numberSlotFor('devA', ['devA', 'devB']), 1);
      expect(AccessService.numberSlotFor('devB', ['devA', 'devB']), 2);
    });

    test('unregistered device -> fallback slot 9', () {
      expect(AccessService.numberSlotFor('devC', ['devA', 'devB']), 9);
      expect(AccessService.numberSlotFor('devA', const []), 9);
    });

    test('shrink back to one device -> slot 0 again', () {
      expect(AccessService.numberSlotFor('devA', ['devA']), 0);
    });
  });

  group('slot-scoped numbering (DB)', () {
    Future<void> insertBill(String id, int billNo, {int dirty = 0}) async {
      final db = await DB.open();
      await db.insert('bills', {
        'id': id,
        'bill_no': billNo,
        'customer_id': 'c1',
        'customer_name': 'Test Shop',
        'bill_date': 1000,
        'bill_day': '2026-01-01',
        'subtotal_paise': 10000,
        'discount_paise': 0,
        'total_paise': 10000,
        'note': '',
        'created_at': 1000,
        'updated_at': 1000,
        'is_deleted': 0,
        'dirty': dirty,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    test('legacy rows keep their numbers; slot 0 continues them', () async {
      await insertBill('b1', 1);
      await insertBill('b2', 2);
      await insertBill('b3', 5);
      await Repo.instance.setNumberSlot(0);
      expect(await Repo.instance.nextBillNo(), 6); // continues 1..5
    });

    test('slot 1 ignores legacy rows and starts at 100,000+1', () async {
      await insertBill('b1', 1);
      await insertBill('b2', 500);
      await Repo.instance.setNumberSlot(1);
      expect(await Repo.instance.nextBillNo(), 100001);
    });

    test('slots are independent - no overlap between devices', () async {
      await insertBill('b1', 1);
      await insertBill('b2', 2);
      await Repo.instance.setNumberSlot(1);
      expect(await Repo.instance.nextBillNo(), 100001);
      await insertBill('b3', 100001);
      await insertBill('b4', 100002);
      expect(await Repo.instance.nextBillNo(), 100003); // own slot max + 1

      // The other phone's slot never sees ours.
      await Repo.instance.setNumberSlot(2);
      expect(await Repo.instance.nextBillNo(), 200001);
    });

    test('saveBill allocates inside the device slot, legacy rows untouched',
        () async {
      await insertBill('legacy1', 1);
      await insertBill('legacy2', 4);
      await Repo.instance.setNumberSlot(2);
      final bill = await Repo.instance.saveBill(
        customerId: 'c1',
        customerName: 'Test',
        lines: const [],
      );
      expect(bill.billNo, 200001);
      final db = await DB.open();
      final rows = await db
          .rawQuery('SELECT id, bill_no FROM bills ORDER BY created_at');
      expect((rows[0] as Map)['bill_no'], 1); // purana number - untouched
      expect((rows[1] as Map)['bill_no'], 4); // purana number - untouched
      expect((rows[2] as Map)['bill_no'], 200001);
    });

    test('missing slot meta -> fallback slot 9 (900,001+)', () async {
      await insertBill('b1', 3);
      expect(await Repo.instance.nextBillNo(), 900001);
    });

    test('purchases + returns are slot-scoped too', () async {
      final db = await DB.open();
      await db.insert('purchases', {
        'id': 'p1', 'purchase_no': 7, 'supplier_name': 'S',
        'purchase_date': 1000, 'purchase_day': '2026-01-01',
        'created_at': 1000, 'updated_at': 1000, 'is_deleted': 0, 'dirty': 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await Repo.instance.setNumberSlot(1);
      expect(await Repo.instance.nextPurchaseNo(), 100001);

      final ret = await Repo.instance.saveSalesReturn(
        customerId: 'c1',
        customerName: 'C',
        lines: const [],
      );
      expect(ret.returnNo, 100001);

      await Repo.instance.setNumberSlot(0);
      expect(await Repo.instance.nextPurchaseReturnNo(), 1);
    });
  });

  group('duplicate healer now covers the return ledgers too', () {
    Future<void> insertSalesReturn(String id, int no, int createdAt,
        {int dirty = 0}) async {
      final db = await DB.open();
      await db.insert('sales_returns', {
        'id': id, 'return_no': no, 'customer_id': 'c1', 'customer_name': 'C',
        'amount_paise': 5000, 'note': '', 'return_date': createdAt,
        'return_day': '2026-01-01', 'created_at': createdAt,
        'updated_at': createdAt, 'is_deleted': 0, 'dirty': dirty,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    test('duplicate return_no healed, oldest keeps, idempotent', () async {
      await insertSalesReturn('r1', 3, 100);
      await insertSalesReturn('r2', 3, 200);
      expect(await Repo.instance.reconcileDuplicateNumbers(), 1);
      final db = await DB.open();
      final rows = await db.rawQuery(
          'SELECT id, return_no, dirty FROM sales_returns ORDER BY id');
      final byId = {for (final r in rows) r['id'] as String: r};
      expect(byId['r1']!['return_no'], 3);
      expect(byId['r2']!['return_no'], 4); // MAX+1 beyond slot 0 data
      expect(byId['r2']!['dirty'], 1);
      expect(await Repo.instance.reconcileDuplicateNumbers(), 0); // idempotent
    });

    test('slot rows do not collide across heal - slot number preserved',
        () async {
      await insertSalesReturn('r1', 100001, 100); // slot 1 row
      await insertSalesReturn('r2', 100001, 200); // duplicate from 2nd phone
      expect(await Repo.instance.reconcileDuplicateNumbers(), 1);
      final db = await DB.open();
      final rows = await db.rawQuery(
          'SELECT id, return_no FROM sales_returns ORDER BY id');
      expect((rows[0] as Map)['return_no'], 100001);
      expect((rows[1] as Map)['return_no'], 100002);
    });
  });
}
