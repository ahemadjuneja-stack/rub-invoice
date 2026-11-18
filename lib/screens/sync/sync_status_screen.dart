import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repo.dart';
import '../../services/access_service.dart';
import '../../services/sync_service.dart';
import '../../widgets/widgets.dart';

/// Menu module: Cloud Sync Status.
/// Shows "All Data Synced" / "Offline Mode - Pending Sync" plus the
/// pending-changes count, last sync time, account + device slots, and a
/// manual SYNC NOW trigger.
class SyncStatusScreen extends StatefulWidget {
  const SyncStatusScreen({super.key});

  @override
  State<SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends State<SyncStatusScreen> {
  SyncStatus _status = SyncStatus.offline;
  int _pending = 0;
  int? _lastSync;
  String _deviceId = '';
  int _devicesUsed = 0;
  int _maxDevices = 2;
  bool _fbReady = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    SyncService.instance.status.addListener(_onSync);
    _load();
  }

  @override
  void dispose() {
    SyncService.instance.status.removeListener(_onSync);
    super.dispose();
  }

  void _onSync() {
    if (!mounted) return;
    setState(() {
      _status = SyncService.instance.status.value;
      _syncing = _status == SyncStatus.syncing;
    });
    _load();
  }

  Future<void> _load() async {
    final pending = await Repo.instance.getPendingDirtyCount();
    final lastRaw = await Repo.instance.getMeta('last_sync_ms');
    final devId = SyncService.instance.fbReady
        ? await AccessService.instance.deviceId()
        : '';
    final info = AccessService.instance.account.value;
    if (!mounted) return;
    setState(() {
      _pending = pending;
      _lastSync = int.tryParse(lastRaw ?? '');
      _deviceId = devId;
      _devicesUsed = info?.registeredDevices.length ?? 0;
      _maxDevices = info?.maxDevices ?? 2;
      _fbReady = SyncService.instance.fbReady;
    });
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    await SyncService.instance.syncNow();
    _onSync();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cloud Sync Status')),
      body: RefreshIndicator(
        color: Ruby.ruby,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _statusBanner(),
            const SizedBox(height: 12),
            _rowCard(
              icon: Icons.pending_actions_outlined,
              label: 'Pending changes',
              value: _pending == 0 ? 'Nothing pending' : '$_pending row(s) waiting to upload',
              highlight: _pending > 0,
            ),
            const SizedBox(height: 8),
            _rowCard(
              icon: Icons.history_outlined,
              label: 'Last successful sync',
              value: _lastSync == null
                  ? 'Never (no sync yet)'
                  : Dt.fmtDateTime(DateTime.fromMillisecondsSinceEpoch(_lastSync!)),
            ),
            const SizedBox(height: 8),
            _rowCard(
              icon: Icons.cloud_outlined,
              label: 'Firebase',
              value: _fbReady
                  ? 'Configured - signed in'
                  : 'Not configured (offline-only mode)',
              highlight: !_fbReady,
            ),
            const SizedBox(height: 12),
            if (_fbReady) ...[
              const SectionHeader('Device access'),
              _rowCard(
                icon: Icons.phone_android_outlined,
                label: 'This device ID',
                value: _deviceId.isEmpty ? '-' : _deviceId,
              ),
              const SizedBox(height: 8),
              _rowCard(
                icon: Icons.devices_other,
                label: 'Device slots',
                value: '$_devicesUsed of $_maxDevices used (max $_maxDevices allowed)',
                highlight: _devicesUsed >= _maxDevices,
              ),
              const SizedBox(height: 8),
              _rowCard(
                icon: Icons.storefront_outlined,
                label: 'Business',
                value: AccessService.instance.account.value?.businessName ?? '-',
              ),
              const SizedBox(height: 8),
              _rowCard(
                icon: Icons.phone_outlined,
                label: 'Account mobile number',
                value: AccessService.instance.account.value?.phone ?? '-',
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 6),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: (_syncing || !_fbReady) ? null : _syncNow,
              icon: _syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.sync, size: 20),
              label: Text(_fbReady ? 'SYNC NOW' : 'SYNC NOT AVAILABLE'),
            ),
            if (!_fbReady) ...[
              const SizedBox(height: 10),
              const Text(
                'Firebase is not configured yet, so the app runs fully '
                'offline and keeps every bill safely on this phone. '
                'After FIREBASE_SETUP.md is completed, this screen turns '
                'into the live sync dashboard.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: Ruby.faint, height: 1.5),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusBanner() {
    late final String title;
    late final String subtitle;
    late final Color bg;
    late final Color fg;
    late final IconData icon;
    switch (_status) {
      case SyncStatus.synced:
        title = 'All Data Synced';
        subtitle = 'Every bill, payment and inventory change is safe in the cloud.';
        bg = Ruby.greenLight;
        fg = Ruby.green;
        icon = Icons.cloud_done_outlined;
        break;
      case SyncStatus.syncing:
      case SyncStatus.offline:
        title = _fbReady ? 'Syncing...' : 'Offline Mode';
        subtitle = _fbReady
            ? 'Uploading and downloading the latest changes...'
            : 'Working locally - data will sync once Firebase is set up.';
        bg = Ruby.fieldBg;
        fg = Ruby.ink;
        icon = Icons.cloud_sync_outlined;
        break;
      case SyncStatus.error:
        title = 'Offline Mode - Pending Sync';
        subtitle =
            'No network right now. Keep billing normally - $_pending pending '
            'change(s) will upload automatically when you are back online.';
        bg = const Color(0xFFFFF7E0);
        fg = const Color(0xFFB8860B);
        icon = Icons.cloud_off_outlined;
        break;
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 40, color: fg),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: fg)),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, height: 1.4, color: Ruby.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rowCard({
    required IconData icon,
    required String label,
    required String value,
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: highlight ? Ruby.ruby : Ruby.line, width: highlight ? 1.2 : 1),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: Ruby.ruby),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1, color: Ruby.faint)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Ruby.ink),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
