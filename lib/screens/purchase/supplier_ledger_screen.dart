import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repo.dart';
import '../../models/models.dart';
import '../../services/sync_service.dart';
import '../../widgets/widgets.dart';
import 'purchase_form_screen.dart';
import 'purchase_return_form.dart';

/// Supplier account (hisab): every purchase (+), every return / payment
/// (-), with a running balance. Positive = we still owe the supplier.
/// Actions: new purchase bill, purchase return, pay supplier.
class SupplierLedgerScreen extends StatefulWidget {
  final Supplier supplier;
  const SupplierLedgerScreen({super.key, required this.supplier});

  @override
  State<SupplierLedgerScreen> createState() => _SupplierLedgerScreenState();
}

class _SupplierLedgerScreenState extends State<SupplierLedgerScreen> {
  int _balance = 0;
  List<LedgerEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final (balance, entries) =
        await Repo.instance.supplierLedger(widget.supplier.id);
    if (!mounted) return;
    setState(() {
      _balance = balance;
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _newPurchaseBill() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseFormScreen(supplier: widget.supplier),
      ),
    );
    _reload();
  }

  Future<void> _purchaseReturn() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseReturnForm(supplier: widget.supplier),
      ),
    );
    if (saved == true) {
      SyncService.instance.syncSoon();
    }
    _reload();
  }

  Future<void> _pay() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PaySupplierSheet(supplier: widget.supplier),
    );
    if (ok == true) {
      SyncService.instance.syncSoon();
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: RubyAppBar(
        title: widget.supplier.name,
        subtitle: [
          if (widget.supplier.city.isNotEmpty) widget.supplier.city,
          if (widget.supplier.phone.isNotEmpty) widget.supplier.phone,
        ].join('  |  '),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Ruby.ruby))
          : Column(
              children: [
                _balanceBar(),
                _actionRow(),
                Expanded(
                  child: _entries.isEmpty
                      ? const EmptyState(
                          icon: Icons.book_outlined,
                          title: 'Account is empty',
                          subtitle:
                              'Make the first purchase bill for this party. Every '
                              'goods delivery, '
                              'return and payment shows in this one account.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                          itemCount: _entries.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (_, i) => _tile(_entries[i]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _balanceBar() {
    return Container(
      color: Ruby.ruby,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _balance > 0
                      ? 'BANKA / DENA HAI'
                      : _balance < 0
                          ? 'ADVANCE'
                          : 'SETTLED',
                  style: const TextStyle(
                      fontSize: 9.5,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFF3B7BC)),
                ),
                Text(
                  _balance == 0
                      ? Money.fmt(0)
                      : Money.fmt(_balance.abs()),
                  style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionRow() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: _actionChip(
              Icons.add_shopping_cart,
              'PURCHASE',
              _newPurchaseBill,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _actionChip(
              Icons.keyboard_return,
              'RETURN',
              _purchaseReturn,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _actionChip(
              Icons.payments_outlined,
              'PAY',
              _pay,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionChip(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: Ruby.rubyLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Ruby.ruby.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: Ruby.ruby),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Ruby.ruby,
                    letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }

  Widget _tile(LedgerEntry e) {
    final isPurchase = e.kind == 'purchase';
    final isOpening = e.kind == 'opening';
    final debit = e.debitPaise > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Ruby.line),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: isPurchase
                ? Ruby.rubyLight
                : isOpening
                    ? Ruby.fieldBg
                    : Ruby.greenLight,
            child: Icon(
              isPurchase
                  ? Icons.local_shipping_outlined
                  : isOpening
                      ? Icons.info_outline
                      : Icons.currency_rupee,
              size: 15,
              color: isPurchase
                  ? Ruby.ruby
                  : isOpening
                      ? Ruby.muted
                      : Ruby.green,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: Ruby.ink),
                ),
                Text(
                  Dt.fmtDateTime(e.date),
                  style: const TextStyle(fontSize: 11.5, color: Ruby.muted),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                debit ? '+${Money.fmt(e.debitPaise)}' : '-${Money.fmt(e.creditPaise)}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  color: debit ? Ruby.ink : Ruby.green,
                ),
              ),
              Text(
                'bal ${Money.fmt(e.runningBalancePaise, withSymbol: false)}',
                style: const TextStyle(fontSize: 10.5, color: Ruby.faint),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Pay-supplier sheet: amount, mode, note. Reduces the bakaya.
class _PaySupplierSheet extends StatefulWidget {
  final Supplier supplier;
  const _PaySupplierSheet({required this.supplier});

  @override
  State<_PaySupplierSheet> createState() => _PaySupplierSheetState();
}

class _PaySupplierSheetState extends State<_PaySupplierSheet> {
  final _amountC = TextEditingController();
  final _noteC = TextEditingController();
  String _mode = 'cash';
  bool _saving = false;

  @override
  void dispose() {
    _amountC.dispose();
    _noteC.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amt = Money.parsePaise(_amountC.text);
    if (amt <= 0) {
      showSnack(context, 'Enter the amount', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await Repo.instance.paySupplier(
        supplierId: widget.supplier.id,
        amountPaise: amt,
        mode: _mode,
        note: _noteC.text.trim(),
      );
      if (mounted) {
        showSnack(context, 'Payment recorded');
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) {
        showSnack(context, 'Could not save - try again', error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Pay ${widget.supplier.name}',
              style: const TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  color: Ruby.ink)),
          const SizedBox(height: 14),
          TextField(
            controller: _amountC,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))
            ],
            decoration: const InputDecoration(hintText: 'Amount *'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final m in ['cash', 'upi', 'bank'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(m.toUpperCase(),
                        style: const TextStyle(fontSize: 11)),
                    selected: _mode == m,
                    selectedColor: Ruby.rubyLight,
                    onSelected: (_) => setState(() => _mode = m),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _noteC,
            decoration: const InputDecoration(hintText: 'Note (optional)'),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('RECORD PAYMENT',
                    style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}
