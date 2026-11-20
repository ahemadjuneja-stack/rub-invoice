import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../data/repo.dart';
import '../../services/pdf_service.dart';
import '../../services/sync_service.dart';
import '../../widgets/widgets.dart';
import '../billing/billing_screen.dart';
import 'dispatch_sheet.dart';

/// Bill detail: items, totals, share PDF, edit (pen), delete.
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
  Customer? _cust;
  String _city = '';
  String _phone = '';
  int _balanceAfter = 0;
  BillDispatch? _dispatch;
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
    final d = await repo.dispatchFor(widget.billId);
    if (!mounted) return;
    setState(() {
      _bill = bill;
      _items = items;
      _shop = shop;
      _cust = cust;
      _city = cust?.city ?? '';
      _phone = cust?.phone ?? '';
      _balanceAfter = entries.isEmpty ? 0 : entries.last.runningBalancePaise;
      _dispatch = d;
      _loading = false;
    });
  }

  /// Opens the bill in the billing screen with every line editable -
  /// same invoice number is kept, ledger and stock recomputed on save.
  Future<void> _edit() async {
    final bill = _bill;
    final cust = _cust;
    if (bill == null || cust == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BillingScreen(customer: cust, editBill: bill),
      ),
    );
    if (mounted) _load(); // refresh items, total and balance after the edit
  }

  Future<void> _share() async {
    if (_bill == null) return;
    // DEBIT MEMO vs CASH MEMO: a bill whose amount was fully received
    // (cash/jama) prints as CASH MEMO, anything with balance left prints
    // as DEBIT MEMO - exactly like the paper memos.
    int paidOnBill = 0;
    try {
      paidOnBill = await Repo.instance.paidWithBill(_bill!.id);
    } catch (_) {}
    await PdfService.instance.shareBill(
      bill: _bill!,
      items: _items,
      shop: _shop,
      customerCity: _city,
      customerPhone: _phone,
      balanceAfterPaise: _balanceAfter,
      isCashMemo: paidOnBill >= _bill!.totalPaise,
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

  /// Miracle-style identity: "City - Name" (e.g. "Rajkot - Riya") on
  /// one line, exactly like the billing screen header.
  String get _customerTitle {
    final city = _city.trim();
    final shop = (_cust?.shopName ?? '').trim();
    final label = shop.isNotEmpty ? shop : (_bill?.customerName ?? '');
    if (city.isNotEmpty && label.isNotEmpty) return '$city - $label';
    return label;
  }

  @override
  Widget build(BuildContext context) {
    final bill = _bill;
    return Scaffold(
      appBar: RubyAppBar(
        title: bill == null ? 'Bill' : 'Bill #${bill.billNo}',
        actions: [
          IconButton(
            onPressed: bill == null ? null : _edit,
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit bill',
          ),
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
                              _customerTitle,
                              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Ruby.ink),
                            ),
                            const SizedBox(height: 3),
                            if (_phone.isNotEmpty)
                              Text(
                                _phone,
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
                _dispatchCard(),
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

  /// Delivery (transport) details saved at bill time: the mode, the
  /// transport note and the billty photo (45-day retention). Tap ADD /
  /// the pen to open the delivery sheet; share button sends everything
  /// (photo included) to WhatsApp.
  Widget _dispatchCard() {
    final bill = _bill;
    if (bill == null) return const SizedBox.shrink();
    final d = _dispatch;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Ruby.line),
      ),
      child: d == null
          ? InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _openDispatch,
              child: Row(
                children: [
                  const Icon(Icons.local_shipping_outlined, size: 20, color: Ruby.faint),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Delivery details not added yet',
                      style: TextStyle(fontSize: 13, color: Ruby.muted),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Ruby.ruby,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'ADD',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_modeIcon(d.mode), size: 18, color: Ruby.ruby),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Delivery: ${d.modeLabel}',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Ruby.ink),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Edit delivery details',
                      onPressed: _openDispatch,
                      icon: const Icon(Icons.edit_outlined, size: 18, color: Ruby.muted),
                    ),
                  ],
                ),
                if (d.note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      d.note,
                      style: const TextStyle(fontSize: 12.5, color: Ruby.muted, height: 1.4),
                    ),
                  ),
                if (d.billtyPath.isNotEmpty && File(d.billtyPath).existsSync()) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () => showPhotoFullscreen(context, d.billtyPath),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(d.billtyPath),
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 72,
                              height: 72,
                              color: Ruby.fieldBg,
                              child: const Icon(Icons.broken_image_outlined, size: 20, color: Ruby.faint),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'BILLTY PHOTO',
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: Ruby.muted),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Tap to view - ${billtyDaysLeft(d)}',
                              style: const TextStyle(fontSize: 11.5, color: Ruby.faint),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.chat_outlined, size: 18),
                  label: const Text(
                    'SHARE ON WHATSAPP',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                  onPressed: () => shareDispatchDetails(bill, d, title: _customerTitle),
                ),
              ],
            ),
    );
  }

  /// Opens the delivery sheet (same display as right after Done); the
  /// card reloads when it closes so saved details appear instantly.
  Future<void> _openDispatch() async {
    final bill = _bill;
    if (bill == null) return;
    await showDispatchSheet(context, bill: bill);
    if (mounted) _load();
  }

  IconData _modeIcon(String mode) {
    if (mode == 'transport') return Icons.local_shipping_outlined;
    if (mode == 'inhand') return Icons.directions_walk_outlined;
    if (mode == 'courier') return Icons.markunread_mailbox_outlined;
    if (mode == 'pending') return Icons.schedule_outlined;
    return Icons.help_outline;
  }

  String _qty(double qty) {
    if (qty == qty.roundToDouble()) return qty.round().toString();
    return qty.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
}
