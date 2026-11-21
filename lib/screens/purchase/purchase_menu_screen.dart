import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repo.dart';
import '../../models/models.dart';
import '../../services/sync_service.dart';
import '../../widgets/widgets.dart';
import 'purchase_form_screen.dart';
import 'purchase_return_form.dart';
import 'suppliers_screen.dart';
import 'supplier_picker_sheet.dart';

/// PURCHASE MENU - one place for everything about goods coming in:
///   * NEW PURCHASE and NEW PURCHASE RETURN buttons (supplier picker
///     first, then the billing-style form)
///   * the summary: how much goods arrived, how much went back, GST
///     paid and parcel charges - all time
///   * PURCHASE PARTIES: every supplier with phone, address and account
///     balance (tap a party for its full ledger)
///   * recent purchase returns with full detail
///
/// Opened from the menu icon on the Purchase Invoices screen.
class PurchaseMenuScreen extends StatefulWidget {
  const PurchaseMenuScreen({super.key});

  @override
  State<PurchaseMenuScreen> createState() => _PurchaseMenuScreenState();
}

class _PurchaseMenuScreenState extends State<PurchaseMenuScreen> {
  ({int purchased, int returned, int gst, int parcel})? _summary;
  List<PurchaseReturn> _returns = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final summary = await Repo.instance.purchaseSummary();
    final returns = await Repo.instance.purchaseReturns();
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _returns = returns;
      _loading = false;
    });
  }

  Future<void> _newPurchase() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PurchaseFormScreen()),
    );
    _reload();
  }

  Future<void> _newPurchaseReturn() async {
    final Supplier? sup = await showModalBottomSheet<Supplier>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const SupplierPickerSheet(title: 'Select supplier for the return'),
    );
    if (sup == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PurchaseReturnForm(supplier: sup)),
    );
    SyncService.instance.syncSoon();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    return Scaffold(
      appBar: const RubyAppBar(
        title: 'Purchase Menu',
        subtitle: 'Goods in - purchases, returns, parties',
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Ruby.ruby))
          : RefreshIndicator(
              color: Ruby.ruby,
              onRefresh: _reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  // ---------- action buttons ----------
                  Row(
                    children: [
                      Expanded(
                        child: _bigButton(
                          icon: Icons.local_shipping_outlined,
                          label: 'NEW PURCHASE',
                          onTap: _newPurchase,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _bigButton(
                          icon: Icons.keyboard_return,
                          label: 'PURCHASE RETURN',
                          onTap: _newPurchaseReturn,
                          outlined: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // ---------- summary ----------
                  SectionHeader('Goods summary - all time'),
                  const SizedBox(height: 6),
                  if (s != null) _summaryCard(s),
                  const SizedBox(height: 16),
                  // ---------- parties ----------
                  SectionHeader('Purchase parties (contacts)'),
                  const SizedBox(height: 6),
                  _linkCard(
                    icon: Icons.contact_phone_outlined,
                    title: 'Parties, phone & address',
                    subtitle:
                        'Every supplier with contact details and account balance - '
                        'tap a party to open its full ledger (bills, payments, returns).',
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SuppliersScreen()),
                      );
                      _reload();
                    },
                  ),
                  const SizedBox(height: 16),
                  // ---------- recent returns ----------
                  SectionHeader('Purchase returns (${_returns.length})'),
                  const SizedBox(height: 6),
                  if (_returns.isEmpty)
                    const _PlainNote(
                      text:
                          'No purchase return yet. When goods go back to a party, '
                          'tap PURCHASE RETURN - the amount is credited in that '
                          'party\'s account automatically.',
                    )
                  else
                    for (final r in _returns.take(15))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _returnRow(r),
                      ),
                ],
              ),
            ),
    );
  }

  Widget _summaryCard(
      ({int purchased, int returned, int gst, int parcel}) s) {
    final net = s.purchased - s.returned;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Ruby.line),
      ),
      child: Column(
        children: [
          _sumRow('Goods received (purchases)', s.purchased),
          _sumRow('Goods returned (credit)', -s.returned, green: true),
          const Divider(height: 16),
          _sumRow('NET goods kept', net, bold: true),
          const Divider(height: 16),
          _sumRow('GST paid on purchases', s.gst),
          _sumRow('Parcel / transport charges', s.parcel),
        ],
      ),
    );
  }

  Widget _sumRow(String label, int paise, {bool bold = false, bool green = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: bold ? 13.5 : 12.5,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
                color: bold ? Ruby.ruby : Ruby.muted,
              ),
            ),
          ),
          Text(
            Money.fmt(paise),
            style: TextStyle(
              fontSize: bold ? 15.5 : 13.5,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
              color: green ? Ruby.green : Ruby.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _returnRow(PurchaseReturn r) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openReturnDetails(r),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Ruby.line),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Ruby.greenLight,
              child: const Icon(Icons.keyboard_return, size: 16, color: Ruby.green),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.supplierName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 13.5, color: Ruby.ink)),
                  Text(
                    'Return #${r.returnNo}  |  ${Dt.fmtDate(Dt.dayStartOf(r.returnDate))}'
                    '${r.gstTotalPaise > 0 ? '  |  GST ${Money.fmt(r.gstTotalPaise, withSymbol: false)}' : ''}',
                    style: const TextStyle(fontSize: 11, color: Ruby.muted),
                  ),
                ],
              ),
            ),
            Text(
              '- ${Money.fmt(r.amountPaise)}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: Ruby.green),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openReturnDetails(PurchaseReturn r) async {
    final items = await Repo.instance.purchaseReturnItems(r.id);
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(18),
          children: [
            Text(r.supplierName,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800, color: Ruby.ink)),
            Text(
              'Return #${r.returnNo}  |  ${Dt.fmtDate(Dt.dayStartOf(r.returnDate))}',
              style: const TextStyle(fontSize: 12, color: Ruby.muted),
            ),
            const SizedBox(height: 12),
            for (final it in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Ruby.line, width: 0.9),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(it.productName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: Ruby.ink)),
                      ),
                      Text(
                        '${Qty.fmt(it.qty)} x ${Money.fmt(it.ratePaise, withSymbol: false)}'
                        '${it.gstPercent > 0 ? ' +${it.gstPercent.toStringAsFixed(0)}%' : ''}',
                        style: const TextStyle(fontSize: 11.5, color: Ruby.muted),
                      ),
                      const SizedBox(width: 8),
                      Text(Money.fmt(it.amountPaise),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: Ruby.ink)),
                    ],
                  ),
                ),
              ),
            const Divider(height: 20),
            Row(
              children: [
                const Text('TOTAL CREDIT',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800, color: Ruby.ruby)),
                const Spacer(),
                Text(Money.fmt(r.amountPaise + r.gstTotalPaise),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800, color: Ruby.ink)),
              ],
            ),
            if (r.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Note: ${r.note}',
                    style: const TextStyle(fontSize: 12.5, color: Ruby.muted)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bigButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool outlined = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          color: outlined ? Colors.white : Ruby.ruby,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: outlined ? Ruby.ruby.withValues(alpha: 0.5) : Ruby.ruby),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: outlined ? Ruby.ruby : Colors.white),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: outlined ? Ruby.ruby : Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _linkCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Ruby.line),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: Ruby.rubyLight,
              child: Icon(icon, size: 20, color: Ruby.ruby),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          color: Ruby.ink)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(fontSize: 11, color: Ruby.faint)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: Ruby.faint),
          ],
        ),
      ),
    );
  }
}

class _PlainNote extends StatelessWidget {
  final String text;
  const _PlainNote({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Ruby.fieldBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(text,
          style: const TextStyle(fontSize: 12, height: 1.5, color: Ruby.muted)),
    );
  }
}
