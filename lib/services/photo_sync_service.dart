import 'dart:io';
import '../core/app_log.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../data/repo.dart';
import 'sync_service.dart';

/// Cloud sync for the photos (Bilty / transport receipts, payment-proof
/// screenshots, purchase-bill photos).
///
/// Why a separate service: SyncService pushes TABLE ROWS; photos are
/// FILES. SQLite stores the local path only, so the same row on the
/// other phone has a path that does not exist on that phone.
///
/// Design (keeps the row documents untouched):
///   * UPLOAD: every synced row whose photo path is set and whose file
///     exists gets its image compressed to <= 300 KB (client-side, saves
///     bandwidth + storage cost) and uploaded to
///     Firebase Storage: shops/{uid}/photos/{table}_{rowId}.jpg
///     A tiny marker document in shops/{uid}/photos keeps the download
///     URL; a local meta key (ph_up_...) stops re-uploads until the row
///     changes again.
///   * DOWNLOAD: on every sync the photos collection is read once; any
///     local row whose photo file is MISSING (fresh install, 2nd phone,
///     after APK update) fetches the URL and rebuilds the file locally
///     so both devices show identical live data.
///   * 45-DAY RULE: billty photos honour the same retention everywhere -
///     expired billties are never uploaded again, and a device that
///     pulls an expired cloud copy deletes it from Storage + Firestore.
///     Payment proofs / purchase photos have no expiry.
class PhotoSyncService {
  PhotoSyncService._();
  static final PhotoSyncService instance = PhotoSyncService._();

  static const int maxBytes = 300 * 1024; // 300 KB - the upload spec

  /// (table, path column, cloud folder the local file is rebuilt in)
  static const _specs = <_PhotoSpec>[
    _PhotoSpec('bill_dispatch', 'billty_path', 'billty_photos', has45DayExpiry: true),
    _PhotoSpec('payments', 'proof_path', 'payment_proofs'),
    _PhotoSpec('purchases', 'photo_path', 'purchase_photos'),
  ];

  bool get _ready => SyncService.instance.fbReady && SyncService.instance.signedIn;

  /// Called from SyncService.syncNow() AFTER push + pull.
  Future<void> run(Database db) async {
    if (!_ready) return;
    final uid = FirebaseAuth.instance.currentUser!.uid;
    try {
      await _uploadPending(db, uid);
    } catch (e) {
      appLog('[photo-sync] upload: $e');
    }
    try {
      await _downloadMissing(db, uid);
    } catch (e) {
      appLog('[photo-sync] download: $e');
    }
  }

  // ------------------------------------------------------------------
  // UPLOAD
  // ------------------------------------------------------------------

  Future<void> _uploadPending(Database db, String uid) async {
    final storage = FirebaseStorage.instance;
    final fs = FirebaseFirestore.instance;
    for (final spec in _specs) {
      final rows = await db.rawQuery(
        "SELECT id, ${spec.pathCol} AS p, updated_at FROM ${spec.table} "
        "WHERE is_deleted = 0 AND ${spec.pathCol} != '' LIMIT 50",
      );
      for (final r in rows) {
        final id = r['id'] as String;
        final path = (r['p'] ?? '') as String;
        final updatedAt = ((r['updated_at'] ?? 0) as num).toInt();
        final key = '${spec.table}_$id';
        final marker = await Repo.instance.getMeta('ph_up_$key');
        if (marker == '$updatedAt') continue; // already in the cloud

        final f = File(path);
        if (!f.existsSync()) continue; // gone locally (45-day cleanup etc.)

        // Billty photos older than 45 days are never re-synced.
        if (spec.has45DayExpiry) {
          final atRow = await db.rawQuery(
            'SELECT billty_at FROM bill_dispatch WHERE id = ?',
            [id],
          );
          final at = atRow.isEmpty ? 0 : ((atRow.first['billty_at'] ?? 0) as num).toInt();
          final cutoff =
              DateTime.now().millisecondsSinceEpoch - Repo.billtyRetentionDays * 86400000;
          if (at > 0 && at < cutoff) {
            // Expired: clear the cloud copy (from any device).
            try {
              await storage.ref('shops/$uid/photos/$key.jpg').delete();
            } catch (_) {}
            try {
              await fs.collection('shops').doc(uid).collection('photos').doc(key).delete();
            } catch (_) {}
            continue;
          }
        }

        final bytes = await _compressUnder300KB(f);
        if (bytes == null) continue;
        final ref = storage.ref('shops/$uid/photos/$key.jpg');
        await ref.putData(
          bytes,
          SettableMetadata(contentType: 'image/jpeg', customMetadata: {
            'table': spec.table,
            'rowId': id,
          }),
        );
        final url = await ref.getDownloadURL();
        await fs.collection('shops').doc(uid).collection('photos').doc(key).set({
          'table': spec.table,
          'rowId': id,
          'url': url,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        });
        await Repo.instance.setMeta('ph_up_$key', '$updatedAt');
      }
    }
  }

