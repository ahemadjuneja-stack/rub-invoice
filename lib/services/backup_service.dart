import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../data/db.dart';
import '../data/repo.dart';

/// JSON backup: share the file to WhatsApp/Drive/Telegram from the share
/// sheet; restore replaces the whole local database (then everything is
/// marked dirty so the next sync pushes it to Firebase as well).
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const _tables = ['payments', 'bill_items', 'bills', 'products', 'customers'];

  Future<File> exportToFile() async {
    final db = await DB.open();
    final tables = <String, dynamic>{};
    for (final t in ['customers', 'products', 'bills', 'bill_items', 'payments']) {
      tables[t] = await db.rawQuery('SELECT * FROM $t');
    }
    final now = DateTime.now();
    final data = {
      'app': 'ruby_invoice',
      'schema': 1,
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
      for (final t in _tables) {
        await txn.delete(t);
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
      for (final t in ['customers', 'products', 'bills', 'bill_items', 'payments']) {
        await txn.execute('UPDATE $t SET dirty = 1');
      }
    });
    return count;
  }

  Future<int> lastBackupMs() async =>
      int.tryParse(await Repo.instance.getMeta('last_backup') ?? '') ?? 0;
}
