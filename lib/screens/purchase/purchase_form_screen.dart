import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/app_log.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repo.dart';
import '../../models/models.dart';
import '../../services/sync_service.dart';
import '../../widgets/widgets.dart';
import 'suppliers_screen.dart';
import '../../services/bill_scan_service.dart';

/// Purchase bill form (billing jaisa hi system): supplier party, party ka
/// apna bill number, date, item lines with per-product GST %, parcel
/// charges, and the photo of the paper bill.
///
/// AI SCAN: "Scan Bill" lets the owner photograph the supplier's paper
/// bill; on-device text recognition reads it and the form pre-fills the
/// party bill number, item lines (name / qty / rate / GST%) and totals.
/// The user reviews and corrects before saving - AI suggests, human
/// confirms.
class PurchaseFormScreen extends StatefulWidget {
  /// Supplier picked in advance (from the party ledger).
  final Supplier? supplier;

  /// Pen-edit of a saved purchase bill (same purchase number).
  final Purchase? editPurchase;

  const PurchaseFormScreen({super.key, this.supplier, this.editPurchase});

  @override
  State<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

class _PurchaseFormScreenState extends State<PurchaseFormScreen> {
  final _repo = Repo.instance;

  bool get _isEdit => widget.editPurchase != null;

  final TextEditingController _nameC = TextEditingController();
  final TextEditingController _qtyC = TextEditingController();
  final TextEditingController _rateC = TextEditingController();
  final TextEditingController _gstC = TextEditingController();
  final TextEditingController _partyBillC = TextEditingController();
  final TextEditingController _parcelC = TextEditingController();
  final TextEditingController _noteC = TextEditingController();
  final FocusNode _nameF = FocusNode();
  final FocusNode _qtyF = FocusNode();
  final FocusNode _rateF = FocusNode();

  List<Product> _catalog = [];
  Product? _selected;
  Supplier? _supplier;
  final List<PurchaseCartLine> _lines = [];
  String _photoPath = '';
  bool _saving = false;
  bool _scanning = false;
  DateTime _date = Dt.todayStart();

  @override
  void initState() {
    super.initState();
    _supplier = widget.supplier;
    _loadCatalog();
    if (_isEdit) {
      _loadForEdit();
    }
  }

  @override
  void dispose() {
    _nameC.dispose();
    _qtyC.dispose();
    _rateC.dispose();
    _gstC.dispose();
    _partyBillC.dispose();
    _parcelC.dispose();
    _noteC.dispose();
    _nameF.dispose();
    _qtyF.dispose();
    _rateF.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    final list = await _repo.searchProducts('');
    if (!mounted) return;
    setState(() => _catalog = list);
  }

  Future<void> _loadForEdit() async {
    final (p, items) = await _repo.purchaseWithItems(widget.editPurchase!.id);
    if (!mounted) return;
    setState(() {
      // supplier identity is carried on the existing row; the header
      // shows the snapshot name while editing.
      _partyBillC.text = p.partyBillNo;
      _parcelC.text = Money.fmtRupeesInput(p.parcelPaise);
      _noteC.text = p.note;
      _photoPath = p.photoPath;
      _date = DateTime.fromMillisecondsSinceEpoch(p.purchaseDate);
      _lines.addAll([
        for (final it in items)
          PurchaseCartLine(
            productId: it.productId,
            name: it.productName,
            qty: it.qty,
            ratePaise: it.ratePaise,
            gstPercent: it.gstPercent,
          ),
      ]);
    });
  }

  // ---------------- totals ----------------

  int get _subtotalPaise =>
      _lines.fold(0, (s, l) => s + l.amountPaise);
  int get _gstPaise => _lines.fold(0, (s, l) => s + l.gstPaise);
  int get _parcelPaise => Money.parsePaise(_parcelC.text);
  int get _totalPaise => _subtotalPaise + _gstPaise + _parcelPaise;

  // ---------------- item entry ----------------

  Iterable<Product> _options(String query) {
    if (query.isEmpty) return const Iterable<Product>.empty();
    final q = query.toLowerCase().trim();
    final starts =
        _catalog.where((p) => p.name.toLowerCase().startsWith(q)).take(8);
    if (starts.isNotEmpty) return starts;
    return _catalog
        .where((p) => p.name.toLowerCase().contains(q))
        .take(8);
  }

