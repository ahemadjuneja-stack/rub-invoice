import 'dart:async';
import '../core/app_log.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../data/db.dart';
import '../data/repo.dart';
import 'access_service.dart';
import 'photo_sync_service.dart';

enum SyncStatus { offline, syncing, synced, error }

/// Offline-first sync engine.
///
/// * Local SQLite is always the source of truth; the app never waits on
///   the network.
/// * Every table row has a uuid id, updated_at and a tombstone flag
///   (is_deleted), which makes a simple robust last-write-wins merge.
/// * Push: rows with dirty = 1 are written to Firestore in batches.
/// * Pull: rows with updated_at > last_sync cursor are applied locally
///   only when strictly newer than the local row.
/// * Bills embed their items (one document per bill) so a saved bill is
///   always consistent across devices.
/// * Both phones logged in with the SAME mobile number share one shop
///   document tree, so both apps always see the same data.
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  final ValueNotifier<SyncStatus> status = ValueNotifier<SyncStatus>(SyncStatus.offline);

  /// v0.2.19: flips true when Firebase becomes ready - including when
  /// the boot-time init failed on a slow network and the background
  /// recovery (_recoverFirebaseInBackground in main.dart) succeeded
  /// later. AuthGate listens to this and shows the login screen the
  /// moment cloud features come alive.
  final ValueNotifier<bool> fbReadyNotifier = ValueNotifier<bool>(false);

  bool _fbReady = false;
  bool _busy = false;
  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  StreamSubscription<dynamic>? _authSub;

  bool get fbReady => _fbReady;

  bool get signedIn {
    if (!_fbReady) return false;
    try {
      return FirebaseAuth.instance.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  /// Safe to call multiple times (boot + background recovery): old
  /// listeners are cancelled first, so wires are never duplicated.
  Future<void> configure({required bool fbReady}) async {
    _fbReady = fbReady;
    fbReadyNotifier.value = fbReady;
    _timer?.cancel();
    _timer = null;
    await _connSub?.cancel();
    _connSub = null;
    await _authSub?.cancel();
    _authSub = null;
    if (!_fbReady) {
      status.value = SyncStatus.offline;
      return;
    }
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) syncNow();
    });
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _timer?.cancel();
      if (user != null) {
        syncNow();
        _timer = Timer.periodic(const Duration(minutes: 2), (_) => syncNow());
      } else {
        status.value = SyncStatus.offline;
      }
    }, onError: (e) => appLog('[sync] auth stream error: $e'));
  }

  /// Fire-and-forget; call after every local mutation.
  void syncSoon() {
    if (!_fbReady) return;
    Future.microtask(syncNow);
  }

  Future<void> syncNow() async {
    if (!_fbReady || _busy) return;
    try {
      if (FirebaseAuth.instance.currentUser == null) return;
    } catch (_) {
      return;
    }
    _busy = true;
    status.value = SyncStatus.syncing;
    try {
      final db = await DB.open();
      await _pushAll(db);
      await _pullAll(db);
      // GOAL 3 (v0.4.1): two phones can save the SAME bill/purchase
      // number while offline (MAX+1 is per-phone). After the pull,
      // heal duplicate numbers deterministically (oldest keeps the
      // number) and push the renumbered rows back right away so the
      // other phone converges on the next pull. Idempotent: a second
      // pass finds no duplicates and changes nothing.
      final renumbered = await Repo.instance.reconcileDuplicateNumbers();
      if (renumbered > 0) {
        appLog('[sync] renumbered $renumbered duplicate bill/purchase numbers');
        await _pushAll(db);
      }
      // Photos (billty / payment proof / purchase bill) are FILES, not
      // rows - they travel through Firebase Storage, compressed to
      // <= 300 KB client-side. Best-effort: a photo failure never
      // blocks or fails the data sync.
      try {
        await PhotoSyncService.instance.run(db);
      } catch (e) {
        appLog('[sync] photo step skipped: $e');
      }
      status.value = SyncStatus.synced;
      // Spec: verify the access rules on every background sync too
      // (status active / not expired / approved device). The admin
      // kill-switch reacts within one sync cycle as a safety net.
      await AccessService.instance.verifyOnce();
    } catch (e) {
      appLog('[sync] error: $e');
      status.value = SyncStatus.error;
    } finally {
      _busy = false;
    }
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await _connSub?.cancel();
  }

  // ---------- Firestore helpers ----------

  CollectionReference<Map<String, dynamic>> _coll(String name) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance.collection('shops').doc(uid).collection(name);
  }

  // ---------- PUSH ----------

  Future<void> _pushAll(Database db) async {
    await _pushFlat(db, 'customers');
    await _pushFlat(db, 'products');
    await _pushFlat(db, 'payments');
    await _pushFlat(db, 'suppliers');
    await _pushFlat(db, 'supplier_payments');
    await _pushFlat(db, 'bill_dispatch');
    await _pushBills(db);
    // v0.3.0: purchases with their items embedded (one document per
    // purchase bill, exactly like bills), plus purchase/sales returns
    // with their item lines embedded.
    await _pushWithItems(db, 'purchases', 'purchase_items', 'purchase_id', 200);
    await _pushWithItems(db, 'purchase_returns', 'purchase_return_items', 'return_id', 200);
    await _pushWithItems(db, 'sales_returns', 'sales_return_items', 'return_id', 200);
  }

  Future<void> _pushFlat(Database db, String table) async {
    final rows = await db.rawQuery('SELECT * FROM $table WHERE dirty = 1 LIMIT 400');
    if (rows.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final r in rows) {
      final map = Map<String, Object?>.from(r)..remove('dirty');
      batch.set(_coll(table).doc(map['id'] as String), map);
    }
    await batch.commit();
    final ids = rows.map((r) => _quote(r['id'] as String)).join(',');
    await db.execute('UPDATE $table SET dirty = 0 WHERE id IN ($ids)');
  }

  Future<void> _pushBills(Database db) async {
    final bills = await db.rawQuery('SELECT * FROM bills WHERE dirty = 1 LIMIT 200');
    if (bills.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    final ids = <String>[];
    for (final r in bills) {
      final map = Map<String, Object?>.from(r)..remove('dirty');
      final billId = map['id'] as String;
      final items = await db.rawQuery('SELECT * FROM bill_items WHERE bill_id = ?', [billId]);
      map['items'] = items.map((e) {
        final m = Map<String, Object?>.from(e)..remove('dirty');
        return m;
      }).toList();
      batch.set(_coll('bills').doc(billId), map);
      ids.add(billId);
    }
    await batch.commit();
    final idList = ids.map(_quote).join(',');
    await db.execute('UPDATE bills SET dirty = 0 WHERE id IN ($idList)');
    await db.execute('UPDATE bill_items SET dirty = 0 WHERE bill_id IN ($idList)');
  }

  // ---------- PULL ----------

  /// v0.2.20 FIX: PER-TABLE sync cursors. The old code shared ONE
  /// cursor across every table, so the cursor ran ahead to the newest
  /// row of the first table and every OLDER row of the later tables
  /// (a payment saved before the last customer edit, a bill older than
  /// the newest payment...) was silently skipped - FOREVER, because
  /// the cursor was saved. A fresh device (or a phone whose DB was
  /// quarantined) restored only a slice of the cloud data: customers
  /// arrived, bills/payments never did. Engine tests reproduce it.
  /// Old 'last_sync_ms' key is retired: missing per-table keys start at
  /// 0 = one full idempotent re-pull (last-write-wins re-apply heals
  /// every previously missed row) and then the per-table cursors are
  /// stored.
  Future<void> _pullAll(Database db) async {
    for (final table in [
      'customers', 'products', 'payments', 'bill_dispatch',
      'suppliers', 'supplier_payments', 'purchase_items',
      'purchase_return_items', 'sales_return_items',
    ]) {
      final last = int.tryParse(await Repo.instance.getMeta('last_sync_ms_$table') ?? '') ?? 0;
      final cursor = await _pullFlat(db, table, last);
      if (cursor > last) {
        await Repo.instance.setMeta('last_sync_ms_$table', '$cursor');
      }
    }
    // Header tables whose documents embed their item lines.
    for (final spec in [
      ('bills', 'bill_items', 'bill_id'),
      ('purchases', 'purchase_items', 'purchase_id'),
      ('purchase_returns', 'purchase_return_items', 'return_id'),
      ('sales_returns', 'sales_return_items', 'return_id'),
    ]) {
      final last = int.tryParse(
              await Repo.instance.getMeta('last_sync_ms_${spec.$1}') ?? '') ?? 0;
      final cursor = await _pullWithItems(db, spec.$1, spec.$2, spec.$3, last);
      if (cursor > last) {
        await Repo.instance.setMeta('last_sync_ms_${spec.$1}', '$cursor');
      }
    }
  }

  /// Pages with startAfterDocument (not a numeric where) so rows that
  /// share the exact same updated_at are never skipped at a page
  /// boundary inside one pull.
  /// Generic "header + item lines embedded in the document" push, used by
  /// bills, purchases and the two return ledgers.
  Future<void> _pushWithItems(Database db, String table, String itemsTable,
      String fkColumn, int limit) async {
    final heads = await db.rawQuery(
        'SELECT * FROM $table WHERE dirty = 1 LIMIT $limit');
    if (heads.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    final ids = <String>[];
    for (final r in heads) {
      final map = Map<String, Object?>.from(r)..remove('dirty');
      final id = map['id'] as String;
      final items = await db.rawQuery(
          'SELECT * FROM $itemsTable WHERE $fkColumn = ?', [id]);
      map['items'] = items.map((e) {
        final m = Map<String, Object?>.from(e)..remove('dirty');
        return m;
      }).toList();
      batch.set(_coll(table).doc(id), map);
      ids.add(id);
    }
    await batch.commit();
    final idList = ids.map(_quote).join(',');
    await db.execute('UPDATE $table SET dirty = 0 WHERE id IN ($idList)');
    await db.execute(
        'UPDATE $itemsTable SET dirty = 0 WHERE $fkColumn IN ($idList) AND is_deleted = 0');
    // tombstoned item lines must still travel once: push them flat so the
    // other device learns about the delete
    await _pushDeletedItemLines(db, itemsTable, fkColumn, ids);
  }

  /// Tombstoned item lines of freshly-pushed headers are pushed flat so
  /// the pen-edit/delete of a bill reaches the other device.
  Future<void> _pushDeletedItemLines(Database db, String itemsTable,
      String fkColumn, List<String> headIds) async {
    final idList = headIds.map(_quote).join(',');
    final rows = await db.rawQuery(
        'SELECT * FROM $itemsTable WHERE dirty = 1 AND $fkColumn IN ($idList)');
    if (rows.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final r in rows) {
      final map = Map<String, Object?>.from(r)..remove('dirty');
      batch.set(_coll(itemsTable).doc(map['id'] as String), map);
    }
    await batch.commit();
    await db.execute(
        'UPDATE $itemsTable SET dirty = 0 WHERE id IN (${rows.map((r) => _quote(r['id'] as String)).join(',')})');
  }

  Future<int> _pullFlat(Database db, String table, int after) async {
    var cursor = after;
    DocumentSnapshot<Map<String, dynamic>>? lastDoc;
    while (true) {
      Query<Map<String, dynamic>> q = _coll(table).orderBy('updated_at').limit(200);
      if (lastDoc != null) {
        q = q.startAfterDocument(lastDoc);
      } else if (after > 0) {
        q = q.startAfter([after]);
      }
      final snap = await q.get();
      for (final d in snap.docs) {
        final data = Map<String, dynamic>.from(d.data());
        data['id'] ??= d.id;
        await _applyRemote(db, table, data);
        final ua = _toInt(data['updated_at']);
        if (ua > cursor) cursor = ua;
      }
      if (snap.docs.length < 200) return cursor;
      lastDoc = snap.docs.last;
    }
  }

  /// Pull for header tables whose documents embed their item lines
  /// (bills since v1, purchases / returns since v0.3.0).
  Future<int> _pullWithItems(Database db, String table, String itemsTable,
      String fkColumn, int after) async {
    var cursor = after;
    DocumentSnapshot<Map<String, dynamic>>? lastDoc;
    while (true) {
      Query<Map<String, dynamic>> q = _coll(table).orderBy('updated_at').limit(100);
      if (lastDoc != null) {
        q = q.startAfterDocument(lastDoc);
      } else if (after > 0) {
        q = q.startAfter([after]);
      }
      final snap = await q.get();
      for (final d in snap.docs) {
        final data = Map<String, dynamic>.from(d.data());
        data['id'] ??= d.id;
        final itemsRaw = (data.remove('items') as List?) ?? const [];
        // v0.2.20 FIX: only replace local items when the remote header row
        // was ACTUALLY applied (strictly newer). The old code deleted and
        // re-inserted items unconditionally, so a remote snapshot that
        // LOST the last-write-wins race still destroyed the local item
        // lines of the winning row.
        final applied = await _applyRemote(db, table, data);
        if (applied) {
          final headId = data['id'] as String;
          await db.delete(itemsTable, where: '$fkColumn = ?', whereArgs: [headId]);
          for (final it in itemsRaw) {
            final m = Map<String, Object?>.from(it as Map);
            m['dirty'] = 0;
            m[fkColumn] ??= headId;
            await db.insert(itemsTable, m, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
        final ua = _toInt(data['updated_at']);
        if (ua > cursor) cursor = ua;
      }
      if (snap.docs.length < 100) return cursor;
      lastDoc = snap.docs.last;
    }
  }

  /// Last-write-wins: apply the remote row only when strictly newer.
  /// Returns true when the row was applied (or is brand new locally).
  Future<bool> _applyRemote(Database db, String table, Map<String, dynamic> data) async {
    final id = data['id'] as String;
    final remoteUa = _toInt(data['updated_at']);
    final local = await db.rawQuery('SELECT updated_at FROM $table WHERE id = ?', [id]);
    if (local.isNotEmpty) {
      final localUa = _toInt(local.first['updated_at']);
      if (remoteUa <= localUa) return false;
    }
    final row = Map<String, Object?>.from(data);
    row['dirty'] = 0;
    await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
    return true;
  }

  int _toInt(Object? v) => ((v ?? 0) as num).toInt();

  String _quote(String id) => "'${id.replaceAll("'", "''")}'";
}
