import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_log.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../data/repo.dart';
import '../../services/return_draft_service.dart';
import '../../services/sync_service.dart';
import '../../widgets/widgets.dart';

/// SALES RETURN ENTRY - works exactly like the billing screen:
///  - entry row at the TOP: [ Product name | Qty | Rate ] - Enter walks
///    name -> qty -> rate -> add -> name again, so a full return bill is
///    typed without ever touching the screen
///  - added products show as slim numbered bordered strips (1, 2, 3...)
///  - TOTAL + SAVE pinned in the ruby bottom bar
///  - the cart is auto-saved as a draft: back press / phone call can
///    never lose a half-typed return
///  - on save the amount is CREDITED (minus) in the customer's account
///    and the ledger merges it into the one net figure.
class SalesReturnEntryScreen extends StatefulWidget {
  final Customer customer;

  const SalesReturnEntryScreen({super.key, required this.customer});

  @override
  State<SalesReturnEntryScreen> createState() => _SalesReturnEntryScreenState();
}

class _SalesReturnEntryScreenState extends State<SalesReturnEntryScreen>
    with WidgetsBindingObserver {
  final _repo = Repo.instance;
  final ScrollController _cartScroll = ScrollController();

  final TextEditingController _productC = TextEditingController();
  final TextEditingController _qtyC = TextEditingController();
  final TextEditingController _rateC = TextEditingController();
  final TextEditingController _noteC = TextEditingController();
  final FocusNode _productF = FocusNode();
  final FocusNode _qtyF = FocusNode();
  final FocusNode _rateF = FocusNode();

  List<Product> _catalog = [];
  final List<CartLine> _lines = [];
  Product? _selected;
  bool _saving = false;
  bool _restored = false;

  /// Return date (back-datable): goods came back yesterday? Keep the
  /// books true - the ledger orders entries by this date.
  DateTime _returnDate = Dt.todayStart();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCatalog();
    _restoreDraft();
  }

  @override
  void didChangeMetrics() {
    // Keyboard open/close: one frame after the resize, snap the list
    // back inside its content (no empty space left at the bottom).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
      if (_cartScroll.hasClients) {
        final pos = _cartScroll.position;
        if (pos.pixels > pos.maxScrollExtent) {
          pos.jumpTo(pos.maxScrollExtent.clamp(0.0, double.infinity));
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Auto-save the lines so nothing is lost on back / app switch.
    unawaited(_persistDraft());
    _cartScroll.dispose();
    _productC.dispose();
    _qtyC.dispose();
    _rateC.dispose();
    _noteC.dispose();
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

  Future<void> _persistDraft() async {
    if (_lines.isEmpty) {
      await ReturnDraftService.instance.clear();
      return;
    }
    await ReturnDraftService.instance.save(ReturnDraft(
      customerId: widget.customer.id,
      customerName: widget.customer.name,
      lines: List.of(_lines),
      returnDateMs: _returnDate.millisecondsSinceEpoch,
      note: _noteC.text.trim(),
      savedAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Future<void> _restoreDraft() async {
    final d = await ReturnDraftService.instance.load();
    if (!mounted || d == null || _restored) return;
    if (d.customerId != widget.customer.id || d.lines.isEmpty) return;
    _restored = true;
    setState(() {
      _lines
        ..clear()
        ..addAll([
          for (final l in d.lines)
            CartLine(productId: l.productId, name: l.name, qty: l.qty, ratePaise: l.ratePaise),
        ]);
      if (d.returnDateMs > 0) {
        _returnDate = DateTime.fromMillisecondsSinceEpoch(d.returnDateMs);
      }
      _noteC.text = d.note;
    });
    showSnack(context, 'Draft restored - continue where you left');
  }

  Future<void> _loadCatalog() async {
    final list = await _repo.searchProducts('');
    if (!mounted) return;
    setState(() => _catalog = list);
  }

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
      _qtyC.text = Qty.fmt(p.defaultQty);
      _rateC.text = Money.fmtRupeesInput(p.defaultPricePaise);
    });
    _qtyF.requestFocus();
  }

  int get _totalPaise => _lines.fold(0, (sum, line) => sum + line.amountPaise);

  void _addLine() {
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
      _lines.add(CartLine(
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
    final line = _lines[index];
    final qtyC = TextEditingController(text: Qty.fmt(line.qty));
    final rateC = TextEditingController(text: Money.fmtRupeesInput(line.ratePaise));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Edit: ${line.name}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyC,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
              decoration: const InputDecoration(hintText: 'Quantity'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: rateC,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
              decoration: const InputDecoration(hintText: 'Rate'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
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

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _returnDate,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
      helpText: 'Select return date',
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (picked != null && mounted) {
      setState(() => _returnDate = DateTime(
            picked.year,
            picked.month,
            picked.day,
            now.hour,
            now.minute,
            now.second,
          ));
      _persistDraft();
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_lines.isEmpty) {
      showSnack(context, 'Add at least one item');
      return;
    }
    setState(() => _saving = true);
    try {
      SalesReturn ret;
      try {
        ret = await _repo.saveSalesReturn(
          customerId: widget.customer.id,
          customerName: widget.customer.name,
          lines: _lines,
          note: _noteC.text.trim(),
          date: _returnDate,
        );
      } catch (e) {
        appLog('[sales-return] save failed: $e');
        if (mounted) {
          showSnack(context, 'Return could not be saved - items are safe, try again',
              error: true);
        }
        return;
      }
      // Saved: empty the cart BEFORE dispose/lifecycle hooks can write
      // the saved lines back as a draft (ghost draft prevention).
      setState(() {
        _lines.clear();
        _noteC.clear();
        _returnDate = Dt.todayStart();
      });
      await ReturnDraftService.instance.clear();
      SyncService.instance.syncSoon();
      if (!mounted) return;
      showSnack(context,
          'Return #${ret.returnNo} saved - ${Money.fmt(ret.amountPaise)} credited to ${widget.customer.name}');
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: RubyAppBar(
        showBrand: false,
        title: widget.customer.name,
        subtitle: 'Sales return - amount goes to the party account',
      ),
      body: Column(
        children: [
          _dateBar(),
          _entryRow(),
          Expanded(
            child: _lines.isEmpty
                ? const EmptyState(
                    icon: Icons.keyboard_return,
                    title: 'No items yet',
                    subtitle:
                        'Type the product name, qty and rate of everything the '
                        'party returned. Press Enter after each box - every '
                        'product becomes a numbered line.',
                  )
                : _linesList(),
          ),
          _bottomBar(),
        ],
      ),
    );
  }

  Widget _dateBar() {
    final isToday = Dt.dayKey(_returnDate) == Dt.todayKey();
    return InkWell(
      onTap: _pickDate,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        color: const Color(0xFFF2F2F4),
        child: Row(
          children: [
            const Icon(Icons.calendar_month_outlined, size: 17, color: Ruby.ruby),
            const SizedBox(width: 8),
            const Text('Return date',
                style: TextStyle(fontSize: 12.5, color: Ruby.muted, fontWeight: FontWeight.w600)),
            const SizedBox(width: 10),
            Text(Dt.fmtDate(_returnDate),
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Ruby.ink)),
            if (!isToday) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Ruby.rubyLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  Dt.labelFor(Dt.dayKey(_returnDate)),
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Ruby.ruby),
                ),
              ),
            ],
            const Spacer(),
            const Icon(Icons.edit_calendar_outlined, size: 16, color: Ruby.faint),
            const SizedBox(width: 4),
            const Text('Change',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Ruby.ruby)),
          ],
        ),
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
                            title: Text(p.name,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: Ruby.ink)),
                            subtitle: Text(
                              'Default qty ${Qty.fmt(p.defaultQty)} ${p.unit}  |  ${Money.fmt(p.defaultPricePaise)}',
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
                hintText: 'Rate',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 12),
              ),
              style: const TextStyle(fontWeight: FontWeight.w700),
              onSubmitted: (_) => _addLine(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _linesList() {
    return ListView.separated(
      controller: _cartScroll,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      itemCount: _lines.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, i) {
        final line = _lines[i];
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _editLine(i),
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Ruby.line, width: 0.9),
            ),
            child: Row(
              children: [
                Text('${i + 1}.',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Ruby.ruby)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(line.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: Ruby.ink)),
                ),
                Text(
                  '${Qty.fmt(line.qty)} x ${Money.fmt(line.ratePaise, withSymbol: false)}',
                  style: const TextStyle(fontSize: 11.5, color: Ruby.muted),
                ),
                const SizedBox(width: 10),
                Text(Money.fmt(line.amountPaise),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Ruby.ink)),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() => _lines.removeAt(i));
                    _persistDraft();
                  },
                  child: const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.close, size: 16, color: Ruby.faint),
                  ),
                ),
              ],
            ),
          ),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _noteC,
                    decoration: const InputDecoration(
                      hintText: 'Note',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    ),
                    onChanged: (_) => _persistDraft(),
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: Ruby.ruby,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TOTAL CREDIT TO ACCOUNT',
                          style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFF3B7BC))),
                      Text(Money.fmt(_totalPaise),
                          style: const TextStyle(
                              fontSize: 21, fontWeight: FontWeight.w800, color: Colors.white)),
                      Text('Items: ${_lines.length}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFFF3B7BC))),
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
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Ruby.ruby))
                      : const Text('SAVE RETURN',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