  void _selectProduct(Product p) {
    setState(() {
      _selected = p;
      _nameC.text = p.name;
      _qtyC.text = Qty.fmt(p.defaultQty);
      _rateC.text = Money.fmtRupeesInput(p.defaultPricePaise);
      _gstC.text = '';
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
    final gst =
        double.tryParse(_gstC.text.trim().replaceAll(',', '')) ?? 0;
    if (gst < 0 || gst > 100) {
      showSnack(context, 'GST 0-100 ke beech hona chahiye');
      return;
    }
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

  void _editLine(int index) {
    final l = _lines[index];
    final qtyC = TextEditingController(text: Qty.fmt(l.qty));
    final rateC = TextEditingController(text: Money.fmtRupeesInput(l.ratePaise));
    final gstC = TextEditingController(
        text: l.gstPercent == 0 ? '' : l.gstPercent.toString());
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Edit: ${l.name}',
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyC,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(hintText: 'Quantity'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: rateC,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(hintText: 'Rate'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: gstC,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(hintText: 'GST % (e.g. 18)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              setState(() {
                l.qty = double.tryParse(qtyC.text.replaceAll(',', '')) ?? l.qty;
                l.ratePaise = Money.parsePaise(rateC.text);
                l.gstPercent =
                    double.tryParse(gstC.text.replaceAll(',', '')) ?? 0;
              });
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ).then((_) {
      qtyC.dispose();
      rateC.dispose();
      gstC.dispose();
    });
  }

  // ---------------- photo ----------------

  Future<void> _pickPhoto({required bool camera}) async {
    try {
      final x = await ImagePicker().pickImage(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1600,
      );
      if (x == null) return;
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(
          '${docs.path}${Platform.pathSeparator}purchase_photos');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final dst = File(
          '${dir.path}${Platform.pathSeparator}p${_nowMs()}.jpg');
      await File(x.path).copy(dst.path);
      setState(() => _photoPath = dst.path);
    } catch (_) {
      if (mounted) {
        showSnack(context, 'Photo nahi mil gayi', error: true);
      }
    }
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  // ---------------- AI scan hook (filled by the scan service) ----------------

  /// Runs the on-device bill scanner on the attached photo and pre-fills
  /// the form. Implemented in lib/services/bill_scan_service.dart.
  Future<void> _scanBill() async {
    if (_photoPath.isEmpty) {
      showSnack(context,
          'Pehle bill ki photo lo (camera) ya gallery se choose karo');
      return;
    }
    setState(() => _scanning = true);
    try {
      final result =
          await BillScanService.instance.scan(_photoPath);
      if (!mounted) return;
      if (result == null) {
        showSnack(context,
            'Scan se data nahi padha gaya - haath se daal do', error: true);
        return;
      }
      setState(() {
        if (result.partyBillNo.isNotEmpty && !_isEdit) {
          _partyBillC.text = result.partyBillNo;
        }
        if (result.lines.isNotEmpty) {
          _lines
            ..clear()
            ..addAll(result.lines);
        }
        if (result.parcelPaise > 0) {
          _parcelC.text = Money.fmtRupeesInput(result.parcelPaise);
        }
      });
      showSnack(context,
          'Scan complete - ${result.lines.length} items mile, check karke save karo');
    } catch (e) {
      appLog('[purchase] scan failed: $e');
      if (mounted) {
        showSnack(context, 'Scan fail hua - haath se daal do', error: true);
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  // ---------------- save ----------------

  Future<void> _save() async {
    if (_lines.isEmpty) {
      showSnack(context, 'Kam se kam 1 item add karo');
      return;
    }
    if ((_supplier?.name ?? '').isEmpty && !_isEdit) {
      showSnack(context, 'Purchase party choose karo (upar tap karo)');
      return;
    }
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await _repo.updatePurchase(
          existing: widget.editPurchase!,
          lines: _lines,
          parcelPaise: _parcelPaise,
          partyBillNo: _partyBillC.text.trim(),
          note: _noteC.text.trim(),
          photoPath: _photoPath,
          date: _date,
        );
      } else {
        await _repo.savePurchase(
          supplierId: _supplier!.id,
          supplierName: _supplier!.name,
          supplierPhone: _supplier!.phone,
          partyBillNo: _partyBillC.text.trim(),
          lines: _lines,
          parcelPaise: _parcelPaise,
          note: _noteC.text.trim(),
          photoPath: _photoPath,
          date: _date,
        );
      }
      SyncService.instance.syncSoon();
      if (!mounted) return;
      showSnack(context, _isEdit
          ? 'Purchase bill updated'
          : 'Purchase bill saved');
      Navigator.pop(context);
    } catch (e) {
      appLog('[purchase] save failed: $e');
      if (mounted) {
        showSnack(context, 'Save fail hua - dobara try karo', error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------- build ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: RubyAppBar(
        title: _isEdit
            ? 'Editing Purchase #${widget.editPurchase!.purchaseNo}'
            : 'New Purchase Bill',
        subtitle: 'Maal aaya - kya aaya, kitna rate, kitna GST',
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
              children: [
                _supplierRow(),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _partyBillC,
                        decoration: const InputDecoration(
                          hintText: 'Party ka bill no.',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: _pickDate,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 11),
                        decoration: BoxDecoration(
                          color: Ruby.fieldBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Ruby.line),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_month_outlined,
                                size: 15, color: Ruby.ruby),
                            const SizedBox(width: 6),
                            Text(
                              Dt.fmtDate(_date),
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: Ruby.ink),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _itemEntryRow(),
                const SizedBox(height: 6),
                if (_lines.isEmpty)
                  const EmptyState(
                    icon: Icons.inventory_outlined,
                    title: 'Items add karo',
                    subtitle:
                        'Jo maal aaya hai: naam, qty, rate aur uska GST%. '
                        'Bill ki photo se auto-fill ke liye "SCAN BILL" dabao.',
                  )
                else
                  ..._linesList(),
                const SizedBox(height: 10),
                _totalsCard(),
                const SizedBox(height: 10),
                _photoRow(),
                const SizedBox(height: 10),
                TextField(
                  controller: _noteC,
                  decoration: const InputDecoration(
                      hintText: 'Note (parcel detail, bhai-char, etc.)'),
                ),
              ],
            ),
          ),
          _saveBar(),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 10),
      lastDate: now.add(const Duration(days: 30)),
      helpText: 'Purchase date',
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (picked != null && mounted) {
      setState(() => _date = DateTime(
            picked.year,
            picked.month,
            picked.day,
            now.hour,
            now.minute,
          ));
    }
  }

  Widget _supplierRow() {
    final name = _isEdit
        ? widget.editPurchase!.supplierName
        : (_supplier?.name ?? '');
    return InkWell(
      onTap: _isEdit ? null : _pickSupplier,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Ruby.rubyLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Ruby.ruby.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.local_shipping_outlined, color: Ruby.ruby, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name.isEmpty ? 'Purchase party choose karo (tap)' : name,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: name.isEmpty ? Ruby.muted : Ruby.ruby,
                ),
              ),
            ),
            if (!_isEdit)
              const Icon(Icons.chevron_right, size: 18, color: Ruby.faint),
          ],
        ),
      ),
    );
  }

