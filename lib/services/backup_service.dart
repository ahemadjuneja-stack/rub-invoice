import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../data/db.dart';
import '../data/repo.dart';

/// ZERO-DATA-LOSS Layer 3: local backup + export.
///
/// JSON backup (full): every business table, shareable to
/// WhatsApp/Drive/Telegram from the share sheet; restore replaces the
/// whole local database (then everything is marked dirty so the next
/// sync pushes it to Firebase as well).
///
/// v0.4.0: the table list is now COMPLETE - suppliers, supplier
/// payments, dispatch records, purchase/return item lines and sales
/// returns used to be MISSING from backups (they silently restored
/// incomplete shops). CSV export added for the ledgers people want to
/// open in Excel.
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  /// Parent tables FIRST (restore order: parents before item lines).
  /// v0.4.0 - COMPLETE list, matches every business table in db.dart.
  static const List<String> _tables = [
    'customers',
    'products',
    'suppliers',
    'bills',
    'bill_items',
    'payments',
    'purchases',
    'purchase_items',
    'purchase_returns',
    'purchase_return_items',
    'sales_returns',
    'sales_return_items',
    'supplier_payments',
    'bill_dispatch',
  ];

  /// Tables that carry money or items - CSV-exported for Excel.
  static const List<String> _csvTables = [
    'customers',
    'bills',
    'bill_items',
    'payments',
    'purchases',
    'purchase_items',
    'sales_returns',
    'sales_return_items',
    'supplier_payments',
  ];

  Future<File> exportToFile() async {
    final db = await DB.open();
    final tables = <String, dynamic>{};
    for (final t in _tables) {
      tables[t] = await db.rawQuery('SELECT * FROM $t');
    }
    final now = DateTime.now();
    final data = {
      'app': 'ruby_invoice',
      'schema': 2,
      'exported_at': now.toIso8601String(),
      'tables': tables,
    };
    final dir = await getTemporaryDirectory();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final f = File('${dir.path}/ruby_invoice_backup_$stamp.json');
    await f.writeAsString(jsonEncode(data), flush: true);
    await Repo.instance.setMeta('last_backup', now.millisecondsSinceEpoch.toString());
    return f;
  }

  Future<void> shareBackup() async {
    final f = await exportToFile();
    await Share.shareXFiles([XFile(f.path)], text: 'Ruby Invoice backup');
  }

  /// v0.4.0: Excel-friendly export. One CSV file per table (opened
  /// directly in Excel / Google Sheets), bundled into the share sheet
  /// together with the full JSON backup. Money is exported in rupees.
  Future<void> shareCsvExport() async {
    final db = await DB.open();
    final dir = await getTemporaryDirectory();
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final files = <XFile>[];
    for (final t in _csvTables) {
      final rows = await db.rawQuery('SELECT * FROM $t');
      if (rows.isEmpty) continue;
      final cols = (rows.first as Map<String, Object?>).keys.toList();
      final buf = StringBuffer();
      buf.writeln(cols.map(_csvCell).join(','));
      for (final r in rows) {
        buf.writeln(cols.map((c) => _csvCell(r[c])).join(','));
      }
      final f = File('${dir.path}/ruby_${t}_$stamp.csv');
      await f.writeAsString(buf.toString(), flush: true);
      files.add(XFile(f.path, mimeType: 'text/csv'));
    }
    if (files.isEmpty) {
      // Nothing to export yet - share one empty marker so the user
      // still sees a predictable result instead of silence.
      final f = File('${dir.path}/ruby_export_$stamp.csv');
      await f.writeAsString('no data yet - create a bill first', flush: true);
      files.add(XFile(f.path, mimeType: 'text/csv'));
    }
    await Repo.instance.setMeta('last_backup', now.millisecondsSinceEpoch.toString());
    await Share.shareXFiles(files,
        text: 'Ruby Invoice data export (Excel/CSV)');
  }

  String _csvCell(Object? v) {
    if (v == null) return '';
    final s = v.toString();
    return s.contains(',') || s.contains('"') || s.contains('\n')
        ? '"${s.replaceAll('"', '""')}"'
        : s;
  }

  Future<String?> pickBackupFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    return res?.files.single.path;
  }

  Future<int> restoreFrom(String path) async {
    final raw = await File(path).readAsString();
    final data = jsonDecode(raw) as Map<String, dynamic>;
    if (data['app'] != 'ruby_invoice') {
      throw Exception('This file is not a Ruby Invoice backup');
    }
    final tables = (data['tables'] ?? {}) as Map<String, dynamic>;
    final db = await DB.open();
    int count = 0;
    await db.transaction((txn) async {
      // Only wipe tables the backup actually captured, so restoring an
      // older backup (schema without purchases) never destroys newer data.
      for (final t in _tables) {
        if (tables.containsKey(t)) {
          await txn.delete(t);
        }
      }
      for (final t in _tables.reversed) {
        final rows = (tables[t] as List?) ?? const [];
        for (final r in rows) {
          final map = Map<String, Object?>.from(r as Map);
          await txn.insert(t, map, conflictAlgorithm: ConflictAlgorithm.replace);
          count++;
        }
      }
      // Mark everything dirty so the next sync re-uploads the restored data.
      for (final t in _tables) {
        try {
          await txn.execute('UPDATE $t SET dirty = 1');
        } catch (_) {
          // A table missing in this legacy DB version is skipped.
        }
      }
    });
    return count;
  }

  Future<int> lastBackupMs() async =>
      int.tryParse(await Repo.instance.getMeta('last_backup') ?? '') ?? 0;
}
