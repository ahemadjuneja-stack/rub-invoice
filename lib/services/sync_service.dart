import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../data/db.dart';
import '../data/repo.dart';
import 'access_service.dart';

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

  bool _fbReady = false;
  bool _busy = false;
  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  bool get fbReady => _fbReady;

  bool get signedIn {
    if (!_fbReady) return false;
    try {
      return FirebaseAuth.instance.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> configure({required bool fbReady}) async {
    _fbReady = fbReady;
    if (!_fbReady) {
      status.value = SyncStatus.offline;
      return;
    }
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) syncNow();
    });
    FirebaseAuth.instance.authStateChanges().listen((user) {
      _timer?.cancel();
      if (user != null) {
        syncNow();
        _timer = Timer.periodic(const Duration(minutes: 2), (_) => syncNow());
      } else {
        status.value = SyncStatus.offline;
      }
    });
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
      status.value = SyncStatus.synced;
      // Spec: verify the access rules on every background sync too
      // (status active / not expired / approved device). The admin
      // kill-switch reacts within one sync cycle as a safety net.
      await AccessService.instance.verifyOnce();
    } catch (e) {
      debugPrint('[sync] error: $e');
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
    await _pushFlat(db, 'purchases');
    await _pushBills(db);
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

  Future<void> _pullAll(Database db) async {
    final last = int.tryParse(await Repo.instance.getMeta('last_sync_ms') ?? '') ?? 0;
    var cursor = last;
    for (final table in ['customers', 'products', 'payments', 'purchases']) {
      cursor = await _pullFlat(db, table, cursor);
    }
    cursor = await _pullBills(db, cursor);
    await Repo.instance.setMeta('last_sync_ms', '${cursor > 0 ? cursor : DateTime.now().millisecondsSinceEpoch}');
  }

  Future<int> _pullFlat(Database db, String table, int after) async {
    var cursor = after;
    while (true) {
      final snap = await _coll(table)
          .where('updated_at', isGreaterThan: cursor)
          .orderBy('updated_at')
          .limit(200)
          .get();
      for (final d in snap.docs) {
        final data = Map<String, dynamic>.from(d.data());
        data['id'] ??= d.id;
        await _applyRemote(db, table, data);
        final ua = _toInt(data['updated_at']);
        if (ua > cursor) cursor = ua;
      }
      if (snap.docs.length < 200) return cursor;
    }
  }

  Future<int> _pullBills(Database db, int after) async {
    var cursor = after;
    while (true) {
      final snap = await _coll('bills')
          .where('updated_at', isGreaterThan: cursor)
          .orderBy('updated_at')
          .limit(100)
          .get();
      for (final d in snap.docs) {
        final data = Map<String, dynamic>.from(d.data());
        data['id'] ??= d.id;
        final itemsRaw = (data.remove('items') as List?) ?? const [];
        await _applyRemote(db, 'bills', data);

        // Replace local items with the embedded snapshot.
        final billId = data['id'] as String;
        await db.delete('bill_items', where: 'bill_id = ?', whereArgs: [billId]);
        for (final it in itemsRaw) {
          final m = Map<String, Object?>.from(it as Map);
          m['dirty'] = 0;
          m['bill_id'] ??= billId;
          await db.insert('bill_items', m, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        final ua = _toInt(data['updated_at']);
        if (ua > cursor) cursor = ua;
      }
      if (snap.docs.length < 100) return cursor;
    }
  }

  /// Last-write-wins: apply the remote row only when strictly newer.
  Future<void> _applyRemote(Database db, String table, Map<String, dynamic> data) async {
    final id = data['id'] as String;
    final remoteUa = _toInt(data['updated_at']);
    final local = await db.rawQuery('SELECT updated_at FROM $table WHERE id = ?', [id]);
    if (local.isNotEmpty) {
      final localUa = _toInt(local.first['updated_at']);
      if (remoteUa <= localUa) return;
    }
    final row = Map<String, Object?>.from(data);
    row['dirty'] = 0;
    await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  int _toInt(Object? v) => ((v ?? 0) as num).toInt();

  String _quote(String id) => "'${id.replaceAll("'", "''")}'";
}
