import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../data/repo.dart';
import '../../services/sync_service.dart';
import '../../widgets/widgets.dart';

/// Purchase invoices (maal kharida): every supplier bill with its amount
/// and an optional photo of the paper bill - clicked with the camera or
/// picked from the gallery, saved right next to the amount.
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
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseFormScreen()));
    _reload();
  }

  Future<void> _deletePurchase(Purchase p) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete purchase?',
      message: '"${p.supplierName}" - ${Money.fmt(p.amountPaise)} '
          '(${Dt.fmtDate(Dt.dayStartOf(p.purchaseDate))}) will be removed from purchase records.',
      ok: 'Delete',
      dangerous: true,
    );
    if (!ok) return;
    await Repo.instance.deletePurchase(p.id);
    SyncService.instance.syncSoon();
    _reload();
    if (mounted) showSnack(context, 'Purchase deleted');
  }

  void _openDetails(Purchase p) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
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
                    backgroundColor: Ruby.rubyLight,
                    child: const Icon(Icons.local_shipping_outlined, color: Ruby.ruby, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Purchase #${p.purchaseNo}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Ruby.ink),
                        ),
                        Text(
                          p.supplierName,
                          style: const TextStyle(fontSize: 12.5, color: Ruby.muted),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    Money.fmt(p.amountPaise),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Ruby.ruby),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _detailRow('Date', Dt.fmtDate(Dt.dayStartOf(p.purchaseDate))),
              if (p.supplierPhone.isNotEmpty) _detailRow('Phone', p.supplierPhone),
              if (p.note.isNotEmpty) _detailRow('Details', p.note),
              const SizedBox(height: 10),
              if (p.photoPath.isNotEmpty && File(p.photoPath).existsSync()) ...[
                GestureDetector(
                  onTap: () => _showPhotoFull(p.photoPath),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: Image.file(
                        File(p.photoPath),
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Center(
                  child: Text(
                    'Tap photo to view full screen',
                    style: TextStyle(fontSize: 11, color: Ruby.faint),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                icon: const Icon(Icons.delete_outline, size: 20),
                label: const Text('DELETE PURCHASE'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _deletePurchase(p);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Text(label, style: const TextStyle(fontSize: 12.5, color: Ruby.faint)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Ruby.ink)),
          ),
        ],
      ),
    );
  }

  void _showPhotoFull(String path) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                maxScale: 4,
                child: Image.file(File(path), filterQuality: FilterQuality.medium),
              ),
            ),
            Positioned(
              top: 24,
              right: 12,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 26),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _items.fold<int>(0, (s, p) => s + p.amountPaise);
    return Scaffold(
      appBar: const RubyAppBar(title: 'Purchase Invoices', subtitle: 'Maal kharida - supplier bills'),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Ruby.ruby,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TOTAL PURCHASES',
                        style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFF3B7BC)),
                      ),
                      Text(
                        Money.fmt(total),
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_items.length} bills',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Ruby.ruby))
                : _items.isEmpty
                    ? const EmptyState(
                        icon: Icons.local_shipping_outlined,
                        title: 'No purchase bills yet',
                        subtitle:
                            'Record everything you buy: supplier name, amount and a photo of the paper bill. '
                            'Tap New Purchase to add the first one.',
                      )
                    : RefreshIndicator(
                        color: Ruby.ruby,
                        onRefresh: _reload,
                        child: ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (_, __) =>
                              const Divider(indent: 16, endIndent: 16, height: 1),
                          itemBuilder: (context, i) => _purchaseTile(_items[i]),
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'purchase_fab',
        onPressed: _openForm,
        icon: const Icon(Icons.add, size: 26),
        label: const Text('New Purchase', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }

  Widget _purchaseTile(Purchase p) {
    final photoOk = p.photoPath.isNotEmpty && File(p.photoPath).existsSync();
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 52,
          height: 52,
          color: Ruby.fieldBg,
          child: photoOk
              ? Image.file(
                  File(p.photoPath),
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.receipt_long_outlined, color: Ruby.faint, size: 22),
                )
              : const Icon(Icons.local_shipping_outlined, color: Ruby.faint, size: 22),
        ),
      ),
      title: Text(
        p.supplierName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: Ruby.ink),
      ),
      subtitle: Text(
        [
          'Purchase #${p.purchaseNo}',
          Dt.fmtDate(Dt.dayStartOf(p.purchaseDate)),
          if (p.note.isNotEmpty) p.note,
        ].join('  \u2022  '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: Ruby.muted),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            Money.fmt(p.amountPaise),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Ruby.ruby),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 19, color: Ruby.faint),
            tooltip: 'Delete purchase',
            onPressed: () => _deletePurchase(p),
          ),
        ],
      ),
      onTap: () => _openDetails(p),
    );
  }
}

// ---------------- new purchase form ----------------

class PurchaseFormScreen extends StatefulWidget {
  const PurchaseFormScreen({super.key});