  Future<void> _pickSupplier() async {
    final picked = await showModalBottomSheet<Supplier>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _SupplierPickerSheet(),
    );
    if (picked != null) {
      setState(() => _supplier = picked);
    }
  }

  Widget _itemEntryRow() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
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
              optionsBuilder: (TextEditingValue value) =>
                  _options(value.text),
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 5,
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (context, i) {
                          final p = options.elementAt(i);
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.inventory_2_outlined,
                                color: Ruby.ruby, size: 18),
                            title: Text(p.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5)),
                            onTap: () => onSelected(p),
                          );
                        },
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
          _smallField(_qtyC, _qtyF, 'Qty', onSubmitted: () => _rateF.requestFocus()),
          const SizedBox(width: 5),
          _smallField(_rateC, _rateF, 'Rate', onSubmitted: _addLine),
          const SizedBox(width: 5),
          _smallField(_gstC, null, 'GST%',
              onSubmitted: _addLine, width: 52),
          const SizedBox(width: 4),
          IconButton(
            onPressed: _addLine,
            icon: const Icon(Icons.add_circle, color: Ruby.ruby, size: 28),
            tooltip: 'Add item',
          ),
        ],
      ),
    );
  }

  Widget _smallField(
    TextEditingController c,
    FocusNode? f,
    String hint, {
    required VoidCallback onSubmitted,
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

  List<Widget> _linesList() {
    return [
      for (var i = 0; i < _lines.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _editLine(i),
            child: Container(
              height: 40,
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
                    style: const TextStyle(
                        fontSize: 11, color: Ruby.muted),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Ruby.fieldBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _lines[i].gstPercent == 0
                          ? '-'
                          : 'GST ${_lines[i].gstPercent.toStringAsFixed(0)}%',
                      style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: Ruby.muted),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    Money.fmt(_lines[i].amountPaise),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: Ruby.ink),
                  ),
                  const SizedBox(width: 2),
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 16,
                      icon: const Icon(Icons.close, color: Ruby.faint),
                      onPressed: () =>
                          setState(() => _lines.removeAt(i)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ];
  }

  Widget _totalsCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Ruby.line),
      ),
      child: Column(
        children: [
          _row('Subtotal (maal)', _subtotalPaise),
          _row('GST total', _gstPaise),
          Row(
            children: [
              const Expanded(
                  child: Text('Parcel / transport kharcha',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: Ruby.muted,
                          fontWeight: FontWeight.w600))),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _parcelC,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))
                  ],
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(
                    hintText: '0',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  ),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const Divider(height: 14),
          Row(
            children: [
              const Text('GRAND TOTAL',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: Ruby.ruby)),
              const Spacer(),
              Text(
                Money.fmt(_totalPaise),
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Ruby.ink),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, int paise) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 12.5, color: Ruby.muted))),
          Text(Money.fmt(paise),
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Ruby.ink)),
        ],
      ),
    );
  }

  Widget _photoRow() {
    final file = _photoPath.isEmpty ? null : File(_photoPath);
    final exists = file != null && file.existsSync();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Ruby.line),
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: Ruby.fieldBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Ruby.line),
            ),
            child: exists
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Image.file(file!, fit: BoxFit.cover),
                  )
                : const Icon(Icons.receipt_long_outlined,
                    color: Ruby.faint),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Paper bill ki photo',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: Ruby.ink)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 34),
                      ),
                      onPressed: () => _pickPhoto(camera: true),
                      icon: const Icon(Icons.photo_camera_outlined,
                          size: 16),
                      label: const Text('Camera',
                          style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 34),
                      ),
                      onPressed: () => _pickPhoto(camera: false),
                      icon: const Icon(Icons.photo_outlined, size: 16),
                      label: const Text('Gallery',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Ruby.ruby,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            onPressed: _scanning ? null : _scanBill,
            icon: _scanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.document_scanner_outlined, size: 17),
            label: const Text('SCAN',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _saveBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Ruby.line)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(
                _isEdit ? 'UPDATE PURCHASE BILL' : 'SAVE PURCHASE BILL',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
      ),
    );
  }
}

