import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repo.dart';
import '../common/widgets.dart';
import '../ledger/ledger_screen.dart';

/// Reports: monthly sales, customer-wise purchases (year & all-time) and
/// top selling items - the "saal me kitna maal liya" answers.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  late int _year = DateTime.now().year;
  List<(String, int, int)> _monthly = [];
  List<Map<String, Object?>> _customers = [];
  List<Map<String, Object?>> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final monthly = await Repo.instance.monthlySales(_year);
    final customers = await Repo.instance.customerSummaries(_year);
    final products = await Repo.instance.topProducts(_year);
    if (!mounted) return;
    setState(() {
      _monthly = monthly;
      _customers = customers;
      _products = products;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  List<int> get _years => [DateTime.now().year, DateTime.now().year - 1, DateTime.now().year - 2];

  int _monthTotal(String ym) {
    for (final (ym0, _, total) in _monthly) {
      if (ym0 == ym) return total;
    }
    return 0;
  }

  int _monthCount(String ym) {
    for (final (ym0, cnt, _) in _monthly) {
      if (ym0 == ym) return cnt;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reports'),
          bottom: TabBar(
            controller: _tabs,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: const Color(0xFFF3B7BC),
            labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            tabs: const [
              Tab(text: 'Monthly'),
              Tab(text: 'Customers'),
              Tab(text: 'Top Items'),
            ],
          ),
        ),
        body: Column(
          children: [
            _yearSelector(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Ruby.ruby))
                  : TabBarView(
                      controller: _tabs,
                      children: [_monthlyTab(), _customersTab(), _productsTab()],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _yearSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          const Text('Year', style: TextStyle(fontSize: 13, color: Ruby.muted)),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Ruby.line),
              borderRadius: BorderRadius.circular(10),
              color: Ruby.fieldBg,
            ),
            child: DropdownButton<int>(
              value: _year,
              underline: const SizedBox.shrink(),
              items: [
                for (final y in _years) DropdownMenuItem(value: y, child: Text('$y')),
              ],
              onChanged: (y) {
                if (y == null || y == _year) return;
                setState(() => _year = y);
                _load();
              },
            ),
          ),
          const Spacer(),
          Text(
            'Total ${Money.fmt(_monthly.fold<int>(0, (s, e) => s + e.$3))}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Ruby.ink),
          ),
        ],
      ),
    );
  }

  // ---------------- monthly ----------------

  Widget _monthlyTab() {
    final maxTotal = _monthly.fold<int>(0, (m, e) => e.$3 > m ? e.$3 : m);
    final now = DateTime.now();
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (var m = 1; m <= 12; m++)
          _monthRow(m, maxTotal, isCurrent: _year == now.year && m == now.month),
      ],
    );
  }

  Widget _monthRow(int month, int maxTotal, {bool isCurrent = false}) {
    final ym = '$_year-${month.toString().padLeft(2, '0')}';
    final total = _monthTotal(ym);
    final count = _monthCount(ym);
    final frac = maxTotal == 0 || total == 0 ? 0.0 : total / maxTotal;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: SizedBox(
        width: 44,
        child: Text(
          Dt.months[month - 1],
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: isCurrent ? Ruby.ruby : Ruby.ink,
          ),
        ),
      ),
      title: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 8,
          color: Ruby.fieldBg,
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: frac,
            child: Container(color: Ruby.ruby),
          ),
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('$count bill${count == 1 ? '' : 's'}', style: const TextStyle(fontSize: 11.5, color: Ruby.faint)),
      ),
      trailing: Text(
        Money.fmt(total),
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 13.5,
          color: total == 0 ? Ruby.faint : Ruby.ink,
        ),
      ),
    );
  }

  // ---------------- customers ----------------

  Widget _customersTab() {
    if (_customers.isEmpty) {
      return const EmptyState(
        icon: Icons.people_outline,
        title: 'No sales yet',
        subtitle: 'Customer purchases for the selected year will appear here.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _customers.length,
      itemBuilder: (context, i) {
        final row = _customers[i];
        final yearTotal = ((row['year_total'] ?? 0) as num).toInt();
        final allTotal = ((row['all_total'] ?? 0) as num).toInt();
        final lastBill = (row['last_bill'] as int?) ?? 0;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Ruby.rubyLight,
            child: Text(
              ((row['name'] as String?)?.isNotEmpty == true) ? (row['name'] as String)[0].toUpperCase() : '?',
              style: const TextStyle(color: Ruby.ruby, fontWeight: FontWeight.w800),
            ),
          ),
          title: Text(
            row['name'] as String,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: Ruby.ink),
          ),
          subtitle: Text(
            [
              'This year: ${Money.fmt(yearTotal)}',
              'All time: ${Money.fmt(allTotal)}',
              if (lastBill > 0) 'Last: ${Dt.fmtDate(DateTime.fromMillisecondsSinceEpoch(lastBill))}',
            ].join('\n'),
            style: const TextStyle(fontSize: 12, color: Ruby.muted, height: 1.35),
          ),
          isThreeLine: true,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LedgerScreen(
                  customerId: row['id'] as String,
                  customerName: row['name'] as String,
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------------- top items ----------------

  Widget _productsTab() {
    if (_products.isEmpty) {
      return const EmptyState(
        icon: Icons.stacked_bar_chart,
        title: 'No item sales yet',
        subtitle: 'Best-selling items of the selected year will appear here.',
      );
    }
    final maxAmt = _products.fold<int>(0, (m, e) {
      final v = ((e['amt'] ?? 0) as num).toInt();
      return v > m ? v : m;
    });
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _products.length,
      itemBuilder: (context, i) {
        final row = _products[i];
        final amt = ((row['amt'] ?? 0) as num).toInt();
        final qty = ((row['qty'] ?? 0) as num).toDouble();
        final frac = maxAmt == 0 || amt == 0 ? 0.0 : amt / maxAmt;
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 14,
            backgroundColor: i < 3 ? Ruby.ruby : Ruby.fieldBg,
            child: Text(
              '${i + 1}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: i < 3 ? Colors.white : Ruby.muted,
              ),
            ),
          ),
          title: Text(
            row['name'] as String,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Ruby.ink),
          ),
          subtitle: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              margin: const EdgeInsets.only(top: 6),
              height: 6,
              color: Ruby.fieldBg,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: frac,
                child: Container(color: Ruby.ruby),
              ),
            ),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(Money.fmt(amt), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: Ruby.ink)),
              Text('${_qty(qty)} sold', style: const TextStyle(fontSize: 11.5, color: Ruby.faint)),
            ],
          ),
        );
      },
    );
  }

  String _qty(double q) {
    if (q == q.roundToDouble()) return q.round().toString();
    return q.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
}
