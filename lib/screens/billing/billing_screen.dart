import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../data/repo.dart';
import '../../services/pdf_service.dart';
import '../../services/sync_service.dart';
import '../../widgets/widgets.dart';

/// Smart billing screen (Miracle-style):
///  - 3-slim-column entry row: [ Product name | Qty | Price ]
///  - typing "S" suggests every product starting with S instantly
///  - selecting a product auto-fills saved Qty + Price, focus jumps to Qty
///  - numeric keyboard on qty/price, normal keyboard on product name
///  - totals are computed on integer paise: no rounding mistakes
class BillingScreen extends StatefulWidget {
  final Customer customer;
  const BillingScreen({super.key, required this.customer});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  final _repo = Repo.instance;

  final TextEditingController _productC = TextEditingController();
  final TextEditingController _qtyC = TextEditingController();
  final TextEditingController _rateC = TextEditingController();
  final TextEditingController _paidC = TextEditingController();
  final FocusNode _productF = FocusNode();
  final FocusNode _qtyF = FocusNode();
  final FocusNode _rateF = FocusNode();

  List<Product> _catalog = [];
  final List<CartLine> _cart = [];
  Product? _selected;
  bool _saving = false;
  int _billNo = 0; // invoice number this bill will get (header display)

  /// Payment mode for THIS bill: 'udhar' (credit, nothing received now)
  /// or 'jama' (cash received now). Miracle-style one-tap toggle.
  String _payMode = 'udhar';

  @override
  void initState() {
    super.initState();
    _loadCatalog();
    _loadHeader();
  }

  Future<void> _loadHeader() async {
    final no = await _repo.nextBillNo();
    if (!mounted) return;
    setState(() => _billNo = no);
  }

  @override
  void dispose() {
    _productC.dispose();
    _qtyC.dispose();
    _rateC.dispose();
    _paidC.dispose();
    _productF.dispose();
    _qtyF.dispose();
    _rateF.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    final list = await _repo.searchProducts('');
    if (!mounted) return;
    setState(() => _catalog = list);
  }

  // ---------------- product suggestion ----------------

  Iterable<Product> _options(String query) {
    if (query.isEmpty) return const Iterable<Product>.empty();
    final q = query.toLowerCase().trim();
    final starts = _catalog.where((p) => p.name.toLowerCase().startsWith(q)).take(8);
    if (starts.isNotEmpty) return starts;
    return _catalog.where((p) => p.name.toLowerCase().contains(q)).take(8);
  }

  void _selectProduct(Product p) {
    setState(() {
      _selected = p;
      _productC.text = p.name;
      _qtyC.text = qtyText(p.defaultQty);
      _rateC.text = Money.fmtRupeesInput(p.defaultPricePaise);
    });
    _qtyF.requestFocus();
  }

  // ---------------- cart ----------------

  int get _totalPaise => _cart.fold(0, (sum, line) => sum + line.amountPaise);