/// Search + pick a supplier (and add a brand-new party on the spot).
class _SupplierPickerSheet extends StatefulWidget {
  const _SupplierPickerSheet();

  @override
  State<_SupplierPickerSheet> createState() => _SupplierPickerSheetState();
}

class _SupplierPickerSheetState extends State<_SupplierPickerSheet> {
  final _searchC = TextEditingController();
  List<Map<String, Object?>> _rows = [];

  @override
  void initState() {
    super.initState();
    _filter();
  }

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  Future<void> _filter() async {
    final rows = await Repo.instance.searchSuppliers(_searchC.text);
    if (!mounted) return;
    setState(() => _rows = rows);
  }

  Future<void> _addNew() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const SupplierFormSheet(),
    );
    if (saved == true) _filter();
  }

  Future<void> _pick(Map<String, Object?> row) async {
    final sup = await Repo.instance.getSupplier(row['id'] as String);
    if (!mounted || sup == null) return;
    Navigator.pop(context, sup);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Choose purchase party',
              style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  color: Ruby.ink)),
          const SizedBox(height: 12),
          TextField(
            controller: _searchC,
            autofocus: true,
            onChanged: (_) => _filter(),
            decoration: const InputDecoration(
              hintText: 'Search party name, city...',
              isDense: true,
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _rows.length,
              itemBuilder: (context, i) {
                final r = _rows[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.local_shipping_outlined,
                      color: Ruby.ruby, size: 20),
                  title: Text(r['name'] as String? ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(r['city'] as String? ?? '',
                      style: const TextStyle(fontSize: 11.5)),
                  onTap: () => _pick(r),
                );
              },
            ),
          ),
          OutlinedButton.icon(
            onPressed: _addNew,
            icon: const Icon(Icons.person_add_alt_1, size: 18),
            label: const Text('NEW PARTY ADD KARO'),
          ),
        ],
      ),
    );
  }
}