  /// Client-side compression to the 300 KB budget (spec). Pure Dart:
  /// decode once, downscale progressively and re-encode until the bytes
  /// fit. Returns null when the file cannot be read at all.
  Future<Uint8List?> _compressUnder300KB(File f) async {
    Uint8List orig;
    try {
      orig = await f.readAsBytes();
    } catch (_) {
      return null;
    }
    if (orig.lengthInBytes <= maxBytes) return orig;

    final decoded = await compute(_decodeImage, orig);
    if (decoded == null) return null; // undecodable - best effort

    Uint8List out = orig;
    int quality = 78;
    int side = 1600; // longest-edge start scale
    for (var i = 0; i < 10; i++) {
      // Keep the aspect ratio: scale the LONGER edge to `side`.
      final long = decoded.width > decoded.height ? decoded.width : decoded.height;
      final factor = long > side ? side / long : 1.0;
      final scaled = img.copyResize(
        decoded,
        width: (decoded.width * factor).round(),
        height: (decoded.height * factor).round(),
      );
      out = Uint8List.fromList(img.encodeJpg(scaled, quality: quality));
      if (out.lengthInBytes <= maxBytes) return out;
      side = (side * 0.8).toInt(); // shrink and try again
      if (side < 320) quality = 55;
      if (side < 200) break;
    }
    return out; // best effort even if slightly over
  }

  static img.Image? _decodeImage(Uint8List bytes) => img.decodeImage(bytes);

  // ------------------------------------------------------------------
  // DOWNLOAD
  // ------------------------------------------------------------------

  Future<void> _downloadMissing(Database db, String uid) async {
    final storage = FirebaseStorage.instance;
    final fs = FirebaseFirestore.instance;
    final snap = await fs
        .collection('shops')
        .doc(uid)
        .collection('photos')
        .limit(200)
        .get();

    for (final doc in snap.docs) {
      final key = doc.id; // '<table>_<rowId>'
      final spec = _specs.where((s) => key.startsWith('${s.table}_')).toList();
      if (spec.isEmpty) continue;
      final s = spec.first;
      final rowId = key.substring('${s.table}_'.length);

      final rows = await db.rawQuery(
        'SELECT id, ${s.pathCol} AS p FROM ${s.table} WHERE id = ? LIMIT 1',
        [rowId],
      );
      if (rows.isEmpty) continue;
      final localPath = (rows.first['p'] ?? '') as String;
      if (localPath.isEmpty) continue;
      if (File(localPath).existsSync()) continue; // already here

      final url = doc.data()['url'] as String?;
      if (url == null || url.isEmpty) continue;

      // Fetch the bytes through the Storage SDK (respects the rules).
      try {
        final ref = storage.refFromURL(url);
        final data = await ref.getData(1024 * 1024); // 1 MB hard cap
        if (data == null || data.isEmpty) continue;

        final dir = await _ensureDir(s.folder);
        final file = File('${dir.path}$Platform.pathSeparator$key.jpg');
        await file.writeAsBytes(data);

        // dirty stays 0: the ROW content did not change, only this
        // phone's local copy of the file - no re-push churn.
        await db.update(
          s.table,
          {s.pathCol: file.path},
          where: 'id = ?',
          whereArgs: [rowId],
        );
      } catch (_) {
        // Offline / rules denied - retried on the next sync tick.
      }
    }
  }

  Future<Directory> _ensureDir(String folder) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}$folder');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }
}

class _PhotoSpec {
  final String table;
  final String pathCol;
  final String folder;
  final bool has45DayExpiry;
  const _PhotoSpec(this.table, this.pathCol, this.folder, {this.has45DayExpiry = false});
}