  @override
  State<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

class _PurchaseFormScreenState extends State<PurchaseFormScreen> {
  final _supplierC = TextEditingController();
  final _phoneC = TextEditingController();
  final _amountC = TextEditingController();
  final _noteC = TextEditingController();

  DateTime _date = Dt.todayStart();
  String _photoPath = ''; // temporary picked file until saved
  int _nextNo = 0;
  bool _saving = false;

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadNo();
  }

  Future<void> _loadNo() async {
    final no = await Repo.instance.nextPurchaseNo();
    if (!mounted) return;
    setState(() => _nextNo = no);
  }

  @override
  void dispose() {
    _supplierC.dispose();
    _phoneC.dispose();
    _amountC.dispose();
    _noteC.dispose();
    super.dispose();
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
      setState(() => _date = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _takePhoto(ImageSource source) async {
    try {
      final x = await _picker.pickImage(
        source: source,
        imageQuality: 72, // keeps the file small but readable
        maxWidth: 1600,
      );
      if (x == null) return;
      setState(() => _photoPath = x.path);
    } catch (_) {
      if (mounted) {
        showSnack(context,
            'Could not open the ${source == ImageSource.camera ? 'camera' : 'gallery'}',
            error: true);
      }
    }
  }

  Future<void> _removePhoto() async {
    setState(() => _photoPath = '');
  }

  /// Copies the picked photo into the app's documents folder so it
  /// survives gallery cleanups, then returns the new path.
  Future<String?> _persistPhoto() async {
    if (_photoPath.isEmpty) return null;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}${Platform.pathSeparator}purchase_photos');
      if (!await dir.exists()) await dir.create(recursive: true);
      final f = File('${dir.path}${Platform.pathSeparator}${const Uuid().v4()}.jpg');
      await File(_photoPath).copy(f.path);
      return f.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    final supplier = _supplierC.text.trim();
    if (supplier.isEmpty) {
      showSnack(context, 'Supplier name is required', error: true);
      return;
    }
    final amount = Money.parsePaise(_amountC.text);
    if (amount <= 0) {
      showSnack(context, 'Enter the bill amount', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final savedPhoto = await _persistPhoto();
      await Repo.instance.savePurchase(
        supplierName: supplier,
        supplierPhone: _phoneC.text.trim(),
        amountPaise: amount,
        note: _noteC.text.trim(),
        photoPath: savedPhoto ?? '',
        date: _date,
      );
      SyncService.instance.syncSoon();
      if (mounted) {
        showSnack(context, 'Purchase saved');
        Navigator.pop(context);
      }
    } catch (e) {
      // v0.2.19: never fail silently.
      if (mounted) {
        showSnack(context, 'Purchase could not be saved - please try again',
            error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: RubyAppBar(
        title: 'New Purchase',
        subtitle: 'Purchase #${_nextNo == 0 ? '...' : _nextNo}',
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _supplierC,
            textCapitalization: TextCapitalization.words,
            autofocus: true,
            decoration:
                const InputDecoration(hintText: 'Supplier / company name (e.g. Sharma Traders) *'),
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _phoneC,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d+\-\s]'))],
                  decoration: const InputDecoration(hintText: 'Phone (optional)'),
                  style: const TextStyle(fontSize: 15),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _amountC,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
                  decoration: const InputDecoration(hintText: 'Amount (\u20B9) *'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Date row: Miracle-style - the purchase can be back-dated or
          // pre-dated just like a sale bill.
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Ruby.line),
                borderRadius: BorderRadius.circular(12),
                color: Ruby.fieldBg,
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_outlined, size: 18, color: Ruby.ruby),
                  const SizedBox(width: 10),
                  const Text('Date', style: TextStyle(fontSize: 13, color: Ruby.muted)),
                  const SizedBox(width: 10),
                  Text(
                    Dt.fmtDate(_date),
                    style:
                        const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Ruby.ink),
                  ),
                  const Spacer(),
                  const Icon(Icons.edit_calendar_outlined, size: 16, color: Ruby.faint),
                  const SizedBox(width: 4),
                  const Text('Change',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Ruby.ruby)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _noteC,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Details (items bought, their bill no...)'),
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 18),
          const Text(
            'BILL PHOTO',
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: Ruby.muted),
          ),
          const SizedBox(height: 8),
          if (_photoPath.isNotEmpty) ...[
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: Image.file(
                      File(_photoPath),
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 18, color: Colors.red),
                      tooltip: 'Remove photo',
                      onPressed: _removePhoto,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.photo_camera_outlined, size: 20, color: Ruby.ruby),
                  label: const Text('Click photo', style: TextStyle(fontSize: 13)),
                  onPressed: () => _takePhoto(ImageSource.camera),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.photo_outlined, size: 20, color: Ruby.ruby),
                  label: const Text('From gallery', style: TextStyle(fontSize: 13)),
                  onPressed: () => _takePhoto(ImageSource.gallery),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Photo of the paper bill stays safe on this phone with the purchase record.',
            style: TextStyle(fontSize: 11.5, color: Ruby.faint),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('SAVE PURCHASE',
                    style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.3)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
