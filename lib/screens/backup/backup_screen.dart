import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../services/backup_service.dart';
import '../../services/sync_service.dart';
import '../../widgets/widgets.dart';

/// Backup & restore. Export produces a single JSON file you can save to
/// Google Drive / WhatsApp; restore replaces the local database with it.
/// When Firebase is configured, data also syncs continuously.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  DateTime? _lastBackup;

  @override
  void initState() {
    super.initState();
    _loadLast();
  }

  Future<void> _loadLast() async {
    final ms = await BackupService.instance.lastBackupMs();
    if (!mounted) return;
    setState(() {
      _lastBackup = ms == 0 ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    });
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      await BackupService.instance.shareBackup();
      await _loadLast();
    } catch (e) {
      if (mounted) showSnack(context, 'Export failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final path = await BackupService.instance.pickBackupFile();
    if (path == null) return;
    if (!mounted) return;
    final ok = await confirmDialog(
      context,
      title: 'Replace all data?',
      message:
          'Restoring will DELETE everything currently in this phone and replace it with the '
          'backup file. Deleted data cannot be recovered. Continue?',
      ok: 'Restore',
      dangerous: true,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final count = await BackupService.instance.restoreFrom(path);
      SyncService.instance.syncSoon();
      if (mounted) showSnack(context, 'Restored $count records');
    } catch (e) {
      if (mounted) showSnack(context, 'Restore failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(
            icon: Icons.ios_share,
            title: 'Export backup',
            subtitle:
                'Creates one JSON file with all customers, products, bills and payments. '
                'Share it to Google Drive, WhatsApp or Telegram to keep it safe.',
            button: 'EXPORT & SHARE',
            onTap: _busy ? null : _export,
            accent: Ruby.ruby,
          ),
          const SizedBox(height: 14),
          _card(
            icon: Icons.restore,
            title: 'Restore from backup',
            subtitle:
                'Pick a previously exported Ruby Invoice backup file. This replaces all data '
                'on this phone (use carefully).',
            button: 'PICK FILE & RESTORE',
            onTap: _busy ? null : _restore,
            accent: Ruby.green,
          ),
          const SizedBox(height: 16),
          Text(
            _lastBackup == null
                ? 'Last export: never'
                : 'Last export: ${Dt.fmtDateTime(_lastBackup!)}',
            style: const TextStyle(fontSize: 12.5, color: Ruby.muted),
          ),
          const SizedBox(height: 20),
          if (SyncService.instance.fbReady) ...[
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.cloud_sync_outlined, color: Ruby.ruby),
              title: const Text('Firebase sync', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              subtitle: const Text(
                'Enabled: data syncs automatically to your other device(s) with the same number. '
                'Export is still recommended as an extra safety copy.',
                style: TextStyle(fontSize: 12.5, height: 1.4),
              ),
              trailing: TextButton(
                onPressed: () => SyncService.instance.syncNow(),
                child: const Text('Sync now'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _card({
    required IconData icon,
    required String title,
    required String subtitle,
    required String button,
    required VoidCallback? onTap,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Ruby.line),
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(backgroundColor: accent.withValues(alpha: 0.12), child: Icon(icon, color: accent)),
              const SizedBox(width: 12),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Ruby.ink)),
            ],
          ),
          const SizedBox(height: 10),
          Text(subtitle, style: const TextStyle(fontSize: 12.5, height: 1.45, color: Ruby.muted)),
          const SizedBox(height: 14),
          ElevatedButton(onPressed: onTap, child: Text(button, style: const TextStyle(fontSize: 13.5))),
        ],
      ),
    );
  }
}
