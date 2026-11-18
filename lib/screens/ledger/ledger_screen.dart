import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../models/settlement.dart';
import '../../data/repo.dart';
import '../../services/sync_service.dart';
import '../billing/billing_screen.dart';
import '../../widgets/widgets.dart';
import '../customer/customer_form_screen.dart';

/// Full customer account: opening balance + every bill (+) and every
/// payment (-), oldest to newest with a running balance.
/// Positive running balance = udhar (customer owes you).
/// Negative = advance (you owe the customer).
class LedgerScreen extends StatefulWidget {
  final String customerId;
  final String customerName;
  const LedgerScreen({super.key, required this.customerId, required this.customerName});

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  Customer? _customer;
  int _balance = 0;
  List<LedgerEntry> _entries = [];
  Settlement? _settlement; // FIFO view: which bills are settled/partial
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cust = await Repo.instance.getCustomer(widget.customerId);
    final (balance, entries) = await Repo.instance.ledger(widget.customerId);
    final st = await Repo.instance.settlement(widget.customerId);
    if (!mounted) return;
    setState(() {
      _customer = cust;
      _balance = balance;
      _entries = entries;
      _settlement = st;
      _loading = false;
    });
    SyncService.instance.syncSoon();
  }

  Future<void> _newBill() async {
    final cust = _customer;
    if (cust == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BillingScreen(customer: cust)),
    );
    _load();
  }

  Future<void> _editCustomer() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerFormScreen(customerId: widget.customerId),
      ),
    );
    _load();
  }

  Future<void> _addPayment() async {
    final ok = await _paymentDialog();
    if (ok == true) {
      _load();
    }
  }

  Future<bool?> _paymentDialog() async {
    final amountC = TextEditingController(
      text: _balance > 0 ? Money.fmtRupeesInput(_balance) : '',
    );
    String mode = 'cash';
    DateTime date = DateTime.now();
    final noteC = TextEditingController();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            20, 20, 20,
            20 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Receive Payment (Jama)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Ruby.ink),
              ),
              if (_balance > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Balance due: ${Money.fmt(_balance)}',
                    style: const TextStyle(fontSize: 12.5, color: Ruby.muted),
                  ),
                ),
              const SizedBox(height: 14),
              TextField(
                controller: amountC,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                decoration: const InputDecoration(hintText: 'Amount', isDense: false, prefixText: '\u{20B9}  '),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final m in const ['cash', 'upi', 'bank', 'other'])
                    ChoiceChip(
                      label: Text(m.toUpperCase()),
                      selected: mode == m,
                      selectedColor: Ruby.ruby,
                      labelStyle: TextStyle(
                        color: mode == m ? Colors.white : Ruby.muted,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                      onSelected: (_) => setSheet(() => mode = m),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.calendar_month_outlined, size: 18, color: Ruby.muted),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                      );
                      if (d != null) setSheet(() => date = d);
                    },
                    child: Text(Dt.fmtDate(date), style: const TextStyle(fontSize: 13.5)),
                  ),
                  const Spacer(),
                  Expanded(
                    child: TextField(
                      controller: noteC,
                      decoration: const InputDecoration(hintText: 'Note (optional)', isDense: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  final amount = Money.parsePaise(amountC.text);
                  if (amount <= 0) {
                    showSnack(ctx, 'Enter an amount', error: true);
                    return;
                  }
                  await Repo.instance.addPayment(
                    customerId: widget.customerId,
                    amountPaise: amount,
                    mode: mode,
                    date: date,
                    note: noteC.text.trim(),
                  );
                  SyncService.instance.syncSoon();
                  if (ctx.mounted) Navigator.pop(ctx, true);
                },
                child: const Text('SAVE PAYMENT'),
              ),
            ],
          ),
        ),
      ),
    );
    amountC.dispose();
    noteC.dispose();
    return saved;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.customerName, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(onPressed: _editCustomer, icon: const Icon(Icons.edit_outlined)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Ruby.ruby))
          : Column(
              children: [
                _header(),
                if (_settlement != null &&
                    (_settlement!.unpaidCount + _settlement!.partialCount) > 0)
                  _settlementStrip(),
                const Divider(),
                Expanded(
                  child: _entries.isEmpty
                      ? const EmptyState(
                          icon: Icons.book_outlined,
                          title: 'No transactions yet',
                          subtitle: 'Bills and payments will appear here with a running balance.',
                        )
                      : ListView.builder(
                          // Newest at the top is handier day-to-day; the header
                          // always shows the final balance anyway.
                          itemCount: _entries.length,
                          itemBuilder: (context, i) => _tile(_entries[_entries.length - 1 - i]),
                        ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.receipt_long, size: 20),
                  label: const Text('NEW BILL'),
                  onPressed: _newBill,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.currency_rupee, size: 20),
                  label: const Text('RECEIVED'),
                  onPressed: _addPayment,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Bill status chips row: how many bills are still open / partial.
  Widget _settlementStrip() {
    final st = _settlement!;
    final open = st.unpaidCount;
    final partial = st.partialCount;
    final parts = <String>[
      if (open > 0) '$open unpaid bill${open == 1 ? '' : 's'}',
      if (partial > 0) '$partial partial',
    ];
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF4F5),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(
        children: [
          const Icon(Icons.flag_outlined, size: 15, color: Ruby.ruby),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'Oldest bills settle first (FIFO): ${parts.join(" \u2022 ")} '
              '- tap a bill row to see paid/due.',
              style: const TextStyle(fontSize: 11.5, color: Ruby.ruby),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final String label;
    final Color color;
    if (_balance > 0) {
      label = 'Balance Due (Udhar)';
      color = Ruby.ruby;
    } else if (_balance < 0) {
      label = 'Advance (Jama extra)';
      color = Ruby.green;
    } else {
      label = 'Settled';
      color = Ruby.green;
    }
    final city = _customer?.city ?? '';
    final phone = _customer?.phone ?? '';
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(),
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: color)),
                const SizedBox(height: 4),
                Text(
                  Money.fmt(_balance.abs()),
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color),
                ),
                if (city.isNotEmpty || phone.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      [city, phone].where((e) => e.isNotEmpty).join('  •  '),
                      style: const TextStyle(fontSize: 12.5, color: Ruby.muted),
                    ),
                  ),
              ],
            ),
          ),
          if (_customer?.openingBalancePaise != null && _customer!.openingBalancePaise != 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Ruby.fieldBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Old bal: ${Money.fmt(_customer!.openingBalancePaise)}',
                style: const TextStyle(fontSize: 11.5, color: Ruby.muted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tile(LedgerEntry e) {
    final isBill = e.kind == 'bill';
    final isOpening = e.kind == 'opening';
    final debit = e.debitPaise > 0;
    final amountColor = isOpening ? Ruby.muted : (debit ? Ruby.ink : Ruby.green);
    final row = isBill && _settlement != null
        ? _settlement!.rows.where((r) => r.refId == e.refId).firstOrNull
        : null;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isBill
            ? Ruby.rubyLight
            : isOpening
                ? Ruby.fieldBg
                : Ruby.greenLight,
        child: Icon(
          isBill
              ? Icons.receipt_long
              : isOpening
                  ? Icons.info_outline
                  : Icons.currency_rupee,
          size: 18,
          color: isBill ? Ruby.ruby : (isOpening ? Ruby.muted : Ruby.green),
        ),
      ),
      title: Text(
        e.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Ruby.ink),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(Dt.fmtDateTime(e.date), style: const TextStyle(fontSize: 12, color: Ruby.muted)),
          if (row != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: _statusChip(row),
            ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            isOpening
                ? Money.fmt(e.debitPaise > 0 ? e.debitPaise : -e.creditPaise)
                : debit
                    ? '+ ${Money.fmt(e.debitPaise)}'
                    : '- ${Money.fmt(e.creditPaise)}',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: amountColor),
          ),
          Text(
            'bal ${Money.fmt(e.runningBalancePaise)}',
            style: TextStyle(
              fontSize: 11,
              color: e.runningBalancePaise > 0 ? Ruby.ruby : Ruby.green,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// SETTLED (green) / PARTIAL with pending amount / UNPAID (red).
  Widget _statusChip(SettlementRow row) {
    final String label;
    final Color fg;
    final Color bg;
    switch (row.status) {
      case SettlementStatus.settled:
        label = 'SETTLED';
        fg = Ruby.green;
        bg = Ruby.greenLight;
        break;
      case SettlementStatus.partial:
        label = 'PARTIAL - DUE ${Money.fmt(row.duePaise)}';
        fg = const Color(0xFFB8860B);
        bg = const Color(0xFFFFF7E0);
        break;
      case SettlementStatus.unpaid:
        label = 'UNPAID - ${Money.fmt(row.duePaise)}';
        fg = Ruby.ruby;
        bg = Ruby.rubyLight;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: fg,
        ),
      ),
    );
  }
}
