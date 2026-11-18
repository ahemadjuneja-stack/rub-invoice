import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/sync_service.dart';

/// Small reusable widgets shared across screens.

class SectionHeader extends StatelessWidget {
  final String text;
  final Color color;
  const SectionHeader(this.text, {super.key, this.color = Ruby.muted});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: color,
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const EmptyState({super.key, required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Ruby.faint),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Ruby.ink)),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Ruby.muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String ok = 'Confirm',
  bool dangerous = false,
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      content: Text(message, style: const TextStyle(fontSize: 13.5, height: 1.45, color: Ruby.muted)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(80, 42),
            backgroundColor: dangerous ? Colors.red : Ruby.ruby,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return res ?? false;
}

/// Live sync indicator for the home app bar: cloud_off / spinner /
/// cloud_done. Tap to force a sync. Shows nothing while Firebase is
/// not configured (pure offline mode).
class SyncChip extends StatelessWidget {
  const SyncChip({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = SyncService.instance;
    if (!svc.fbReady) return const SizedBox.shrink();
    return ValueListenableBuilder<SyncStatus>(
      valueListenable: svc.status,
      builder: (context, status, _) {
        late final Widget icon;
        String tip = 'Sync';
        switch (status) {
          case SyncStatus.offline:
            icon = const Icon(Icons.cloud_off_outlined, size: 20, color: Colors.white70);
            tip = 'Signed out';
            break;
          case SyncStatus.syncing:
            icon = const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            );
            tip = 'Syncing...';
            break;
          case SyncStatus.synced:
            icon = const Icon(Icons.cloud_done_outlined, size: 20, color: Colors.white);
            tip = 'Synced';
            break;
          case SyncStatus.error:
            icon = const Icon(Icons.cloud_off, size: 20, color: Color(0xFFFFC1C6));
            tip = 'Sync error - tap to retry';
            break;
        }
        return IconButton(
          tooltip: tip,
          icon: icon,
          onPressed: () async {
            await svc.syncNow();
          },
        );
      },
    );
  }
}

Future<void> showSnack(BuildContext context, String message, {bool error = false}) async {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? Colors.red.shade700 : null,
      duration: const Duration(seconds: 2),
    ),
  );
}
