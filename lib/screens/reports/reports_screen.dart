import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repo.dart';
import '../../widgets/widgets.dart';
import '../ledger/ledger_screen.dart';

/// Sales reports with Miracle-style period filters:
///   * Calendar Year (Jan - Dec)
///   * Financial Year (Apr - Mar, the Indian FY)
///   * Single Month (daily drill-down)
/// Every tab (monthly bars, customer-wise, item-wise) follows the
/// selected period.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

enum _Period { year, fy, month }

class _ReportsScreenState extends State<ReportsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  _Period _period = _Period.fy; // Indian shops think in FYs by default
  late int _year = DateTime.now().year;
  int _month = DateTime.now().month;

  List<(String, int, int)> _series = []; // by month (year/fy) or by day (month)
  List<Map<String, Object?>> _customers = [];
  List<Map<String, Object?>> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ---------------- period math ----------------

  String get _startDay {
    switch (_period) {
      case _Period.year:
        return '$_year-01-01';
      case _Period.fy:
        return _fyStartYear < 0 ? '' : '$_fyStartYear-04-01';
      case _Period.month:
        return '$_year-${_month.toString().padLeft(2, '0')}-01';
    }
  }

  String get _endDay {
    switch (_period) {
      case _Period.year:
        return '$_year-12-31';
      case _Period.fy:
        return '$_fyEndYear-03-31';
      case _Period.month:
        final last = DateTime(_year, _month + 1, 1).subtract(const Duration(days: 1));
        return '$_year-${_month.toString().padLeft(2, '0')}-${last.day.toString().padLeft(2, '0')}';
    }
  }

  /// FY that contains today (Apr - Mar). 2026-11 -> FY start 2026.
  int get _currentFyStart {
    final n = DateTime.now();
    return n.month >= 4 ? n.year : n.year - 1;
  }

  int get _fyStartYear => _period == _Period.fy ? _year : -1;
  int get _fyEndYear => _fyStartYear + 1;

  String get _periodLabel {
    switch (_period) {
      case _Period.year:
        return 'Jan - Dec $_year';
      case _Period.fy:
        return 'FY $_fyStartYear-${('${_fyEndYear % 100}').padLeft(2, '0')}';
      case _Period.month:
        return '${Dt.months[_month - 1]} $_year';
    }
  }

  List<int> get _years => [
        DateTime.now().year + 1,
        DateTime.now().year,
        DateTime.now().year - 1,
        DateTime.now().year - 2,
        DateTime.now().year - 3,
      ];

  Future<void> _load() async {
    setState(() => _loading = true);
    final byMonth = await Repo.instance.salesByMonth(_startDay, _endDay);
    final series = _period == _Period.month
        ? await Repo.instance.salesByDay(_startDay, _endDay)
        : byMonth;
    final customers = await Repo.instance.customerSummaries(_startDay, _endDay);
    final products = await Repo.instance.topProducts(_startDay, _endDay);
    if (!mounted) return;
    setState(() {
      _series = series;
      _customers = customers;
      _products = products;
      _loading = false;
    });
  }

  int get _periodTotal => _series.fold<int>(0, (s, e) => s + e.$3);

  // ---------------- build ----------------

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sales Reports'),
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
            _periodSelector(),
            _totalBar(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Ruby.ruby))
                  : TabBarView(
                      controller: _tabs,
                      children: [_seriesTab(), _customersTab(), _productsTab()],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- period selector ----------------

  Widget _periodSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Ruby.fieldBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Ruby.line),
              ),
              child: Row(
                children: [
                  _modeChip('YEAR', _Period.year),
                  _modeChip('FY', _Period.fy),
                  _modeChip('MONTH', _Period.month),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _valueDropdown(),
        ],
      ),
    );
  }

  Widget _modeChip(String label, _Period p) {
    final selected = _period == p;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: () {
          if (_period == p) return;
          setState(() {
            if (p == _Period.fy) _year = _currentFyStart;
            _period = p;
          });
          _load();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? Ruby.ruby : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: selected ? Colors.white : Ruby.muted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _valueDropdown() {
    if (_period == _Period.month) {
      return Row(
        children: [
          _dropdown<int>(
            value: _month,
            items: [
              for (var m = 1; m <= 12; m++)
                DropdownMenuItem(value: m, child: Text(Dt.months[m - 1], style: const TextStyle(fontSize: 13))),
            ],
            onChanged: (m) {
              if (m == null) return;
              setState(() => _month = m);
              _load();
            },
          ),
          const SizedBox(width: 6),
          _dropdown<int>(
            value: _year,
            items: [
              for (final y in _years) DropdownMenuItem(value: y, child: Text('$y', style: const TextStyle(fontSize: 13))),
            ],
            onChanged: (y) {
              if (y == null) return;
              setState(() => _year = y);
              _load();
            },
          ),
        ],
      );
    }
    return _dropdown<int>(
      value: _year,
      items: [
        for (final y in _years)
          DropdownMenuItem(
            value: y,
            child: Text(
              _period == _Period.fy ? 'FY $y-${('${(y + 1) % 100}').padLeft(2, '0')}' : '$y',
              style: const TextStyle(fontSize: 13),
            ),
          ),
      ],
      onChanged: (y) {
        if (y == null) return;
        setState(() => _year = y);
        _load();
      },
    );
  }

  Widget _dropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Ruby.line),
        borderRadius: BorderRadius.circular(10),
        color: Ruby.fieldBg,
      ),
      child: DropdownButton<T>(
        value: value,
        underline: const SizedBox.shrink(),
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  Widget _totalBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          Text(_periodLabel, style: const TextStyle(fontSize: 12.5, color: Ruby.muted)),
          const Spacer(),
          Text(
            'Total ${Money.fmt(_periodTotal)}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Ruby.ink),
          ),
        ],
      ),
    );
  }

  // ---------------- series (monthly bars / daily bars) ----------------

  Widget _seriesTab() {
    if (_series.isEmpty) {
      return EmptyState(
        icon: Icons.stacked_bar_chart,
        title: 'No sales in this period',
        subtitle: 'Change the period above or make some bills first.',
      );
    }
    final maxTotal = _series.fold<int>(0, (m, e) => e.$3 > m ? e.$3 : m);
    final now = DateTime.now();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _series.length,
      itemBuilder: (context, i) {
        final (key, count, total) = _series[i];
        final isCurrent = _period == _Period.month
            ? key == Dt.todayKey()
            : key == '${now.year}-${now.month.toString().padLeft(2, '0')}';
        final label = _period == _Period.month
            ? '${int.parse(key.substring(8, 10))} ${Dt.months[int.parse(key.substring(5, 7)) - 1]}'
            : '${Dt.months[int.parse(key.substring(5, 7)) - 1]} ${key.substring(0, 4)}';
        return _barRow(label, count, total, maxTotal, isCurrent);
      },
    );
  }

  Widget _barRow(String label, int count, int total, int maxTotal, bool isCurrent) {
    final frac = maxTotal == 0 || total == 0 ? 0.0 : total / maxTotal;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: SizedBox(
        width: 64,
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
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
      return EmptyState(
        icon: Icons.people_outline,
        title: 'No sales yet',
        subtitle: 'Customer purchases for ${_periodLabel.toLowerCase()} will appear here.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _customers.length,
      itemBuilder: (context, i) {
        final row = _customers[i];
        final periodTotal = ((row['period_total'] ?? 0) as num).toInt();
        final lastBill = (row['last_bill'] as int?) ?? 0;
        final city = (row['city'] ?? '') as String;
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
              'Bought ${Money.fmt(periodTotal)} in ${_periodLabel.toLowerCase()}',
              if (city.isNotEmpty) city,
              if (lastBill > 0) 'Last bill: ${Dt.fmtDate(DateTime.fromMillisecondsSinceEpoch(lastBill))}',
            ].join('  \u2022  '),
            style: const TextStyle(fontSize: 12, color: Ruby.muted),
          ),
          trailing: const Icon(Icons.chevron_right, color: Ruby.faint),
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
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'No item sales yet',
        subtitle: 'Best-selling items for ${_periodLabel.toLowerCase()} will appear here.',
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
              Text('${Qty.fmt(qty)} sold', style: const TextStyle(fontSize: 11.5, color: Ruby.faint)),
            ],
          ),
        );
      },
    );
  }
}
