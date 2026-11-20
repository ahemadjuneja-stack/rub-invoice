import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../data/repo.dart';
import '../../services/sync_service.dart';
import '../../widgets/widgets.dart';

/// Add or edit a customer. Field order (Miracle-style):
/// City -> Shop name -> Customer name -> Mobile -> Address line.
/// The address line has a "+" that opens a big full-address editor.
class CustomerFormScreen extends StatefulWidget {
  final String? customerId; // null = new
  final String prefillName;
  final String prefillCity;
  const CustomerFormScreen({
    super.key,
    this.customerId,
    this.prefillName = '',
    this.prefillCity = '',
  });

  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
  final _cityC = TextEditingController();
  final _shopC = TextEditingController();
  final _nameC = TextEditingController();
  final _phoneC = TextEditingController();
  final _addressC = TextEditingController();

  bool _isEdit = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameC.text = widget.prefillName;
    _cityC.text = widget.prefillCity;
    _load();
  }

  Future<void> _load() async {
    if (widget.customerId == null) return;
    final c = await Repo.instance.getCustomer(widget.customerId!);
    if (c == null || !mounted) return;
    setState(() {
      _isEdit = true;
      _cityC.text = c.city;
      _shopC.text = c.shopName;
      _nameC.text = c.name;
      _phoneC.text = c.phone;
      _addressC.text = c.address;
    });
  }

  @override
  void dispose() {
    _cityC.dispose();
    _shopC.dispose();
    _nameC.dispose();
    _phoneC.dispose();
    _addressC.dispose();
    super.dispose();
  }

  /// Big full-address editor opened from the "+" on the address line.
  Future<void> _openAddressEditor() async {
    final c = TextEditingController(text: _addressC.text);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Full address',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: c,
          minLines: 3,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Shop / house no, street, area, landmark...',
            isDense: false,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Done')),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() => _addressC.text = c.text.trim());
    }
    c.dispose();
  }

  Future<void> _save() async {
    final name = _nameC.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'Customer name is required', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.customerId == null) {
        await Repo.instance.newCustomer(
          name: name,
          shopName: _shopC.text.trim(),
          city: _cityC.text.trim(),
          phone: _phoneC.text.trim(),
          address: _addressC.text.trim(),
        );
      } else {
        final c = await Repo.instance.getCustomer(widget.customerId!);
        if (c != null) {
          await Repo.instance.upsertCustomer(
            c.copyWith(
              name: name,
              shopName: _shopC.text.trim(),
              city: _cityC.text.trim(),
              phone: _phoneC.text.trim(),
              address: _addressC.text.trim(),
            ),
          );
        }
      }
      SyncService.instance.syncSoon();
      if (mounted) {
        showSnack(context, _isEdit ? 'Customer updated' : 'Customer saved');
        Navigator.pop(context);
      }
    } catch (e) {
      // v0.2.19: a failed save used to reset silently - the user tapped
      // SAVE and "nothing happened". Now it always tells them.
      debugPrint('[customer] save failed: $e');
      if (mounted) {
        showSnack(context, 'Could not save customer - please try again',
            error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _dec(String hint) => InputDecoration(hintText: hint, isDense: false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: RubyAppBar(title: _isEdit ? 'Edit Customer' : 'New Customer'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _cityC,
            textCapitalization: TextCapitalization.words,
            autofocus: !_isEdit,
            decoration: _dec('City (e.g. Rajkot)'),
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _shopC,
            textCapitalization: TextCapitalization.words,
            decoration: _dec('Shop name'),
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _nameC,
            textCapitalization: TextCapitalization.words,
            decoration: _dec('Customer name *'),
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _phoneC,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d+]')), LengthLimitingTextInputFormatter(12)],
            decoration: _dec('Mobile number'),
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _addressC,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Address line',
              isDense: false,
              helperText: 'Tap + to write the full big address',
              suffixIcon: IconButton(
                onPressed: _openAddressEditor,
                icon: const Icon(Icons.add_circle_outline, color: Ruby.ruby, size: 24),
                tooltip: 'Write full address',
              ),
            ),
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 26),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('SAVE CUSTOMER'),
          ),
        ],
      ),
    );
  }
}