  void _addToCart() {
    final name = _selected?.name ?? _productC.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'Type a product name first');
      _productF.requestFocus();
      return;
    }
    final qty = double.tryParse(_qtyC.text.trim().replaceAll(',', '')) ?? 0;
    if (qty <= 0) {
      showSnack(context, 'Enter quantity');
      _qtyF.requestFocus();
      return;
    }
    final ratePaise = Money.parsePaise(_rateC.text);
    setState(() {
      final idx = _cart.indexWhere(
        (l) => l.name.toLowerCase() == name.toLowerCase() && l.ratePaise == ratePaise,
      );
      if (idx >= 0) {
        _cart[idx].qty += qty;
      } else {
        _cart.add(CartLine(
          productId: _selected?.id,
          name: name,
          qty: qty,
          ratePaise: ratePaise,
        ));
      }
      _selected = null;
      _productC.clear();
      _qtyC.clear();
      _rateC.clear();
    });
    _productF.requestFocus();
  }

  Future<void> _editLine(int index) async {
    final line = _cart[index];
    final qtyC = TextEditingController(text: qtyText(line.qty));
    final rateC = TextEditingController(text: Money.fmtRupeesInput(line.ratePaise));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Edit: ${line.name}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyC,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
              decoration: const InputDecoration(hintText: 'Quantity', isDense: false),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: rateC,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
              decoration: const InputDecoration(hintText: 'Rate', isDense: false),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() {
        line.qty = double.tryParse(qtyC.text.replaceAll(',', '')) ?? line.qty;
        line.ratePaise = Money.parsePaise(rateC.text);
      });
    }
    qtyC.dispose();
    rateC.dispose();
  }

  // ---------------- save ----------------

  Future<void> _save() async {
    if (_cart.isEmpty) {
      showSnack(context, 'Add at least one item');
      return;
    }
    final paid = _payMode == 'jama' ? Money.parsePaise(_paidC.text) : 0;
    if (paid > _totalPaise) {
      final ok = await confirmDialog(
        context,
        title: 'Received more than total',
        message:
            'Received amount is more than the bill total. The extra becomes advance (jama) in the customer ledger. Save anyway?',
        ok: 'Save',
      );
      if (!ok) return;
    }
    setState(() => _saving = true);
    try {
      final bill = await _repo.saveBill(
        customerId: widget.customer.id,
        customerName: widget.customer.name,
        lines: _cart,
        paidNowPaise: paid,
      );
      SyncService.instance.syncSoon();
      if (!mounted) return;
      await _showSavedSheet(bill);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showSavedSheet(Bill bill) async {
    final (full, items) = await _repo.billWithItems(bill.id);
    final shop = await _repo.shopProfile();
    final cust = await _repo.getCustomer(widget.customer.id);
    final (_, entries) = await _repo.ledger(widget.customer.id);
    final balance = entries.isEmpty ? 0 : entries.last.runningBalancePaise;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Ruby.greenLight,
                    child: const Icon(Icons.check, color: Ruby.green),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bill #${bill.billNo} saved',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Ruby.ink),
                        ),
                        Text(
                          '${widget.customer.name}  •  ${Money.fmt(full.totalPaise)}'
                          '  •  ${balance > 0 ? 'Due ${Money.fmt(balance)}' : balance < 0 ? 'Advance ${Money.fmt(-balance)}' : 'Settled'}',
                          style: const TextStyle(fontSize: 12.5, color: Ruby.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                icon: const Icon(Icons.share, size: 20),
                label: const Text('SHARE PDF BILL'),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await PdfService.instance.shareBill(
                    bill: full,
                    items: items,
                    shop: shop,
                    customerCity: cust?.city ?? '',
                    customerPhone: cust?.phone ?? '',
                    balanceAfterPaise: balance,
                  );
                  if (mounted) {
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  }
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.post_add, size: 20),
                label: const Text('NEW BILL (SAME CUSTOMER)'),
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _cart.clear();
                    _paidC.clear();
                  });
                },
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).popUntil((r) => r.isFirst);
                },
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- build ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.customer.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
            ),
            Text(
              [
                'Invoice #${_billNo == 0 ? '...' : _billNo}',
                if (widget.customer.city.isNotEmpty) widget.customer.city,
                Dt.fmtDate(DateTime.now()),
              ].join('  •  '),
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFFF3B7BC)),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          _entryRow(),
          Expanded(
            child: _cart.isEmpty
                ? EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'Cart is empty',
                    subtitle: 'Type a product name above. Saved quantity & price fill in automatically.',
                  )
                : _cartList(),
          ),
          _bottomBar(),
        ],
      ),
    );
  }

  Widget _entryRow() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      color: const Color(0xFFF2F2F4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: RawAutocomplete<Product>(
              textEditingController: _productC,
              focusNode: _productF,
              displayStringForOption: (p) => p.name,
              optionsBuilder: (TextEditingValue value) => _options(value.text),
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 5,
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 264),
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (context, i) {
                          final p = options.elementAt(i);
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.inventory_2_outlined, color: Ruby.ruby, size: 18),
                            title: Text(
                              p.name,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: Ruby.ink),
                            ),
                            subtitle: Text(
                              'Default qty ${qtyText(p.defaultQty)} ${p.unit}  •  ${Money.fmt(p.defaultPricePaise)}',
                              style: const TextStyle(fontSize: 11.5, color: Ruby.muted),
                            ),
                            onTap: () => onSelected(p),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                return TextField(
                  controller: _productC,
                  focusNode: _productF,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: 'Product name',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  ),
                  onSubmitted: (_) {
                    final typed = _productC.text.trim().toLowerCase();
                    Product? exact;
                    for (final p in _catalog) {
                      if (p.name.toLowerCase() == typed) {
                        exact = p;
                        break;
                      }
                    }
                    if (exact != null) {
                      _selectProduct(exact);
                    } else {
                      _qtyF.requestFocus();
                    }
                  },
                );
              },
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 1,
            child: TextField(
              controller: _qtyC,
              focusNode: _qtyF,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                hintText: 'Qty',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 12),
              ),
              style: const TextStyle(fontWeight: FontWeight.w700),
              onSubmitted: (_) => _rateF.requestFocus(),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 1,
            child: TextField(
              controller: _rateC,
              focusNode: _rateF,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                hintText: 'Price',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 12),
              ),
              style: const TextStyle(fontWeight: FontWeight.w700),
              onSubmitted: (_) => _addToCart(),
            ),
          ),
          SizedBox(
            width: 44,
            child: IconButton(
              onPressed: _addToCart,
              icon: const Icon(Icons.add_circle, color: Ruby.ruby, size: 30),
              tooltip: 'Add to bill',
            ),
          ),
        ],
      ),
    );
  }

  Widget _cartList() {
    return ListView.separated(
      itemCount: _cart.length,
      separatorBuilder: (_, __) => const Divider(indent: 16, endIndent: 16),
      itemBuilder: (context, i) {
        final line = _cart[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Ruby.rubyLight,
            radius: 16,
            child: Text('${i + 1}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Ruby.ruby)),
          ),
          title: Text(
            line.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: Ruby.ink),
          ),
          subtitle: Text(
            '${qtyText(line.qty)} × ${Money.fmt(line.ratePaise)}',
            style: const TextStyle(fontSize: 12.5, color: Ruby.muted),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                Money.fmt(line.amountPaise),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: Ruby.ink),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: Ruby.faint),
                onPressed: () => setState(() => _cart.removeAt(i)),
              ),
            ],
          ),
          onTap: () => _editLine(i),
        );
      },
    );
  }

  Widget _bottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Ruby.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Payment mode toggle: Credit/Udhar vs Cash/Jama (one tap).
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: _payChip(
                    value: 'udhar',
                    label: 'CREDIT / UDHAR',
                    icon: Icons.schedule_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _payChip(
                    value: 'jama',
                    label: 'CASH / JAMA',
                    icon: Icons.payments_outlined,
                  ),
                ),
              ],
            ),
          ),
          if (_payMode == 'jama')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const Icon(Icons.currency_rupee, size: 18, color: Ruby.muted),
                  const SizedBox(width: 8),
                  const Text('Received now', style: TextStyle(fontSize: 13, color: Ruby.muted)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _paidC,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: '0 (extra becomes advance)',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            color: Ruby.ruby,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            margin: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _payMode == 'jama' ? 'GRAND TOTAL' : 'TOTAL UDHAR',
                        style: const TextStyle(fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w800, color: Color(0xFFF3B7BC)),
                      ),
                      Text(
                        Money.fmt(_totalPaise),
                        style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      Text(
                        'Total items: ${_cart.fold<int>(0, (s, l) => s + l.qty.round())}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFFF3B7BC)),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Ruby.ruby,
                    minimumSize: const Size(150, 48),
                  ),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Ruby.ruby))
                      : const Text(
                          'SAVE & PRINT / PDF',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 0.2),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _payChip({
    required String value,
    required String label,
    required IconData icon,
  }) {
    final selected = _payMode == value;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() {
        _payMode = value;
        if (value == 'udhar') _paidC.clear();
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Ruby.ruby : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? Ruby.ruby : Ruby.line),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: selected ? Colors.white : Ruby.muted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: selected ? Colors.white : Ruby.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kept as a thin alias so older call sites keep working.
String qtyText(double qty) => Qty.fmt(qty);
