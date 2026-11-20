import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repo.dart';
import '../../models/models.dart';
import '../../services/sync_service.dart';
import '../../widgets/widgets.dart';

/// Purchase RETURN form: maal supplier ko wapas bheja. Item lines with
/// rate + GST, note, date. The amount is credited in the supplier's
/// account automatically (supplier ledger merges purchase_returns in).
class PurchaseReturnForm extends StatefulWidget {
  final Supplier supplier;
  const PurchaseReturnForm({super.key, required this.supplier});

  @override
  State<PurchaseReturnForm> createState() => _PurchaseReturnFormState();
}

class _PurchaseReturnFormState extends State<PurchaseReturnForm> {
  final TextEditingController _nameC = TextEditingController();
  final TextEditingController _qtyC = TextEditingController();
  final TextEditingController _rateC = TextEditingController();
  final TextEditingController _gstC = TextEditingController();
  final TextEditingController _noteC = TextEditingController();
  final FocusNode _nameF = FocusNode();
  final FocusNode _qtyF = FocusNode();
  final FocusNode _rateF = FocusNode();

  List<Product> _catalog = [];
  Product? _selected;
  final List<PurchaseCartLine> _lines = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void dispose() {
    _nameC.dispose();
    _qtyC.dispose();
    _rateC.dispose();
    _gstC.dispose();
    _noteC.dispose();
    _nameF.dispose();
    _qtyF.dispose();
    _rateF.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    final list = await Repo.instance.searchProducts('');
    if (!mounted) return;
    setState(() => _catalog = list);
  }

  int get _subtotalPaise => _lines.fold(0, (s, l) => s + l.amountPaise);
  int get _gstPaise => _lines.fold(0, (s, l) => s + l.gstPaise);

  Iterable<Product> _options(String query) {
    if (query.isEmpty) return const Iterable<Product>.empty();
    final q = query.toLowerCase().trim();
    final starts =
        _catalog.where((p) => p.name.toLowerCase().startsWith(q)).take(8);
    if (starts.isNotEmpty) return starts;
    return _catalog.where((p) => p.name.toLowerCase().contains(q)).take(8);
  }

  void _selectProduct(Product p) {
    setState(() {
      _selected = p;
      _nameC.text = p.name;
      _qtyC.text = Qty.fmt(p.defaultQty);
      _rateC.text = Money.fmtRupeesInput(p.defaultPricePaise);
    });
    _qtyF.requestFocus();
  }

