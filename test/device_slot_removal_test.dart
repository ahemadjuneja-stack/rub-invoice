import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ruby_invoice/data/db.dart';
import 'package:ruby_invoice/data/repo.dart';
import 'package:ruby_invoice/services/access_service.dart';

/// DEVICE REMOVE / RESET vs PER-DEVICE NUMBER SLOTS (Blocker 2).
///
/// Scenario: registeredDevices = [A, B]. Device A is removed (admin
/// reset) and possibly re-added later. What happens to B's slot, B's
/// NEW bill numbers, and the OLD numbers?
///
/// Covered cases:
///   1. A removed -> [B]        : B is alone -> slot 0 (plain numbering)
///   2. A re-added -> [B, A]    : B -> slot 1, A -> slot 2 (ranges
///                                re-home; allocation is MAX+1 INSIDE
///                                the target range, so no existing
///                                number is ever reused)
///   3. B OFFLINE during the reset (stale cached slot 2) while a fresh
///      device also holds slot 2 -> duplicates CAN arise in that window;
///      the v0.4.1 healer resolves them deterministically after sync.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tmp;

  setUp(() async {
    await DB.resetForTest();
    tmp = await Directory.systemTemp.createTemp('ruby_slot_removal_test');
    await databaseFactory.setDatabasesPath(tmp.path);
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> insertBill(String id, int billNo, int createdAt,
      {int dirty = 0}) async {
    final db = await DB.open();
    await db.insert('bills', {
      'id': id,
      'bill_no': billNo,
      'customer_id': 'c1',
      'customer_name': 'Test Shop',
      'bill_date': createdAt,
      'bill_day': '2026-01-01',
      'subtotal_paise': 10000,
      'discount_paise': 0,
      'total_paise': 10000,
      'note': '',
      'created_at': createdAt,
      'updated_at': createdAt,
      'is_deleted': 0,
      'dirty': dirty,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Set<int>> allBillNos() async {
    final db = await DB.open();
    final rows = await db.rawQuery('SELECT bill_no FROM bills');
    return rows.map((r) => r['bill_no'] as int).toSet();
  }

  group('slot resolution after remove / reset (pure)', () {
    test('A removed -> B alone -> slot 0', () {
      expect(AccessService.numberSlotFor('B', ['B']), 0);
    });

    test('A re-added -> [B, A]: B slot 1, A slot 2 (append, never swap)', () {
      expect(AccessService.numberSlotFor('B', ['B', 'A']), 1);
      expect(AccessService.numberSlotFor('A', ['B', 'A']), 2);
    });

    test('unregistered device keeps fallback slot 9', () {
      expect(AccessService.numberSlotFor('A', ['B']), 9);
    });
  });

  group('CASE 1: A removed, B alone ([B])', () {
    test('new numbers continue plain numbering; OLD slot-2 numbers untouched',
        () async {
      // Shop history: legacy bills + B's old slot-2 bills.
      await insertBill('legacy1', 1, 100);
      await insertBill('legacy2', 2, 200);
      await insertBill('bOld1', 200001, 300);
      await insertBill('bOld2', 200002, 400);

      // A removed -> B recomputes its slot on the next account refresh.
      await Repo.instance
          .setNumberSlot(AccessService.numberSlotFor('B', ['B']));

      final next = await Repo.instance.nextBillNo();
      expect(next, 3); // continues the legacy sequence, NOT 200003
      expect(next, isNot(200003)); // B's old range is not blindly continued

      final nos = await allBillNos();
      expect(nos, containsAll([200001, 200002])); // purane numbers - intact
      expect(nos.contains(next), isFalse); // no collision with old numbers
    });

    test('fresh shop (no legacy rows): B alone starts at 1, old 200xxx kept',
        () async {
      await insertBill('bOld1', 200001, 100);
      await insertBill('bOld2', 200002, 200);
      await Repo.instance
          .setNumberSlot(AccessService.numberSlotFor('B', ['B']));
      final next = await Repo.instance.nextBillNo();
      expect(next, 1);
      expect(await allBillNos(), containsAll([200001, 200002]));
    });
  });

  group('CASE 2: A removed AND re-added -> [B, A]', () {
    test('B slot 1 continues AFTER A\'s old slot-1 numbers; '
        'A slot 2 continues AFTER B\'s old slot-2 numbers; zero duplicates',
        () async {
      // Old era [A, B]: A was slot 1 (100xxx), B was slot 2 (200xxx).
      for (var i = 1; i <= 3; i++) {
        await insertBill('aOld$i', 100000 + i, 100 + i); // A's old bills
        await insertBill('bOld$i', 200000 + i, 200 + i); // B's old bills
      }
      final before = await allBillNos();

      // After the reset both devices refresh their slots from [B, A].
      await Repo.instance
          .setNumberSlot(AccessService.numberSlotFor('B', ['B', 'A']));
      final bNext = await Repo.instance.nextBillNo();
      expect(bNext, 100004); // continues A's old range, does not reuse it

      await Repo.instance
          .setNumberSlot(AccessService.numberSlotFor('A', ['B', 'A']));
      final aNext = await Repo.instance.nextBillNo();
      expect(aNext, 200004); // continues B's old range, does not reuse it

      // No collision: both new numbers are unused and distinct.
      expect(bNext, isNot(aNext));
      expect(before.contains(bNext), isFalse);
      expect(before.contains(aNext), isFalse);
      expect(await allBillNos(), containsAll([100003, 200003])); // old intact
    });
  });

  group('CASE 3: stale-cache window (B offline during the reset)', () {
    test('B keeps slot 2 offline, a refreshed device also takes slot 2 '
        '-> duplicate number -> healer fixes it deterministically', () async {
      // Cloud baseline: B's SYNCED slot-2 bills (visible to both phones).
      for (var i = 1; i <= 10; i++) {
        await insertBill('syncB$i', 200000 + i, 1000 + i);
      }

      // B is OFFLINE, still cached slot 2, saves two more bills.
      await Repo.instance.setNumberSlot(2); // B's stale slot
      final bOffline1 = await Repo.instance.nextBillNo(); // 200011
      expect(bOffline1, 200011);
      await insertBill('bOffline1', bOffline1, 5000, dirty: 1); // unsynced

      // Meanwhile A was removed and re-added as [B, A]; A refreshed and
      // took slot 2 (position index 1 + 1). A allocates from ITS OWN
      // local DB - which does NOT contain B's unsynced row yet.
      final db = await DB.open();
      await db.delete('bills', where: 'id = ?', whereArgs: ['bOffline1']);
      await Repo.instance
          .setNumberSlot(AccessService.numberSlotFor('A', ['B', 'A']));
      expect(AccessService.numberSlotFor('A', ['B', 'A']), 2);
      final aNext = await Repo.instance.nextBillNo();
      expect(aNext, 200011); // THE COLLISION - A's view ends at 200010
      await insertBill('aNew', aNext, 6000);

      // Both rows eventually sync: cloud holds the duplicate; on the
      // next pull each phone sees both rows as clean (synced) rows.
      await insertBill('bOffline1', 200011, 5000, dirty: 0); // B's row lands

      // The healer runs after the pull: oldest (B, created 5000) keeps
      // 200011, A's row moves past the floor (MAX of ALL rows + 1).
      final fixed = await Repo.instance.reconcileDuplicateNumbers();
      expect(fixed, 1);

      final db2 = await DB.open();
      final rows = await db2.rawQuery('SELECT id, bill_no FROM bills');
      final byId = {for (final r in rows) r['id'] as String: r};
      expect(byId['bOffline1']!['bill_no'], 200011); // oldest kept it
      expect(byId['aNew']!['bill_no'], 200012); // floor = 200011 -> +1
      expect(byId['syncB10']!['bill_no'], 200010); // old numbers untouched

      // idempotent - second pass changes nothing
      expect(await Repo.instance.reconcileDuplicateNumbers(), 0);
      final nos = await allBillNos();
      expect(nos, containsAll([200011, 200012]));
    });

    test('unsynced (dirty) rows are never renumbered by the healer - '
        'the collision resolves only after both sides sync', () async {
      await insertBill('sync1', 200001, 100);
      await Repo.instance.setNumberSlot(2);
      final bDirty = await Repo.instance.nextBillNo(); // 200002, unsynced
      await insertBill('bDirty', bDirty, 5000, dirty: 1);
      await insertBill('aDirty', 200002, 6000, dirty: 1); // A's unsynced row

      // Both colliding rows are still dirty (in flight) -> healer skips.
      expect(await Repo.instance.reconcileDuplicateNumbers(), 0);
      final nos = await allBillNos();
      expect(nos.contains(200002), isTrue); // untouched until synced
    });
  });
}
