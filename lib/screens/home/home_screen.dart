import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../data/repo.dart';
import '../../services/bill_draft_service.dart';
import '../../services/package_info_helper.dart';
import '../../services/remote_config.dart';
import '../../services/sync_service.dart';
import '../../services/update_service.dart';
import '../backup/backup_screen.dart';
import '../bills/bill_view_screen.dart';
import '../billing/billing_screen.dart';
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

  bool _updateDialogOpen = false;

  Map<String, List<Bill>> _bills = {};
  Map<String, (int, int)> _totals = {};
  Map<String, String> _cities = {}; // customerId -> city (bill tiles)
  BillDraft? _draft; // unfinished in-progress bill (auto-saved)
  bool _loading = true;
  bool _gating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    RemoteConfigService.instance.config.addListener(_onRemoteConfig);
    _reload();
    unawaited(_autoUpdateCheck());
    unawaited(_restorePendingUpdate());
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
    final draft = await BillDraftService.instance.load();
    if (!mounted) return;
    setState(() {
      _bills = bills;
      _totals = totals;
      _cities = cities;
      _draft = (draft != null && draft.lines.isNotEmpty) ? draft : null;
      _loading = false;
    });
    SyncService.instance.syncSoon();
  }

  /// Opens the auto-saved draft straight in the billing screen.
  Future<void> _resumeDraft() async {
    final d = _draft;
    if (d == null) return;
    final cust = await Repo.instance.getCustomer(d.customerId);
    if (!mounted) return;
    if (cust == null) {
      await BillDraftService.instance.clear();
      await _reload();
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BillingScreen(customer: cust)),
    );
    _reload();
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
        await _rememberUpdateTag(tag);
        await _showUpdateDialog(tag: tag);
      } else {
        await _forgetUpdateTag();
        showSnack(context, 'You are on the latest version');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Could not check updates (offline?)', error: true);
    }
  }

  Future<void> _rememberUpdateTag(String tag) async {
    if (tag.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('known_update_tag', tag);
    } catch (_) {}
  }

  Future<void> _forgetUpdateTag() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove('known_update_tag');
    } catch (_) {}
  }

  /// After an app restart: if an update APK was already downloaded but
  /// never installed, bring the popup back so the user can finish it.
  Future<void> _restorePendingUpdate() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final tag = sp.getString('known_update_tag') ?? '';
      if (tag.isEmpty) return;
      final current = await PackageInfoHelper.version();
      if (!UpdateService.isNewerThan(tag, current)) {
        await _forgetUpdateTag();
        return;
      }
      final ok = await UpdateService.instance.adoptCachedApk(tag);
      if (!mounted) return;
      if (ok) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showUpdateDialog(tag: tag);
        });
        return;
      }
      // Cached file was cleared by the OS - refresh the release quietly
      // and start the download again so the popup can offer it.
      final (has, t) = await UpdateService.instance.check();
      if (!mounted) return;
      if (!has) {
        await _forgetUpdateTag();
        return;
      }
      await _rememberUpdateTag(t);
      unawaited(UpdateService.instance.downloadApk());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showUpdateDialog(tag: t);
      });
    } catch (_) {
      // never disturb startup
    }
  }

  /// Silent update check (max once per 6 hours). If a newer release is
  /// out, its APK starts downloading in the background right away and
  /// the update popup is shown on the main screen.
  Future<void> _autoUpdateCheck() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = sp.getInt('last_update_check') ?? 0;
      // First run after an install/update always checks immediately,
      // bypassing the 6-hour throttle - so a freshly updated app looks
      // for an even newer release right away.
      final current = await PackageInfoHelper.version();
      final justUpdated = (sp.getString('last_update_check_version') ?? '') != current;
      if (!justUpdated && now - last < 6 * 3600 * 1000) return;
      await sp.setInt('last_update_check', now);
      await sp.setString('last_update_check_version', current);
      final (has, tag) = await UpdateService.instance.check();
      if (!mounted) return;
      if (!has) {
        await _forgetUpdateTag();
        return;
      }
      await _rememberUpdateTag(tag);
      unawaited(UpdateService.instance.downloadApk());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showUpdateDialog(tag: tag);
      });
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

  /// Ruby-branded update popup: white card, ruby badge, and a ruby
  /// loading line whose front edge shines while the APK downloads.
  /// With force=true it cannot be dismissed.
  Future<void> _showUpdateDialog({required String tag, bool force = false}) {
    if (_updateDialogOpen && !force) return Future.value();
    _updateDialogOpen = true;
    unawaited(UpdateService.instance.downloadApk());
    return showDialog<void>(
      context: context,
      barrierDismissible: !force,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => PopScope(
        canPop: !force,
        child: Dialog(
          backgroundColor: Colors.white,
          elevation: 14,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Ruby.rubyLight,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(Icons.rocket_launch_outlined,
                          color: Ruby.ruby, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            force ? 'Update required' : 'New update available',
                            style: const TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w800,
                                color: Ruby.ink),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Ruby Invoice v$tag',
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Ruby.ruby),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ValueListenableBuilder<String?>(
                  valueListenable: UpdateService.instance.readyPath,
                  builder: (context, path, _) {
                    if (path != null) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.check_circle_rounded,
                                  color: Ruby.ruby, size: 22),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Download complete - ready to install',
                                  style: TextStyle(
                                      fontSize: 13.5,
                                      height: 1.4,
                                      color: Ruby.muted),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: ElevatedButton.icon(
                              onPressed: () => UpdateService.instance.install(),
                              icon: const Icon(Icons.install_mobile, size: 20),
                              label: const Text('Install now'),
                            ),
                          ),
                          if (!force)
                            SizedBox(
                              width: double.infinity,
                              child: TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Later'),
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
                          final failed = !busy &&
                              p == 0 &&
                              UpdateService.instance.lastError != null;
                          final indeterminate = p <= 0 && !failed;
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                force
                                    ? 'A newer version is required to continue. Please wait...'
                                    : 'Downloading the new version in background...',
                                style: const TextStyle(
                                    fontSize: 13, height: 1.45, color: Ruby.muted),
                              ),
                              const SizedBox(height: 14),
                              RubyShimmerProgress(
                                value: indeterminate ? null : p,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text(
                                    failed
                                        ? 'Download failed (offline?)'
                                        : (busy
                                            ? 'Downloading update...'
                                            : 'Starting download...'),
                                    style: const TextStyle(
                                        fontSize: 12, color: Ruby.faint),
                                  ),
                                  const Spacer(),
                                  if (busy && p > 0)
                                    Text(
                                      '${(p * 100).toStringAsFixed(0)}%',
                                      style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w800,
                                          color: Ruby.ruby),
                                    ),
                                ],
                              ),
                              if (failed) ...[
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  height: 44,
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      UpdateService.instance.lastError = null;
                                      unawaited(UpdateService.instance
                                          .downloadApk());
                                    },
                                    icon: const Icon(Icons.refresh, size: 20),
                                    label: const Text('Retry'),
                                  ),
                                ),
                              ],
                              if (!force && !failed) ...[
                                const SizedBox(height: 4),
                                SizedBox(
                                  width: double.infinity,
                                  child: TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('Later'),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline, size: 12, color: Ruby.faint),
                    SizedBox(width: 5),
                    Text(
                      'Your data stays safe during updates',
                      style: TextStyle(fontSize: 11, color: Ruby.faint),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() => _updateDialogOpen = false);
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
      appBar: RubyAppBar(
        title: _tab == 0 ? 'Recent Bills' : 'Menu',
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
          if (_draft != null) _draftBanner(_draft!),
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

  /// "Resume unfinished bill" tile for the auto-saved draft.
  Widget _draftBanner(BillDraft d) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Ruby.ruby, width: 1.2),
      ),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.receipt_long, color: Ruby.ruby),
        title: const Text(
          'Resume unfinished bill',
          style: TextStyle(
              fontSize: 13.5, fontWeight: FontWeight.w800, color: Ruby.ruby),
        ),
        subtitle: Text(
          '${d.customerName}  •  ${Money.fmt(d.totalPaise)}  •  tap to continue',
          style: const TextStyle(fontSize: 12, color: Ruby.muted),
        ),
        trailing: const Icon(Icons.arrow_forward, size: 18, color: Ruby.ruby),
        onTap: _resumeDraft,
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
