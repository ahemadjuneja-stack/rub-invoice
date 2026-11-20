import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repo.dart';
import '../../models/models.dart';
import '../../services/pdf_service.dart';
import '../../services/sync_service.dart';
import '../../widgets/widgets.dart';
import 'purchase_form_screen.dart';
import 'suppliers_screen.dart';

/// Purchase invoices (maal kharida): every supplier bill - what came,
/// from which party, at which rates, how much GST per product, parcel
/// charges - with the photo of the paper bill and the AI-scan shortcut.
/// Full bills are printable (A4 purchase memo) and party-wise hisab
/// lives in the Purchase Parties screen.
class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen({super.key});

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  List<Purchase> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await Repo.instance.purchases();
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  Future<void> _openForm() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PurchaseFormScreen()),
    );
    _reload();
  }

  Future<void> _editPurchase(Purchase p) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PurchaseFormScreen(editPurchase: p)),
    );
    _reload();
  }

  Future<void> _deletePurchase(Purchase p) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete purchase #${p.purchaseNo}?',
      message:
          '"${p.supplierName}" - ${Money.fmt(p.amountPaise)} '
          '(${Dt.fmtDate(Dt.dayStartOf(p.purchaseDate))}) will be removed '
          'from purchase records and the party account.',
      ok: 'Delete',
      dangerous: true,
    );
    if (!ok) return;
    await Repo.instance.deletePurchase(p.id);
    SyncService.instance.syncSoon();
    _reload();
    if (mounted) showSnack(context, 'Purchase deleted');
  }

  Future<void> _sharePdf(Purchase p) async {
    final (purchase, items) = await Repo.instance.purchaseWithItems(p.id);
    await PdfService.instance.sharePurchase(
      purchase: purchase,
      items: items,
    );
  }

  Future<void> _openDetails(Purchase p) async {
    final (purchase, items) = await Repo.instance.purchaseWithItems(p.id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          builder: (_, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.all(18),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          purchase.supplierName,
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Ruby.ink),
                        ),
                        Text(
                          'Purchase #${purchase.purchaseNo}'
                          '${purchase.partyBillNo.isNotEmpty ? '  |  Party bill ${purchase.partyBillNo}' : ''}'
                          '  |  ${Dt.fmtDate(Dt.dayStartOf(purchase.purchaseDate))}',
                          style: const TextStyle(
                              fontSize: 12, color: Ruby.muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _editPurchase(purchase);
                    },
                    icon: const Icon(Icons.edit_outlined, color: Ruby.ruby),
                    tooltip: 'Edit',
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _deletePurchase(purchase);
                    },
                    icon: const Icon(Icons.delete_outline,
                        color: Ruby.ruby),
                    tooltip: 'Delete',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Ruby.rubyLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('GRAND TOTAL',
                              style: TextStyle(
                                  fontSize: 9.5,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w800,
                                  color: Ruby.ruby)),
                          Text(
                            Money.fmt(purchase.amountPaise),
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Ruby.ink),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Ruby.ruby,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => _sharePdf(purchase),
                      icon: const Icon(Icons.share_outlined, size: 17),
                      label: const Text('PDF',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // item table with GST
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Ruby.line),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: Table(
                  border:
                      const TableBorder(horizontalInside: BorderSide(color: Ruby.line)),
                  columnWidths: const {
                    0: FlexColumnWidth(4),
                    1: FlexColumnWidth(1.3),
                    2: FlexColumnWidth(1.7),
                    3: FlexColumnWidth(1),
                    4: FlexColumnWidth(1.9),
                  },
                  children: [
                    const TableRow(
                      decoration: BoxDecoration(color: Ruby.fieldBg),
                      children: [
                        _Th('Product'),
                        _Th('Qty'),
                        _Th('Rate'),
                        _Th('GST%'),
                        _Th('Amount'),
                      ],
                    ),
                    for (final it in items)
                      TableRow(children: [
                        _Td(it.productName, bold: true),
                        _Td(Qty.fmt(it.qty)),
                        _Td(Money.fmt(it.ratePaise, withSymbol: false)),
                        _Td(it.gstPercent == 0
                            ? '-'
                            : it.gstPercent.toStringAsFixed(0)),
                        _Td(Money.fmt(it.amountPaise, withSymbol: false)),
                      ]),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _sumRow('Subtotal (maal)', purchase.subtotalPaise),
              _sumRow('GST total', purchase.gstTotalPaise),
              _sumRow('Parcel / transport', purchase.parcelPaise),
              _sumRow('GRAND TOTAL', purchase.amountPaise, bold: true),
              if (purchase.note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Note: ${purchase.note}',
                      style:
                          const TextStyle(fontSize: 12.5, color: Ruby.muted)),
                ),
              if (purchase.photoPath.isNotEmpty &&
                  File(purchase.photoPath).existsSync()) ...[
                const SizedBox(height: 14),
                const Text('Paper bill photo',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: Ruby.ink)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(File(purchase.photoPath), height: 220,
                      fit: BoxFit.cover),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sumRow(String label, int paise, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: bold ? 14 : 12.5,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
                color: bold ? Ruby.ruby : Ruby.muted,
              ),
            ),
          ),
          Text(
            Money.fmt(paise),
            style: TextStyle(
              fontSize: bold ? 16 : 13.5,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
              color: Ruby.ink,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: RubyAppBar(
        title: 'Purchase Invoices',
        subtitle: 'Maal kharida - party wise hisab',
        actions: [
          IconButton(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SuppliersScreen()),
              );
              _reload();
            },
            icon: const Icon(Icons.local_shipping_outlined),
            tooltip: 'Purchase parties & hisab',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Ruby.ruby,
        foregroundColor: Colors.white,
        onPressed: _openForm,
        icon: const Icon(Icons.add),
        label: const Text('NEW PURCHASE',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Ruby.ruby))
          : _items.isEmpty
              ? const EmptyState(
                  icon: Icons.local_shipping_outlined,
                  title: 'Koi purchase nahi hui',
                  subtitle:
                      'Surat / Mumbai / local agent se maal aaya? NEW PURCHASE '
                      'dabao - items, rate, GST aur parcel ke saath poora bill '
                      'banega. Party ka bill photo se AI-scan bhi ho sakta hai.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final p = _items[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _openDetails(p),
                      child: Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Ruby.line),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: Ruby.rubyLight,
                              child: Text(
                                p.supplierName.isEmpty
                                    ? '?'
                                    : p.supplierName
                                        .substring(0, 1)
                                        .toUpperCase(),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Ruby.ruby),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.supplierName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14.5,
                                        color: Ruby.ink),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    [
                                      '#${p.purchaseNo}',
                                      if (p.partyBillNo.isNotEmpty)
                                        'Bill ${p.partyBillNo}',
                                      Dt.fmtDate(
                                          Dt.dayStartOf(p.purchaseDate)),
                                      if (p.gstTotalPaise > 0)
                                        'GST ${Money.fmt(p.gstTotalPaise, withSymbol: false)}',
                                      if (p.parcelPaise > 0)
                                        'Parcel ${Money.fmt(p.parcelPaise, withSymbol: false)}',
                                    ].join('  |  '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 11.5, color: Ruby.muted),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              Money.fmt(p.amountPaise),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: Ruby.ink),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _Th extends StatelessWidget {
  final String text;
  const _Th(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Text(text,
          style: const TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w800, color: Ruby.muted)),
    );
  }
}

class _Td extends StatelessWidget {
  final String text;
  final bool bold;
  const _Td(this.text, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          color: Ruby.ink,
        ),
      ),
    );
  }
}
