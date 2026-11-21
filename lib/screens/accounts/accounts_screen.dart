import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repo.dart';
import '../../widgets/widgets.dart';

/// ACCOUNTS (Hisab) - THE single place for every number of the shop.
/// Sales, sales returns, purchases, purchase returns, money in and
/// money out all live HERE - there is no separate sales-report screen
/// any more, nothing is scattered around (v0.3.1).
///
/// Two periods side by side: This Month and the Indian financial year
/// (April - March). Older years appear in the selector only when
/// old-dated data actually exists. The NET row is the one figure that
/// adds it all up: money in minus money out for the chosen period.
class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  int _udhaar = 0;
  int _purchasesAll = 0;
  int _inMonth = 0;
  int _outMonth = 0;
  int _inFy = 0;
  int _outFy = 0;
  ({int sales, int salesReturns, int purchases, int purchaseReturns})?
      _monthTotals;
  ({int sales, int salesReturns, int purchases, int purchaseReturns})?
      _fyTotals;
  int _fy = Dt.fyStartYear(DateTime.now());
  List<int> _fyChoices = [Dt.fyStartYear(DateTime.now())];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 1); // exclusive
    final fyStart = Dt.fyStart(_fy);
    final fyEnd = Dt.fyEndExclusive(_fy); // exclusive

    final udhaar = await Repo.instance.totalUdhaar();
    final purchasesAll = await Repo.instance.totalPurchases();
    final (mi, mo) = await Repo.instance.inOutForRange(
      monthStart.millisecondsSinceEpoch,
      monthEnd.millisecondsSinceEpoch,
    );
    final (fi, fo) = await Repo.instance.inOutForRange(
      fyStart.millisecondsSinceEpoch,
      fyEnd.millisecondsSinceEpoch,
    );
    final monthTotals = await Repo.instance.salesTotalsForRange(
      monthStart.millisecondsSinceEpoch,
      monthEnd.millisecondsSinceEpoch,
    );
    final fyTotals = await Repo.instance.salesTotalsForRange(
      fyStart.millisecondsSinceEpoch,
      fyEnd.millisecondsSinceEpoch,
    );
    final first = await Repo.instance.firstTransactionMs();

    // FY choices: current FY at the top, going back only as far as the
    // oldest year that actually holds data.
    final curFy = Dt.fyStartYear(now);
    final startFy =
        first > 0 ? Dt.fyStartYear(DateTime.fromMillisecondsSinceEpoch(first)) : curFy;
    final choices = [for (int y = curFy; y >= startFy; y--) y];

    if (!mounted) return;
    setState(() {
      _udhaar = udhaar;
      _purchasesAll = purchasesAll;
      _inMonth = mi;
      _outMonth = mo;
      _inFy = fi;
      _outFy = fo;
      _monthTotals = monthTotals;
      _fyTotals = fyTotals;
      _fyChoices = choices;
      if (!choices.contains(_fy)) _fy = curFy;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Scaffold(
      appBar: const RubyAppBar(
          title: 'Accounts (Hisab)',
          subtitle: 'Sales, purchases, returns - everything in one place'),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Ruby.ruby))
          : RefreshIndicator(
              color: Ruby.ruby,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _udhaarCard(),
                  const SizedBox(height: 12),
                  _purchasesCard(),
                  const SizedBox(height: 16),
                  SectionHeader('This Month - ${Dt.months[now.month - 1]} ${now.year}'),
                  const SizedBox(height: 6),
                  _periodCard(
                    totals: _monthTotals,
                    moneyIn: _inMonth,
                    moneyOut: _outMonth,
                  ),
                  const SizedBox(height: 16),
                  SectionHeader('Financial Year (April - March)'),
                  const SizedBox(height: 6),
                  _fySelector(),
                  const SizedBox(height: 8),
                  _periodCard(
                    totals: _fyTotals,
                    moneyIn: _inFy,
                    moneyOut: _outFy,
                  ),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'Bills dated after 31 March go into the next financial year. '
                      'To see an older year, pick it above - old years appear only '
                      'when they hold data.',
                      style: TextStyle(fontSize: 11, height: 1.5, color: Ruby.faint),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _udhaarCard() {
    final advance = _udhaar < 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        color: advance ? Ruby.green : Ruby.ruby,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            advance ? 'TOTAL ADVANCE (JAMA EXTRA)' : 'TOTAL UDHAAR (TO COLLECT)',
            style: const TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: Color(0xFFF3B7BC)),
          ),
          const SizedBox(height: 6),
          Text(
            Money.fmt(_udhaar.abs()),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white),
          ),
          const SizedBox(height: 2),
          const Text(
            'All customers - opening balance + bills - payments - sales returns',
            style: TextStyle(fontSize: 11.5, color: Color(0xFFF3B7BC)),
          ),
        ],
      ),
    );
  }

  Widget _purchasesCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Ruby.line),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 19,
            backgroundColor: Ruby.rubyLight,
            child: Icon(Icons.local_shipping_outlined, size: 20, color: Ruby.ruby),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('TOTAL PURCHASES',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        color: Ruby.muted)),
                const SizedBox(height: 3),
                Text(Money.fmt(_purchasesAll),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Ruby.ink)),
                const Text('All time - every purchase invoice with GST and parcel',
                    style: TextStyle(fontSize: 11, color: Ruby.faint)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// ONE card with every number of the period - nothing scattered:
  ///   Sales / Sales returns / Purchases / Purchase returns
  ///   Money in (payments) / Money out (purchases)
  ///   NET = money in - money out (the one figure of the period)
  Widget _periodCard({
    required ({int sales, int salesReturns, int purchases, int purchaseReturns})?
        totals,
    required int moneyIn,
    required int moneyOut,
  }) {
    final t = totals ??
        (sales: 0, salesReturns: 0, purchases: 0, purchaseReturns: 0);
    final net = moneyIn - moneyOut;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Ruby.line),
      ),
      child: Column(
        children: [
          _row('Sales (bills)', t.sales),
          _row('Sales returns (credit)', -t.salesReturns,
              green: t.salesReturns > 0),
          _row('Purchases', t.purchases),
          _row('Purchase returns (credit)', -t.purchaseReturns,
              green: t.purchaseReturns > 0),
          const Divider(height: 14),
          Row(
            children: [
              Expanded(
                child: _flow(Icons.south_west, 'MONEY IN', moneyIn, Ruby.green),
              ),
              Container(width: 1, height: 38, color: Ruby.line),
              Expanded(
                child:
                    _flow(Icons.north_east, 'MONEY OUT', moneyOut, Ruby.ruby),
              ),
            ],
          ),
          const Divider(height: 14),
          Row(
            children: [
              const Expanded(
                child: Text('NET (money in - money out)',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: Ruby.ruby)),
              ),
              Text(
                Money.fmt(net),
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  color: net >= 0 ? Ruby.green : Ruby.ruby,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, int paise, {bool green = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 12.5, color: Ruby.muted)),
          ),
          Text(
            Money.fmt(paise),
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: green ? Ruby.green : Ruby.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _flow(IconData icon, String label, int paise, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: color)),
                const SizedBox(height: 3),
                Text(Money.fmt(paise),
                    style: const TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: Ruby.ink)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fySelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Ruby.line),
        borderRadius: BorderRadius.circular(10),
        color: Ruby.fieldBg,
      ),
      child: DropdownButton<int>(
        value: _fy,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        icon: const Icon(Icons.keyboard_arrow_down, color: Ruby.ruby),
        items: [
          for (final y in _fyChoices)
            DropdownMenuItem(
              value: y,
              child: Text(
                Dt.fyLabel(y),
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Ruby.ink),
              ),
            ),
        ],
        onChanged: (y) {
          if (y == null || y == _fy) return;
          setState(() => _fy = y);
          _load();
        },
      ),
    );
  }
}
