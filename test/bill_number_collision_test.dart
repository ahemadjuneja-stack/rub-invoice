import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ruby_invoice/data/db.dart';
import 'package:ruby_invoice/data/repo.dart';

/// GOAL 3 (v0.4.1): BILL NUMBER COLLISION FIX.
///
/// Two phones in the same shop can both save "bill #12" while offline
/// (MAX+1 is atomic per phone, not across phones). The sync engine now
/// heals duplicates after every pull via Repo.reconcileDuplicateNumbers().
///
/// These tests prove the planner is deterministic and that the DB
/// healer renumbers exactly the right rows - and does nothing when
/// there are no duplicates (idempotent second pass).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tmp;

  setUp(() async {
    await DB.resetForTest();
    tmp = await Directory.systemTemp.createTemp('ruby_number_test');
    await databaseFactory.setDatabasesPath(tmp.path);
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Map<String, Object?> row(String id, int no, int createdAt) =>
      {'id': id, 'no': no, 'created_at': createdAt};

  group('planDuplicateNumberFixes (pure planner)', () {
    test('oldest keeps the number, the rest move to MAX+1', () {
      final fixes = planDuplicateNumberFixes([
        row('b', 1, 200), // newer duplicate of #1
        row('a', 1, 100), // oldest -> keeps #1
        row('c', 2, 150), // unique
        row('d', 5, 50), // highest number
      ]);
      expect(fixes, hasLength(1));
      expect(fixes.first.id, 'b');
      expect(fixes.first.newNo, 6); // MAX(5) + 1
    });

    test('two duplicates are renumbered in chronological order', () {
      final fixes = planDuplicateNumberFixes([
        row('a', 3, 100), // keeps #3
        row('b', 3, 200), // -> 4
        row('c', 3, 300), // -> 5
      ]);
      expect(fixes, hasLength(2));
      expect(fixes[0].id, 'b');
      expect(fixes[0].newNo, 4);
      expect(fixes[1].id, 'c');
      expect(fixes[1].newNo, 5);
    });

    test('ties on created_at break by id (determinism across devices)', () {
      final a = planDuplicateNumberFixes([row('x9', 7, 100), row('x2', 7, 100)]);
      final b = planDuplicateNumberFixes([row('x2', 7, 100), row('x9', 7, 100)]);
      // Same outcome no matter the input order -> both phones converge.
      expect(a.map((f) => '${f.id}:${f.newNo}'), b.map((f) => '${f.id}:${f.newNo}'));
      expect(a.first.id, 'x9'); // x2 sorts first, keeps #7
      expect(a.first.newNo, 8);
    });

    test('nextFloor avoids numbers held by dirty (unsynced) rows', () {
      final fixes = planDuplicateNumberFixes(
          [row('a', 1, 100), row('b', 1, 200)],
          nextFloor: 9);
      expect(fixes, hasLength(1));
      expect(fixes.first.newNo, 10); // 9 belongs to an unsynced local bill
    });

    test('no duplicates -> no fixes (idempotent)', () {
      expect(
        planDuplicateNumberFixes([row('a', 1, 1), row('b', 2, 2)]),
        isEmpty,
      );
    });
  });

  group('Repo.reconcileDuplicateNumbers (DB healer)', () {
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

    test('duplicate bill numbers are healed, dirty rows untouched', () async {
      // Simulate the offline 2-device race: both phones saved #1, and
      // this phone also has two UNSYNCED local rows (#1 draft and #9).
      await insertBill('bill_a', 1, 1000); // oldest -> keeps #1
      await insertBill('bill_b', 1, 2000); // -> renumbered past the floor
      await insertBill('bill_c', 1, 3000, dirty: 1); // unsynced, untouched
      await insertBill('bill_d', 9, 4000, dirty: 1); // holds the floor

      final fixed = await Repo.instance.reconcileDuplicateNumbers();
      // Only bill_b is renumbered (bill_c/d are dirty -> invisible).
      expect(fixed, 1);

      final db = await DB.open();
      final rows = await db.rawQuery('SELECT id, bill_no, dirty FROM bills ORDER BY id');
      final byId = {for (final r in rows) r['id'] as String: r};
      expect(byId['bill_a']!['bill_no'], 1);
      expect(byId['bill_b']!['bill_no'], 10); // MAX(9, dirty rows count) + 1
      expect(byId['bill_b']!['dirty'], 1); // renumber syncs back to cloud
      expect(byId['bill_c']!['bill_no'], 1); // dirty row untouched
      expect(byId['bill_d']!['bill_no'], 9); // dirty row untouched
    });

    test('second pass changes nothing (idempotent, no ping-pong)', () async {
      await insertBill('bill_a', 4, 100);
      await insertBill('bill_b', 4, 200);
      expect(await Repo.instance.reconcileDuplicateNumbers(), 1);
      expect(await Repo.instance.reconcileDuplicateNumbers(), 0);
      final db = await DB.open();
      final nos = await db.rawQuery('SELECT DISTINCT bill_no FROM bills');
      expect(nos, hasLength(2));
    });

    test('clean database -> zero changes', () async {
      await insertBill('bill_a', 1, 100);
      await insertBill('bill_b', 2, 200);
      expect(await Repo.instance.reconcileDuplicateNumbers(), 0);
    });
  });
}
