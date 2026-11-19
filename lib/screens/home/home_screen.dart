import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../data/repo.dart';
import '../../services/package_info_helper.dart';
import '../../services/remote_config.dart';
import '../../services/sync_service.dart';
import '../../services/update_service.dart';
import '../backup/backup_screen.dart';
import '../bills/bill_view_screen.dart';
import '../../widgets/widgets.dart';
import '../customer/customer_search_screen.dart';
import '../inventory/inventory_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/settings_screen.dart';
import '../sync/sync_status_screen.dart';

/// Home: Billing tab (today + yesterday bills) and Menu tab.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tab = 0;

  Map<String, List<Bill>> _bills = {};
  Map<String, (int, int)> _totals = {};
  Map<String, String> _cities = {}; // customerId -> city (bill tiles)
  bool _loading = true;
  bool _gating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    RemoteConfigService.instance.config.addListener(_onRemoteConfig);
    _reload();
    unawaited(_autoUpdateCheck());
    unawaited(_gateIfNeeded());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RemoteConfigService.instance.config.removeListener(_onRemoteConfig);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  Future<void> _reload() async {
    final keys = [Dt.todayKey(), Dt.yesterdayKey()];
    final bills = await Repo.instance.billsForDays(keys);
    final totals = await Repo.instance.dayTotals(keys);
    final cities = await Repo.instance.citiesFor(
      bills.values.expand((l) => l).map((b) => b.customerId),
    );
    if (!mounted) return;
    setState(() {
      _bills = bills;
      _totals = totals;
      _cities = cities;
      _loading = false;
    });
    SyncService.instance.syncSoon();
  }

  Future<void> _openNewBill() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CustomerSearchScreen(mode: CustomerSearchMode.pickForBilling)),
    );
    _reload();
  }

  Future<void> _openBill(Bill bill) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BillViewScreen(billId: bill.id)),
    );
    _reload();
  }

  Future<void> _checkUpdate() async {
    try {
      if (UpdateService.instance.readyPath.value != null) {
        await _showUpdateDialog(tag: UpdateService.instance.latestTag ?? '');
        return;
      }
      final (has, tag) = await UpdateService.instance.check();
      if (!mounted) return;
      if (has) {
        await _showUpdateDialog(tag: tag);
      } else {
        showSnack(context, 'You are on the latest version');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Could not check updates (offline?)', error: true);
    }
  }

  /// Silent update check (max once per 6 hours). If a newer release is
  /// out, its APK starts downloading in the background right away - the
  /// user later just taps "Install".
  Future<void> _autoUpdateCheck() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = sp.getInt('last_update_check') ?? 0;
      if (now - last < 6 * 3600 * 1000) return;
      await sp.setInt('last_update_check', now);
      final (has, _) = await UpdateService.instance.check();
      if (has) unawaited(UpdateService.instance.downloadApk());
    } catch (_) {
      // auto check must never disturb the user
    }
  }

  void _onRemoteConfig() => unawaited(_gateIfNeeded());

  /// Force-update gate driven by remote config `min_version`.
  Future<void> _gateIfNeeded() async {
    final min = RemoteConfigService.instance.config.value.minVersion;
    if (min.isEmpty || _gating) return;
    try {
      if (!await UpdateService.instance.updateRequired(min)) return;
    } catch (_) {
      return;
    }
    _gating = true;
    try {
      // Resolve the release and start the background download before the
      // gate dialog appears.
      await UpdateService.instance.check();
      unawaited(UpdateService.instance.downloadApk());
      if (!mounted) return;
      await _showUpdateDialog(tag: min, force: true);
    } catch (_) {
      // offline - the gate will retry on next open
    } finally {
      _gating = false;
    }
  }

  /// Download-progress dialog that turns into an Install button when the
  /// APK has landed. With force=true it cannot be dismissed.
  Future<void> _showUpdateDialog({required String tag, bool force = false}) {
    unawaited(UpdateService.instance.downloadApk());
    return showDialog<void>(
      context: context,
      barrierDismissible: !force,
      builder: (ctx) => PopScope(
        canPop: !force,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            force ? 'Update required (v$tag)' : 'Update available: v$tag',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          content: ValueListenableBuilder<String?>(
            valueListenable: UpdateService.instance.readyPath,
            builder: (context, path, _) {
              if (path != null) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_outline, color: Colors.green, size: 34),
                    const SizedBox(height: 12),
                    Text(
                      'v$tag downloaded and ready to install.',
                      style: const TextStyle(fontSize: 13.5, color: Ruby.muted),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => UpdateService.instance.install(),
                        icon: const Icon(Icons.install_mobile, size: 20),
                        label: const Text('Install now'),
                      ),
                    ),
                  ],
                );
              }
              return ValueListenableBuilder<bool>(
                valueListenable: UpdateService.instance.downloading,
                builder: (context, busy, _) => ValueListenableBuilder<double>(
                  valueListenable: UpdateService.instance.downloadProgress,
                  builder: (context, p, _) {
                    final failed = !busy && p == 0 && UpdateService.instance.lastError != null;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          force
                              ? 'A newer version is required. Downloading in background…'
                              : 'Downloading in background…',
                          style: const TextStyle(fontSize: 13.5, height: 1.45, color: Ruby.muted),
                        ),
                        const SizedBox(height: 14),
                        LinearProgressIndicator(
                          value: busy ? (p > 0 ? p : null) : 0.0,
                          minHeight: 6,
                          color: Ruby.ruby,
                          backgroundColor: Ruby.rubyLight,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          busy && p > 0
                              ? '${(p * 100).toStringAsFixed(0)}% downloaded'
                              : (failed ? 'Download failed (offline?)' : 'Starting download…'),
                          style: const TextStyle(fontSize: 12, color: Ruby.faint),
                        ),
                        if (failed) ...[
                          const SizedBox(height: 14),
                          OutlinedButton(
                            onPressed: () {
                              UpdateService.instance.lastError = null;
                              unawaited(UpdateService.instance.downloadApk());
                            },
                            child: const Text('Retry'),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              );
            },
          ),
          actions: [
            if (!force)
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Later')),
          ],
        ),
      ),
    );
  }

  Future<void> _about() async {
    final v = await PackageInfoHelper.version();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Ruby Invoice', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text(
          'Version $v\n\nOffline-first billing with exact paise-level ledger math, '
          'inventory auto-fill and Firebase sync across your devices.',
          style: const TextStyle(fontSize: 13.5, height: 1.5, color: Ruby.muted),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? 'Recent Bills' : 'Menu'),
        actions: const [SyncChip()],
      ),
      body: ValueListenableBuilder<RemoteConfig>(
        valueListenable: RemoteConfigService.instance.config,
        builder: (context, rc, _) => _tab == 0 ? _billingTab(rc) : _menuTab(rc),
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton(
              heroTag: 'home_fab',
              onPressed: _openNewBill,
              child: const Icon(Icons.add, size: 30),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), activeIcon: Icon(Icons.receipt_long), label: 'Billing'),
          BottomNavigationBarItem(icon: Icon(Icons.menu), label: 'Menu'),
        ],
      ),
    );
  }

  // ---------------- Billing tab ----------------

  Widget _billingTab(RemoteConfig rc) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Ruby.ruby));
    }
    final today = Dt.todayKey();
    final yesterday = Dt.yesterdayKey();
    final tToday = _totals[today] ?? (0, 0);
    final tYesterday = _totals[yesterday] ?? (0, 0);

    return RefreshIndicator(
      color: Ruby.ruby,
      onRefresh: _reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _noticeBanner(rc),
          _updateBanner(),
          _summaryCard(tToday, tYesterday),
          for (final key in [today, yesterday]) ...[
            SectionHeader(Dt.labelFor(key)),
            if ((_bills[key] ?? []).isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  key == today ? 'No bills yet today. Tap + to make one.' : 'No bills yesterday.',
                  style: const TextStyle(fontSize: 13, color: Ruby.muted),
                ),
              )
            else
              for (final bill in _bills[key]!) _billTile(bill),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _summaryCard((int, int) today, (int, int) yesterday) {
    (int, int) x = today;
    (int, int) y = yesterday;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Ruby.ruby,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(child: _stat('TODAY', x.$1, x.$2)),
          Container(width: 1, height: 36, color: Colors.white24),
          Expanded(child: _stat('YESTERDAY', y.$1, y.$2)),
        ],
      ),
    );
  }

  Widget _stat(String label, int count, int totalPaise) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Color(0xFFF3B7BC))),
        const SizedBox(height: 5),
        Text(Money.fmt(totalPaise),
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white)),
        const SizedBox(height: 3),
        Text('$count bill${count == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 11.5, color: Color(0xFFF3B7BC))),
      ],
    );
  }

  Widget _billTile(Bill bill) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Ruby.rubyLight,
        child: const Icon(Icons.receipt_long, color: Ruby.ruby, size: 20),
      ),
      title: Text(
        bill.customerName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: Ruby.ink),
      ),
      subtitle: Text(
        [
          if ((_cities[bill.customerId] ?? '').isNotEmpty) _cities[bill.customerId]!,
          Dt.fmtTime(DateTime.fromMillisecondsSinceEpoch(bill.billDate)),
        ].join('  •  '),
        style: const TextStyle(fontSize: 12.5, color: Ruby.muted),
      ),
      trailing: Text(
        Money.fmt(bill.totalPaise),
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: Ruby.ink),
      ),
      onTap: () => _openBill(bill),
    );
  }

  // ---------------- Banners ----------------

  Widget _noticeBanner(RemoteConfig rc) {
    if (rc.notice.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8D48B)),
      ),
      child: Row(
        children: [
          const Icon(Icons.campaign_outlined, size: 20, color: Color(0xFFB8860B)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              rc.notice,
              style: const TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF7A5C00)),
            ),
          ),
        ],
      ),
    );
  }

  /// Shows download progress / install tap-target while an OTA download
  /// is running in the background.
  Widget _updateBanner() {
    return ValueListenableBuilder<bool>(
      valueListenable: UpdateService.instance.downloading,
      builder: (context, busy, _) => ValueListenableBuilder<String?>(
        valueListenable: UpdateService.instance.readyPath,
        builder: (context, path, _) {
          if (!busy && path == null) return const SizedBox.shrink();
          return Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Ruby.rubyLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Ruby.ruby.withValues(alpha: 0.35)),
            ),
            child: path != null
                ? InkWell(
                    onTap: () => UpdateService.instance.install(),
                    child: Row(
                      children: [
                        const Icon(Icons.install_mobile, size: 20, color: Ruby.ruby),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'New version ready - tap to install',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700, color: Ruby.ink),
                          ),
                        ),
                      ],
                    ),
                  )
                : Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Ruby.ruby),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ValueListenableBuilder<double>(
                          valueListenable: UpdateService.instance.downloadProgress,
                          builder: (context, p, _) => Text(
                            'Downloading update…${p > 0 ? ' ${(p * 100).toStringAsFixed(0)}%' : ''}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700, color: Ruby.ink),
                          ),
                        ),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }

  // ---------------- Menu tab ----------------

  Widget _menuTab(RemoteConfig rc) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            if (rc.feature('inventory'))
              _menuCard(Icons.inventory_2_outlined, 'Inventory (Item Master)', () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const InventoryScreen()));
              }),
            if (rc.feature('ledger'))
              _menuCard(Icons.book_outlined, 'Customer Ledger (Jama / Udhar)', () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CustomerSearchScreen(mode: CustomerSearchMode.browse)),
                );
              }),
            if (rc.feature('reports'))
              _menuCard(Icons.ssid_chart, 'Sales Reports', () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen()));
              }),
            _menuCard(Icons.picture_as_pdf_outlined, 'Bill Format & PDF / Share', () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
            }),
            _menuCard(Icons.cloud_sync_outlined, 'Cloud Sync Status', () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SyncStatusScreen()));
            }),
            _menuCard(Icons.people_alt_outlined, 'Customers', () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CustomerSearchScreen(mode: CustomerSearchMode.browse)),
              );
            }),
          ],
        ),
        const SectionHeader('More'),
        Card(
          color: Colors.white,
          elevation: 1,
          shadowColor: Colors.black12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Ruby.line),
          ),
          child: Column(
            children: [
              if (rc.feature('backup')) ...[
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.backup_outlined, color: Ruby.ruby, size: 20),
                  title: const Text('Backup & Restore', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  trailing: const Icon(Icons.chevron_right, size: 18, color: Ruby.faint),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupScreen()));
                  },
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
              ],
              ListTile(
                dense: true,
                leading: const Icon(Icons.system_update_outlined, color: Ruby.ruby, size: 20),
                title: const Text('Check Updates', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                trailing: const Icon(Icons.chevron_right, size: 18, color: Ruby.faint),
                onTap: _checkUpdate,
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                dense: true,
                leading: const Icon(Icons.info_outline, color: Ruby.ruby, size: 20),
                title: const Text('About', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                trailing: const Icon(Icons.chevron_right, size: 18, color: Ruby.faint),
                onTap: _about,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _menuCard(IconData icon, String title, VoidCallback onTap) {
    return Card(
      color: Colors.white,
      elevation: 2,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Ruby.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 34, color: Ruby.ruby),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Ruby.ink),
            ),
          ],
        ),
      ),
    );
  }
}
