import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../data/repo.dart';
import '../../services/bill_draft_service.dart';
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

class _BillingScreenState extends State<BillingScreen> with WidgetsBindingObserver {
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
  bool _restored = false;
  int _billNo = 0; // invoice number this bill will get (header display)

  /// Bill date (Miracle-style): the user can back-date or pre-date a
  /// bill (kal ya parso). Every bill keeps its own date; reports and
  /// ledger group by this date, not by "when the phone saved it".
  DateTime _billDate = Dt.todayStart();

  /// Saving a brand-new product straight from the bill ("Deo, 3, 103"
  /// -> tap the bookmark icon -> it lives in inventory).
  bool _savingProduct = false;

  /// Payment mode for THIS bill: 'udhar' (credit, nothing received now)
  /// or 'jama' (cash received now). Miracle-style one-tap toggle.
  String _payMode = 'udhar';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCatalog();
    _loadHeader();
    _restoreDraft();
  }

  Future<void> _loadHeader() async {
    final no = await _repo.nextBillNo();
    if (!mounted) return;
    setState(() => _billNo = no);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Auto-save whatever is in the cart so nothing is ever lost
    // (call, app switch, accidental back - the draft survives).
    unawaited(_persistDraft());
    _productC.dispose();
    _qtyC.dispose();
    _rateC.dispose();
    _paidC.dispose();
    _productF.dispose();
    _qtyF.dispose();
    _rateF.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _persistDraft();
    }
  }

  // ---------------- draft (auto-save) ----------------

  Future<void> _persistDraft() async {
    if (_cart.isEmpty) {
      await BillDraftService.instance.clear();
      return;
    }
    await BillDraftService.instance.save(BillDraft(
      customerId: widget.customer.id,
      customerName: widget.customer.name,
      lines: List.of(_cart),
      payMode: _payMode,
      paidNowPaise: _payMode == 'jama' ? Money.parsePaise(_paidC.text) : 0,
      billDateMs: _billDate.millisecondsSinceEpoch,
      savedAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Future<void> _restoreDraft() async {
    final d = await BillDraftService.instance.load();
    if (!mounted || d == null || _restored) return;
    if (d.customerId != widget.customer.id || d.lines.isEmpty) return;
    _restored = true;
    setState(() {
      _cart
        ..clear()
        ..addAll([
          for (final l in d.lines)
            CartLine(productId: l.productId, name: l.name, qty: l.qty, ratePaise: l.ratePaise),
        ]);
      _payMode = d.payMode == 'jama' ? 'jama' : 'udhar';
      if (_payMode == 'jama' && d.paidNowPaise > 0) {
        _paidC.text = Money.fmtRupeesInput(d.paidNowPaise);
      }
      if (d.billDateMs > 0) {
        _billDate = Dt.dayStartOf(d.billDateMs);
      }
    });
    showSnack(context, 'Draft restored - continue where you left');
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
      // ALWAYS a new numbered line - even for the same product. Every
      // row stays fully independent (Miracle-style): editing row 2 can
      // never touch row 3.
      _cart.add(CartLine(
        productId: _selected?.id,
        name: name,
        qty: qty,
        ratePaise: ratePaise,
      ));
      _selected = null;
      _productC.clear();
      _qtyC.clear();
      _rateC.clear();
    });
    _persistDraft();
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
      _persistDraft();
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
        billDate: _billDate,
      );
      await BillDraftService.instance.clear(); // draft consumed
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
                    _payMode = 'udhar';
                    _billDate = Dt.todayStart();
                  });
                  _persistDraft();
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

  /// Header identity, Miracle-style: where the customer used to show as
  /// just "Riya", the full "City - Shop name" appears now
  /// (e.g. "Rajkot - Riya Cosmetic").
  String get _headerTitle {
    final city = widget.customer.city.trim();
    final shop = widget.customer.shopName.trim();
    if (city.isNotEmpty && shop.isNotEmpty) return '$city - $shop';
    if (shop.isNotEmpty) return shop;
    if (city.isNotEmpty) return '$city - ${widget.customer.name}';
    return widget.customer.name;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // No R chip here - the full width belongs to the customer identity,
      // exactly like the printed header of a bill.
      appBar: RubyAppBar(
        showBrand: false,
        title: _headerTitle,
        subtitle: 'Invoice #${_billNo == 0 ? '...' : _billNo}',
      ),
      body: Column(
        children: [
          _dateBar(),
          _entryRow(),
          Expanded(
            child: _cart.isEmpty
                ? const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'Cart is empty',
                    subtitle:
                        'Type a product name, qty and price. A saved name fills everything in. '
                        'New product? Tap the inventory icon to save it for next time.',
                  )
                : _cartList(),
          ),
          _bottomBar(),
        ],
      ),
    );
  }

  // ---------------- bill date (Miracle-style) ----------------

  Future<void> _pickBillDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _billDate,
      firstDate: DateTime(now.year - 10),
      lastDate: now.add(const Duration(days: 30)), // kal / parso ka bill bhi ban sakta hai
      helpText: 'Select bill date',
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (picked != null && mounted) {
      setState(() => _billDate = DateTime(picked.year, picked.month, picked.day));
      _persistDraft();
    }
  }

  /// Slim tappable strip under the app bar: "Bill date  19 Nov 2026".
  /// Tap -> calendar. The chosen date is stored with the draft, shown on
  /// the bill, and used by reports/ledger (Miracle behaviour).
  Widget _dateBar() {
    final isToday = Dt.dayKey(_billDate) == Dt.todayKey();
    return InkWell(
      onTap: _pickBillDate,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        color: const Color(0xFFF2F2F4),
        child: Row(
          children: [
            const Icon(Icons.calendar_month_outlined, size: 17, color: Ruby.ruby),
            const SizedBox(width: 8),
            const Text(
              'Bill date',
              style: TextStyle(fontSize: 12.5, color: Ruby.muted, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 10),
            Text(
              Dt.fmtDate(_billDate),
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Ruby.ink),
            ),
            if (!isToday) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Ruby.rubyLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  Dt.labelFor(Dt.dayKey(_billDate)),
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Ruby.ruby),
                ),
              ),
            ],
            const Spacer(),
            const Icon(Icons.edit_calendar_outlined, size: 16, color: Ruby.faint),
            const SizedBox(width: 4),
            const Text(
              'Change',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Ruby.ruby),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- quick save to inventory ----------------

  /// "Deo, 3, 103" -> tap the inventory icon -> the product is saved to
  /// inventory with these defaults. Next time typing "Deo" auto-fills
  /// it; quantity/price stay editable from the Inventory screen.
  Future<void> _saveProductToInventory() async {
    final name = _productC.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'Type the product name first');
      _productF.requestFocus();
      return;
    }
    final qty = double.tryParse(_qtyC.text.trim().replaceAll(',', '')) ?? 0;
    final pricePaise = Money.parsePaise(_rateC.text);
    if (qty <= 0 || pricePaise <= 0) {
      showSnack(context, 'Enter quantity and price to save in inventory');
      return;
    }
    setState(() => _savingProduct = true);
    try {
      final existing = await _repo.productByName(name);
      if (existing != null) {
        await _repo.upsertProduct(Product(
          id: existing.id,
          name: existing.name,
          unit: existing.unit,
          defaultQty: qty,
          defaultPricePaise: pricePaise,
          trackStock: existing.trackStock,
          stockQty: existing.stockQty,
          lowStock: existing.lowStock,
          createdAt: existing.createdAt,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ));
        if (mounted) {
          showSnack(context,
              '"${existing.name}" updated in inventory (qty ${Qty.fmt(qty)}, ${Money.fmt(pricePaise)})');
        }
      } else {
        await _repo.newProduct(name: name, defaultQty: qty, defaultPricePaise: pricePaise);
        if (mounted) {
          showSnack(context, '"$name" saved to inventory - next time it will auto-fill');
        }
      }
      await _loadCatalog();
    } finally {
      if (mounted) setState(() => _savingProduct = false);
    }
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
            width: 92,
            child: Row(
              children: [
                Expanded(
                  child: IconButton(
                    onPressed: _savingProduct ? null : _saveProductToInventory,
                    icon: _savingProduct
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Ruby.ruby),
                          )
                        : const Icon(Icons.inventory_2_outlined, color: Ruby.ink, size: 23),
                    tooltip: 'Save this product to inventory',
                  ),
                ),
                Expanded(
                  child: IconButton(
                    onPressed: _addToCart,
                    icon: const Icon(Icons.add_circle, color: Ruby.ruby, size: 30),
                    tooltip: 'Add to bill',
                  ),
                ),
              ],
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
                onPressed: () {
                  setState(() => _cart.removeAt(i));
                  _persistDraft();
                },
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
      onTap: () {
        _payMode = value;
        if (value == 'udhar') _paidC.clear();
        _persistDraft();
        setState(() {});
      },
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
