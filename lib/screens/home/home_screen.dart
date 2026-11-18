import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../data/repo.dart';
import '../../services/package_info_helper.dart';
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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    if (!mounted) return;
    setState(() {
      _bills = bills;
      _totals = totals;
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
      final (has, tag, url) = await UpdateService.instance.check();
      if (!mounted) return;
      if (has) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Update available: $tag', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            content: const Text(
              'A newer version of Ruby Invoice has been published. '
              'Open the release page to download and install the APK.',
              style: TextStyle(fontSize: 13.5, height: 1.45, color: Ruby.muted),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Later')),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  UpdateService.instance.openRelease(url);
                },
                child: const Text('Open release'),
              ),
            ],
          ),
        );
      } else {
        showSnack(context, 'You are on the latest version');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Could not check updates (offline?)', error: true);
    }
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
      body: _tab == 0 ? _billingTab() : _menuTab(),
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

  Widget _billingTab() {
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
        '#${bill.billNo}  •  ${Dt.fmtTime(DateTime.fromMillisecondsSinceEpoch(bill.billDate))}',
        style: const TextStyle(fontSize: 12.5, color: Ruby.muted),
      ),
      trailing: Text(
        Money.fmt(bill.totalPaise),
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: Ruby.ink),
      ),
      onTap: () => _openBill(bill),
    );
  }

  // ---------------- Menu tab ----------------

  Widget _menuTab() {
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
            _menuCard(Icons.inventory_2_outlined, 'Inventory (Item Master)', () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const InventoryScreen()));
            }),
            _menuCard(Icons.book_outlined, 'Customer Ledger (Jama / Udhar)', () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CustomerSearchScreen(mode: CustomerSearchMode.browse)),
              );
            }),
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
