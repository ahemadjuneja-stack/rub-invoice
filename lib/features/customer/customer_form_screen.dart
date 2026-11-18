import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../data/repo.dart';
import '../../services/sync_service.dart';
import '../common/widgets.dart';

/// Add or edit a customer: name, city, phone, opening balance.
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
  final _nameC = TextEditingController();
  final _cityC = TextEditingController();
  final _phoneC = TextEditingController();
  final _openingC = TextEditingController();

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
      _nameC.text = c.name;
      _cityC.text = c.city;
      _phoneC.text = c.phone;
      _openingC.text = c.openingBalancePaise == 0 ? '' : Money.fmtRupeesInput(c.openingBalancePaise);
    });
  }

  @override
  void dispose() {
    _nameC.dispose();
    _cityC.dispose();
    _phoneC.dispose();
    _openingC.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameC.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'Customer name is required', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final opening = Money.parsePaise(_openingC.text);
      if (widget.customerId == null) {
        await Repo.instance.newCustomer(
          name: name,
          city: _cityC.text.trim(),
          phone: _phoneC.text.trim(),
          openingBalancePaise: opening,
        );
      } else {
        final c = await Repo.instance.getCustomer(widget.customerId!);
        if (c != null) {
          await Repo.instance.upsertCustomer(
            c.copyWith(
              name: name,
              city: _cityC.text.trim(),
              phone: _phoneC.text.trim(),
              openingBalancePaise: opening,
            ),
          );
        }
      }
      SyncService.instance.syncSoon();
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Customer' : 'New Customer')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameC,
            textCapitalization: TextCapitalization.words,
            autofocus: !_isEdit,
            decoration: const InputDecoration(hintText: 'Customer name *', isDense: false),
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _cityC,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'City (e.g. Rajkot)', isDense: false),
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _phoneC,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d+]')), LengthLimitingTextInputFormatter(12)],
            decoration: const InputDecoration(hintText: 'Phone (optional)', isDense: false),
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _openingC,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
            decoration: const InputDecoration(
              hintText: 'Old balance / udhar (optional)',
              isDense: false,
              helperText: 'Amount this customer already owed before using the app',
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
