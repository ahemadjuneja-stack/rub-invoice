import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../data/repo.dart';
import '../../models/models.dart';
import '../../widgets/widgets.dart';

/// Delivery (transport) details of a bill - the display that opens right
/// after "Done" on a saved bill, and reachable again from the bill view.
///
/// The trader records HOW the goods went (Transport / In Hand / Courier
/// / Pending), captures the billty (lorry receipt) photo when the goods
/// went by transport - the photo deletes itself after 45 days - and
/// writes a transport note. Everything shows again whenever the bill
/// opens, and the details share to WhatsApp with one tap.
Future<BillDispatch?> showDispatchSheet(BuildContext context, {required Bill bill}) {
  return showModalBottomSheet<BillDispatch>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _DispatchSheet(bill: bill),
  );
}

/// Full-screen, zoomable viewer for a billty photo.
void showPhotoFullscreen(BuildContext context, String path) {
  showDialog<void>(
    context: context,
    builder: (ctx) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              maxScale: 4,
              child: Image.file(File(path), fit: BoxFit.contain),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// How many days the billty photo still has before it deletes itself.
String billtyDaysLeft(BillDispatch d) {
  if (d.billtyPath.isEmpty || d.billtyAt <= 0) return '';
  final used = DateTime.now()
      .difference(DateTime.fromMillisecondsSinceEpoch(d.billtyAt))
      .inDays;
  final left = Repo.billtyRetentionDays - used;
  if (left <= 0) return 'photo deletes today';
  return 'photo keeps ${left == 1 ? '1 more day' : '$left more days'}';
}

/// Shares the delivery details as text (+ the billty photo when it is
/// still on the phone) through the Android share sheet - WhatsApp is
/// the first tap for the traders.
Future<void> shareDispatchDetails(Bill bill, BillDispatch d, {String title = ''}) async {
  final head = title.isNotEmpty ? title : 'Bill #${bill.billNo} - ${bill.customerName}';
  final buf = StringBuffer()
    ..writeln(head)
    ..writeln('Delivery: ${d.modeLabel}');
  if (d.note.isNotEmpty) buf.writeln('Note: ${d.note}');
  buf.write('- Ruby Invoice');
  final photo = d.billtyPath;
  if (photo.isNotEmpty && File(photo).existsSync()) {
    await Share.shareXFiles(
      [XFile(photo)],
      subject: 'Billty - Bill #${bill.billNo}',
      text: buf.toString(),
    );
  } else {
    await Share.share(buf.toString(), subject: 'Billty - Bill #${bill.billNo}');
  }
}

class _DispatchSheet extends StatefulWidget {
  final Bill bill;
  const _DispatchSheet({required this.bill});

  @override
  State<_DispatchSheet> createState() => _DispatchSheetState();
}

class _DispatchSheetState extends State<_DispatchSheet> {
  final _repo = Repo.instance;
  final _noteC = TextEditingController();

  String _mode = ''; // transport | inhand | courier | pending ('' = not picked)
  String _billtyPath = ''; // preview path (tmp pick, or the kept saved photo)
  bool _photoChanged = false; // new pick / removal -> persist (or clear) on save
  BillDispatch? _existing;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteC.dispose();
    super.dispose();
  }

  /// Pre-fills the sheet with the details already saved for this bill
  /// (edit from the bill view, or re-open after the first save).
  Future<void> _load() async {
    final d = await _repo.dispatchFor(widget.bill.id);
    if (!mounted || d == null) return;
    setState(() {
      _existing = d;
      _mode = d.mode;
      _noteC.text = d.note;
      _billtyPath = d.billtyPath;
    });
  }

  Future<void> _pick(ImageSource src) async {
    try {
      final x = await ImagePicker().pickImage(source: src, imageQuality: 72, maxWidth: 1600);
      if (x == null) return;
      setState(() {
        _billtyPath = x.path;
        _photoChanged = true;
      });
    } catch (_) {
      if (mounted) showSnack(context, 'Could not open the camera / gallery');
    }
  }

  /// Copies the picked billty photo into the app's documents folder so
  /// it survives gallery cleanups, then returns the new path.
  Future<String?> _persistBillty(String tmpPath) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}${Platform.pathSeparator}billty_photos');
      if (!await dir.exists()) await dir.create(recursive: true);
      final f =
          File('${dir.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}.jpg');
      await File(tmpPath).copy(f.path);
      return f.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    if (_mode.isEmpty && _noteC.text.trim().isEmpty && _billtyPath.isEmpty) {
      showSnack(context, 'Select how the goods went first');
      return;
    }
    setState(() => _saving = true);
    try {
      String path = _billtyPath;
      if (_photoChanged && _billtyPath.isNotEmpty) {
        path = await _persistBillty(_billtyPath) ?? '';
      }
      final d = await _repo.saveDispatch(
        billId: widget.bill.id,
        mode: _mode,
        note: _noteC.text.trim(),
        billtyPath: path,
      );
      if (!mounted) return;
      setState(() {
        _existing = d;
        _billtyPath = d.billtyPath;
        _photoChanged = false;
      });
      showSnack(context, 'Delivery details saved');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _modeChip(String value, IconData icon, String label) {
    final selected = _mode == value;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _mode = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
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
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: selected ? Colors.white : Ruby.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bill = widget.bill;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Ruby.rubyLight,
                    child: Icon(Icons.local_shipping_outlined, size: 20, color: Ruby.ruby),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Delivery details',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Ruby.ink),
                        ),
                        Text(
                          'Bill #${bill.billNo} - ${bill.customerName}',
                          style: const TextStyle(fontSize: 12.5, color: Ruby.muted),
                        ),
                      ],
                    ),
                  ),
                  if (_existing != null)
                    IconButton(
                      tooltip: 'Share on WhatsApp',
                      icon: const Icon(Icons.share_outlined, color: Ruby.ruby),
                      onPressed: () => shareDispatchDetails(bill, _existing!),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'GOODS SENT BY',
                style: TextStyle(fontSize: 10.5, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: Ruby.muted),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _modeChip('transport', Icons.local_shipping_outlined, 'TRANSPORT')),
                  const SizedBox(width: 8),
                  Expanded(child: _modeChip('inhand', Icons.directions_walk_outlined, 'IN HAND')),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _modeChip('courier', Icons.markunread_mailbox_outlined, 'COURIER')),
                  const SizedBox(width: 8),
                  Expanded(child: _modeChip('pending', Icons.schedule_outlined, 'PENDING')),
                ],
              ),
              // Billty photo: only for transport - or whenever a photo
              // already exists so it can be viewed / removed.
              if (_mode == 'transport' || _billtyPath.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Ruby.line),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.receipt_long_outlined, size: 15, color: Ruby.ruby),
                          SizedBox(width: 6),
                          Text(
                            'BILLTY (LORRY RECEIPT) PHOTO',
                            style: TextStyle(fontSize: 10.5, letterSpacing: 1, fontWeight: FontWeight.w800, color: Ruby.muted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_billtyPath.isEmpty)
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                                label: const Text('TAKE PHOTO', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                                onPressed: () => _pick(ImageSource.camera),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.photo_outlined, size: 18),
                                label: const Text('GALLERY', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                                onPressed: () => _pick(ImageSource.gallery),
                              ),
                            ),
                          ],
                        )
                      else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: () => showPhotoFullscreen(context, _billtyPath),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(_billtyPath),
                                  width: 64,
                                  height: 64,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 64,
                                    height: 64,
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
                                    'Billty photo added',
                                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Ruby.ink),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Tap to view - deletes automatically after 45 days',
                                    style: const TextStyle(fontSize: 11, color: Ruby.faint),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove photo',
                              icon: const Icon(Icons.delete_outline, size: 20, color: Ruby.muted),
                              onPressed: () => setState(() {
                                _billtyPath = '';
                                _photoChanged = true;
                              }),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: _noteC,
                maxLines: 3,
                minLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Transport note (optional) - transporter name, GR no, etc.',
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Ruby.ruby),
                      )
                    : const Text(
                        'SAVE DETAILS',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1),
                      ),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: Text(_existing != null ? 'Close' : 'Skip'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
