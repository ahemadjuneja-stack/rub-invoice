import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../services/pdf_service.dart';
import '../../services/sync_service.dart';
import '../common/widgets.dart';

/// Bill detail: items, totals, share PDF, delete.
class BillViewScreen extends StatefulWidget {
  final String billId;
  const BillViewScreen({super.key, required this.billId});

  @override
  State<BillViewScreen> createState() => _BillViewScreenState();
}

class _BillViewScreenState extends State<BillViewScreen> {
  Bill? _bill;
  List<BillItem> _items = [];
  Map<String, String> _shop = {};
  String _city = '';
  String _phone = '';
  int _balanceAfter = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = Repo.instance;
    final (bill, items) = await repo.billWithItems(widget.billId);
    final shop = await repo.shopProfile();
    final cust = await repo.getCustomer(bill.customerId);
    final (_, entries) = await repo.ledger(bill.customerId);
    if (!mounted) return;
    setState(() {
      _bill = bill;
      _items = items;
      _shop = shop;
      _city = cust?.city ?? '';
      _phone = cust?.phone ?? '';
      _balanceAfter = entries.isEmpty ? 0 : entries.last.runningBalancePaise;
      _loading = false;
    });
  }

  Future<void> _share() async {
    if (_bill == null) return;
    await PdfService.instance.shareBill(
      bill: _bill!,
      items: _items,
      shop: _shop,
      customerCity: _city,
      customerPhone: _phone,
      balanceAfterPaise: _balanceAfter,
    );
  }

  Future<void> _delete() async {
    if (_bill == null) return;
    final ok = await confirmDialog(
      context,
      title: 'Delete bill #${_bill!.billNo}?',
      message:
          'This removes the bill and the payment recorded with it from the customer ledger, '
          'and restores tracked stock. The change will sync to your other device.',
      ok: 'Delete',
      dangerous: true,
    );
    if (!ok) return;
    await Repo.instance.deleteBill(_bill!.id);
    SyncService.instance.syncSoon();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bill = _bill;
    return Scaffold(
      appBar: AppBar(
        title: Text(bill == null ? 'Bill' : 'Bill #${bill.billNo}'),
        actions: [
          IconButton(onPressed: bill == null ? null : _share, icon: const Icon(Icons.share)),
          IconButton(onPressed: bill == null ? null : _delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Ruby.ruby))
          : ListView(
              children: [
                Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Ruby.rubyLight,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              bill?.customerName ?? '',
                              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Ruby.ink),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              [
                                if (_city.isNotEmpty) _city,
                                if (_phone.isNotEmpty) _phone,
                              ].join('  •  '),
                              style: const TextStyle(fontSize: 12.5, color: Ruby.muted),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            bill == null ? '' : Dt.fmtDayKey(bill.billDay),
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Ruby.ruby),
                          ),
                          Text(
                            bill == null ? '' : Dt.fmtTime(DateTime.fromMillisecondsSinceEpoch(bill.billDate)),
                            style: const TextStyle(fontSize: 12, color: Ruby.muted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(indent: 16, endIndent: 16),
                for (final it in _items)
                  ListTile(
                    dense: true,
                    title: Text(it.productName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    subtitle: Text(
                      '${_qty(it.qty)} × ${Money.fmt(it.ratePaise)}',
                      style: const TextStyle(fontSize: 12.5, color: Ruby.muted),
                    ),
                    trailing: Text(
                      Money.fmt(it.amountPaise),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Ruby.ink),
                    ),
                  ),
                const Divider(indent: 16, endIndent: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('TOTAL', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 1)),
                      Text(
                        Money.fmt(bill?.totalPaise ?? 0),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Ruby.ruby),
                      ),
                    ],
                  ),
                ),
                if ((bill?.note ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text('Note: ${bill!.note}', style: const TextStyle(fontSize: 12.5, color: Ruby.muted)),
                  ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _balanceAfter > 0
                        ? 'Customer balance after this bill: ${Money.fmt(_balanceAfter)} due'
                        : _balanceAfter < 0
                            ? 'Customer balance after this bill: ${Money.fmt(-_balanceAfter)} advance'
                            : 'Customer balance after this bill: settled',
                    style: const TextStyle(fontSize: 12.5, color: Ruby.muted),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: ElevatedButton.icon(
            icon: const Icon(Icons.share, size: 20),
            label: const Text('SHARE PDF BILL'),
            onPressed: _share,
          ),
        ),
      ),
    );
  }

  String _qty(double qty) {
    if (qty == qty.roundToDouble()) return qty.round().toString();
    return qty.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
}
