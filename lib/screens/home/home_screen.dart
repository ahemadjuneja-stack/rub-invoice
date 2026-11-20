import 'dart:async';
import '../../core/app_log.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../data/repo.dart';
import '../../services/bill_draft_service.dart';
import '../../services/package_info_helper.dart';
import '../../services/remote_config.dart';
import '../../services/sync_service.dart';
import '../../services/update_service.dart';
import '../accounts/accounts_screen.dart';
import '../bills/bill_view_screen.dart';
import '../billing/billing_screen.dart';
import '../../widgets/widgets.dart';
import '../customer/customer_search_screen.dart';
import '../inventory/inventory_screen.dart';
import '../purchase/purchase_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/app_settings_screen.dart';
import '../settings/settings_screen.dart';

/// Home: Billing tab (today + yesterday bills) and Menu tab.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tab = 0;

  bool _updateDialogOpen = false;

  /// Periodic background update check while the app stays open.
  Timer? _updateTimer;

  /// False until this app session has hit the network once - every
  /// fresh app open ALWAYS checks for a release, no throttle.
  bool _sessionChecked = false;

  /// Newest release known to be newer than the installed version. The
  /// home banner keeps offering it (tap to open the popup) even when
  /// the popup itself was closed or snoozed.
  String? _availableTag;

  /// An update that was found while the user was inside another screen
  /// (billing, inventory...). The popup never interrupts bill entry -
  /// it lands here and shows the moment the user is back on home.
  String? _deferredUpdateTag;

  Map<String, List<Bill>> _bills = {};
  Map<String, String> _cities = {}; // customerId -> city (bill tiles)
  BillDraft? _draft; // unfinished in-progress bill (auto-saved)
  bool _loading = true;
  bool _gating = false;

  /// v0.2.19: set when the data load fails - the list then shows a
  /// retry banner instead of a spinner that spins forever.
  String? _loadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    RemoteConfigService.instance.config.addListener(_onRemoteConfig);
    _reload();
    unawaited(_autoUpdateCheck());
    unawaited(_restorePendingUpdate());
    unawaited(_gateIfNeeded());
    // Keep looking for releases while the app is open - a new version
    // pops up on its own, no manual "Check Updates" needed.
    _updateTimer = Timer.periodic(
      const Duration(minutes: 20),
      (_) => unawaited(_autoUpdateCheck()),
    );
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    RemoteConfigService.instance.config.removeListener(_onRemoteConfig);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Coming back to the app (from launcher, call, WhatsApp...) is an
      // app-open moment: refresh data AND look for updates.
      _reload();
      unawaited(_autoUpdateCheck());
    }
  }

  Future<void> _reload() async {
    // v0.2.19: a failed DB read must NEVER leave the spinner spinning
    // forever (the exact bug users reported). Every path ends with
    // _loading = false and a visible error banner with a retry button.
    try {
      final keys = [Dt.todayKey(), Dt.yesterdayKey()];
      final bills = await Repo.instance.billsForDays(keys);
      final cities = await Repo.instance.citiesFor(
        bills.values.expand((l) => l).map((b) => b.customerId),
      );
      final draft = await BillDraftService.instance.load();
      if (!mounted) return;
      setState(() {
        _bills = bills;
        _cities = cities;
        _draft = (draft != null && draft.lines.isNotEmpty) ? draft : null;
        _loadError = null;
        _loading = false;
      });
    } catch (e) {
      appLog('[home] reload failed: $e');
      if (!mounted) return;
      setState(() {
        _loadError = 'Data could not load';
        _loading = false;
      });
    }
    SyncService.instance.syncSoon();
    unawaited(_refreshAvailableTag());
    _flushDeferredUpdate();
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

  /// True when the home screen itself is on top (user is not inside
  /// billing, inventory, ledger etc.). Auto popups must never disturb
  /// bill entry.
  bool _homeIsCurrentRoute() {
    if (!mounted) return false;
    return ModalRoute.of(context)?.isCurrent ?? false;
  }

  /// Shows a parked update popup as soon as the user is back on home.
  void _flushDeferredUpdate() {
    if (_updateDialogOpen || !_homeIsCurrentRoute()) return;
    final tag = _deferredUpdateTag;
    if (tag == null || tag.isEmpty) return;
    _deferredUpdateTag = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showUpdateDialog(tag: tag);
    });
  }

  /// Home banner data: reads the remembered update tag and compares it
  /// with the installed version.
  Future<void> _refreshAvailableTag() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final tag = sp.getString('known_update_tag') ?? '';
      final current = await PackageInfoHelper.version();
      if (!mounted) return;
      final has = tag.isNotEmpty && UpdateService.isNewerThan(tag, current);
      if (_availableTag != (has ? tag : null)) {
        setState(() => _availableTag = has ? tag : null);
      }
    } catch (_) {}
  }

  /// "Later" hides the popup for 12 hours - but a NEWER release always
  /// pops up immediately, snooze applies to that exact version only.
  Future<void> _snoozeCurrentUpdate() async {
    try {
      final tag = UpdateService.instance.latestTag ?? '';
      if (tag.isEmpty) return;
      final sp = await SharedPreferences.getInstance();
      await sp.setString('update_snooze_tag', tag);
      await sp.setInt(
        'update_snooze_until',
        DateTime.now().add(const Duration(hours: 12)).millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  bool _snoozed(String tag, SharedPreferences sp, int now) {
    final snoozeTag = sp.getString('update_snooze_tag') ?? '';
    final snoozeUntil = sp.getInt('update_snooze_until') ?? 0;
    return snoozeTag == tag && now < snoozeUntil;
  }

  /// Plan B when the system installer did not open. The most common
  /// cause: the "Install unknown apps" permission is missing - and it
  /// RESETS after Clear Data, the exact case users report as "update
  /// install nahi ho raha". Guide the user through the two taps and
  /// offer the plain browser download as a second way out.
  void _showInstallHelp(BuildContext dialogCtx) {
    showDialog<void>(
      context: dialogCtx,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        elevation: 12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.shield_outlined, color: Ruby.ruby, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'One permission needed',
                style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: Ruby.ink),
              ),
            ),
          ],
        ),
        content: const Text(
          'Android needs "Allow from this source" to install the update:\n\n'
          '1. Tap Install now again\n'
          '2. Android shows the permission screen -> turn it ON\n'
          '3. Come back and tap Install now\n\n'
          'If it still does not open, download the update in your browser '
          'and tap the downloaded file to install.',
          style: TextStyle(
              fontSize: 13.5, height: 1.5, color: Ruby.muted),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openApkInBrowser();
            },
            child: const Text('Download in browser',
                style: TextStyle(color: Ruby.ruby)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(backgroundColor: Ruby.ruby),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  /// Opens the release APK link in the external browser - a way to
  /// install that always works even when the in-app installer cannot.
  Future<void> _openApkInBrowser() async {
    final url = UpdateService.instance.apkDirectUrl;
    if (url == null || url.isEmpty) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      // browser not available - nothing else to do here
    }
  }

  /// Silent update check - runs on app open, on every resume and every
  /// 20 minutes while the app stays open (throttled to once per 15
  /// minutes). If a newer release is out, its APK starts downloading in
  /// the background right away and the popup shows on the main screen.
  Future<void> _autoUpdateCheck() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = sp.getInt('last_update_check') ?? 0;
      // First run after an install/update always checks immediately.
      final current = await PackageInfoHelper.version();
      final justUpdated = (sp.getString('last_update_check_version') ?? '') != current;
      // Every fresh app open checks the network once - the 15-minute
      // throttle only limits re-checks inside the SAME session (resume
      // / periodic timer). So a new release can never be missed.
      final firstOfSession = !_sessionChecked;
      _sessionChecked = true;
      if (!justUpdated && !firstOfSession && now - last < 15 * 60 * 1000) {
        _flushDeferredUpdate();
        return;
      }
      await sp.setInt('last_update_check', now);
      await sp.setString('last_update_check_version', current);
      final (has, tag) = await UpdateService.instance.check();
      if (!mounted) return;
      if (!has) {
        await _forgetUpdateTag();
        unawaited(_refreshAvailableTag());
        return;
      }
      await _rememberUpdateTag(tag);
      unawaited(_refreshAvailableTag());
      unawaited(UpdateService.instance.downloadApk());
      if (_snoozed(tag, sp, now)) {
        // Same version the user pushed away recently - stay quiet, but
        // keep the APK cached so "Check Updates" opens it instantly.
        return;
      }
      if (_homeIsCurrentRoute()) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showUpdateDialog(tag: tag);
        });
      } else {
        // Never interrupt bill entry - park it for the home screen.
        _deferredUpdateTag = tag;
      }
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
    _deferredUpdateTag = null;
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
                              onPressed: () async {
                                final ok =
                                    await UpdateService.instance.install();
                                if (!ok && mounted && context.mounted) {
                                  _showInstallHelp(ctx);
                                }
                              },
                              icon: const Icon(Icons.install_mobile, size: 20),
                              label: const Text('Install now'),
                            ),
                          ),
                          if (!force)
                            SizedBox(
                              width: double.infinity,
                              child: TextButton(
                                onPressed: () {
                                  _snoozeCurrentUpdate();
                                  Navigator.pop(ctx);
                                },
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
                                    onPressed: () {
                                      _snoozeCurrentUpdate();
                                      Navigator.pop(ctx);
                                    },
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

    return RefreshIndicator(
      color: Ruby.ruby,
      onRefresh: _reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _noticeBanner(rc),
          _updateBanner(),
          if (_loadError != null) _loadErrorBanner(),
          if (_draft != null) _draftBanner(_draft!),
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

  /// v0.2.19: visible failure state with a retry - a broken load can
  /// never again look like the app silently does nothing.
  Widget _loadErrorBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Ruby.ruby, width: 1.2),
      ),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.error_outline, color: Ruby.ruby),
        title: const Text(
          'Data could not load',
          style: TextStyle(
              fontSize: 13.5, fontWeight: FontWeight.w800, color: Ruby.ink),
        ),
        subtitle: const Text(
          'Your data is safe on this phone. Tap retry.',
          style: TextStyle(fontSize: 12, color: Ruby.muted),
        ),
        trailing: TextButton(
          onPressed: () {
            setState(() {
              _loading = true;
              _loadError = null;
            });
            _reload();
          },
          child: const Text('RETRY', style: TextStyle(color: Ruby.ruby)),
        ),
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
          if (!busy && path == null) {
            // Nothing downloading - but if a newer release is known,
            // keep a tappable banner on top so it can never be missed.
            final tag = _availableTag;
            if (tag == null || tag.isEmpty) return const SizedBox.shrink();
            return Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              decoration: BoxDecoration(
                color: Ruby.rubyLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Ruby.ruby.withValues(alpha: 0.35)),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _showUpdateDialog(tag: tag),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.new_releases_outlined, size: 20, color: Ruby.ruby),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'New version v$tag available - tap to update',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700, color: Ruby.ink),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
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
            _menuCard(Icons.people_alt_outlined, 'Customers', () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CustomerSearchScreen(mode: CustomerSearchMode.browse)),
              );
            }),
            if (rc.feature('ledger'))
              _menuCard(Icons.book_outlined, 'Customer Ledger (Jama / Udhar)', () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CustomerSearchScreen(mode: CustomerSearchMode.browse)),
                );
              }),
            if (rc.feature('inventory'))
              _menuCard(Icons.inventory_2_outlined, 'Inventory (Item Master)', () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const InventoryScreen()));
              }),
            _menuCard(Icons.local_shipping_outlined, 'Purchase Invoices', () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseScreen()));
            }),
            _menuCard(Icons.account_balance_wallet_outlined, 'Accounts (Hisab)', () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountsScreen()));
            }),
            if (rc.feature('reports'))
              _menuCard(Icons.ssid_chart, 'Sales Reports', () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen()));
              }),
            _menuCard(Icons.picture_as_pdf_outlined, 'Bill Format & PDF / Share', () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
            }),
            _menuCard(Icons.settings_outlined, 'Settings', () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AppSettingsScreen()));
            }),
          ],
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 14, 4, 0),
          child: Text(
            'Subscription, cloud sync, backup, updates & about live inside Settings.',
            style: TextStyle(fontSize: 11.5, color: Ruby.faint),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _menuCard(IconData icon, String title, VoidCallback onTap,
      {String? badge}) {
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
            if (badge != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Ruby.rubyLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: Ruby.ruby),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