  void _addLine() {
    final name = _selected?.name ?? _nameC.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'Product name likhiye');
      _nameF.requestFocus();
      return;
    }
    final qty = double.tryParse(_qtyC.text.trim().replaceAll(',', '')) ?? 0;
    if (qty <= 0) {
      showSnack(context, 'Quantity likhiye');
      _qtyF.requestFocus();
      return;
    }
    final rate = Money.parsePaise(_rateC.text);
    if (rate <= 0) {
      showSnack(context, 'Rate likhiye');
      _rateF.requestFocus();
      return;
    }
    final gst = double.tryParse(_gstC.text.trim().replaceAll(',', '')) ?? 0;
    setState(() {
      _lines.add(PurchaseCartLine(
        productId: _selected?.id,
        name: name,
        qty: qty,
        ratePaise: rate,
        gstPercent: gst,
      ));
      _selected = null;
      _nameC.clear();
      _qtyC.clear();
      _rateC.clear();
      _gstC.clear();
    });
    _nameF.requestFocus();
  }

  Future<void> _save() async {
    if (_lines.isEmpty) {
      showSnack(context, 'Kam se kam 1 item add karo');
      return;
    }
    setState(() => _saving = true);
    try {
      await Repo.instance.savePurchaseReturn(
        supplierId: widget.supplier.id,
        supplierName: widget.supplier.name,
        lines: _lines,
        note: _noteC.text.trim(),
      );
      SyncService.instance.syncSoon();
      if (!mounted) return;
      showSnack(context, 'Purchase return saved - party account me jama ho gaya');
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        showSnack(context, 'Save fail hua - dobara try karo', error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: RubyAppBar(
        title: 'Purchase Return',
        subtitle: widget.supplier.name,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Ruby.fieldBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Ruby.line),
                  ),
                  child: const Text(
                    'Jo maal party ko wapas bheja hai uski detail yahan '
                    'likhiye. Amount is party ke account me JAMA ho jayega '
                    '(bakaya kam ho jayega).',
                    style: TextStyle(fontSize: 12.5, color: Ruby.muted),
                  ),
                ),
                const SizedBox(height: 12),
                _entryRow(),
                const SizedBox(height: 8),
                for (var i = 0; i < _lines.length; i++) _lineRow(i),
                const SizedBox(height: 10),
                _totals(),
                const SizedBox(height: 10),
                TextField(
                  controller: _noteC,
                  decoration: const InputDecoration(
                      hintText: 'Note (kya wapas gaya, kyun...)'),
                ),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Ruby.line)),
            ),
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: ElevatedButton(
              style:
                  ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('SAVE RETURN',
                      style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _entryRow() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: RawAutocomplete<Product>(
              textEditingController: _nameC,
              focusNode: _nameF,
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
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (context, i) => ListTile(
                          dense: true,
                          title: Text(options.elementAt(i).name),
                          onTap: () => onSelected(options.elementAt(i)),
                        ),
                      ),
                    ),
                  ),
                );
              },
              fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                return TextField(
                  controller: _nameC,
                  focusNode: _nameF,
                  decoration: const InputDecoration(
                    hintText: 'Product name',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  ),
                  onSubmitted: (_) => _qtyF.requestFocus(),
                );
              },
            ),
          ),
          const SizedBox(width: 5),
          _smallField(_qtyC, _qtyF, 'Qty', () => _rateF.requestFocus()),
          const SizedBox(width: 5),
          _smallField(_rateC, _rateF, 'Rate', _addLine),
          const SizedBox(width: 5),
          _smallField(_gstC, null, 'GST%', _addLine, width: 52),
          const SizedBox(width: 4),
          IconButton(
            onPressed: _addLine,
            icon: const Icon(Icons.add_circle, color: Ruby.ruby, size: 28),
          ),
        ],
      ),
    );
  }

  Widget _smallField(
    TextEditingController c,
    FocusNode? f,
    String hint,
    VoidCallback onSubmitted, {
    double width = 62,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: c,
        focusNode: f,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))
        ],
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        ),
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
        onSubmitted: (_) => onSubmitted(),
      ),
    );
  }

  Widget _lineRow(int i) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Ruby.line, width: 0.9),
        ),
        child: Row(
          children: [
            Text('${i + 1}.',
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Ruby.ruby)),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                _lines[i].name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Ruby.ink),
              ),
            ),
            Text(
              '${Qty.fmt(_lines[i].qty)} x ${Money.fmt(_lines[i].ratePaise, withSymbol: false)}',
              style: const TextStyle(fontSize: 11, color: Ruby.muted),
            ),
            const SizedBox(width: 6),
            Text(
              Money.fmt(_lines[i].amountPaise),
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: Ruby.ink),
            ),
            SizedBox(
              width: 26,
              height: 26,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 16,
                icon: const Icon(Icons.close, color: Ruby.faint),
                onPressed: () => setState(() => _lines.removeAt(i)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _totals() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Ruby.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                  child: Text('Return amount',
                      style: TextStyle(fontSize: 12.5, color: Ruby.muted))),
              Text(Money.fmt(_subtotalPaise),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: Ruby.ink)),
            ],
          ),
          if (_gstPaise > 0)
            Row(
              children: [
                const Expanded(
                    child: Text('GST',
                        style: TextStyle(fontSize: 12.5, color: Ruby.muted))),
                Text(Money.fmt(_gstPaise),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: Ruby.ink)),
              ],
            ),
          const Divider(height: 14),
          Row(
            children: [
              const Text('TOTAL CREDIT',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: Ruby.ruby)),
              const Spacer(),
              Text(Money.fmt(_subtotalPaise + _gstPaise),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Ruby.ink)),
            ],
          ),
        ],
      ),
    );
  }
}
