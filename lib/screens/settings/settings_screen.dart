import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/repo.dart';
import '../../services/sync_service.dart';
import '../../widgets/widgets.dart';

/// Shop profile + bill format settings. These values print on the PDF bill.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _nameC = TextEditingController();
  final _addrC = TextEditingController();
  final _phoneC = TextEditingController();
  final _gstinC = TextEditingController();

  String _format = 't80'; // t80 | a5
  bool _saving = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameC.dispose();
    _addrC.dispose();
    _phoneC.dispose();
    _gstinC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final shop = await Repo.instance.shopProfile();
    if (!mounted) return;
    setState(() {
      _nameC.text = shop['shop_name'] ?? '';
      _addrC.text = shop['shop_addr'] ?? '';
      _phoneC.text = shop['shop_phone'] ?? '';
      _gstinC.text = shop['gstin'] ?? '';
      _format = shop['bill_format'] == 'a5' ? 'a5' : 't80';
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Repo.instance.saveShopProfile({
        'shop_name': _nameC.text.trim(),
        'shop_addr': _addrC.text.trim(),
        'shop_phone': _phoneC.text.trim(),
        'gstin': _gstinC.text.trim(),
        'bill_format': _format,
      });
      if (!mounted) return;
      showSnack(context, 'Bill format saved');
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: RubyAppBar(title: 'Bill Format & Shop'),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Ruby.ruby))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SectionHeader('Shop profile (prints on bill)', color: Ruby.ruby),
                TextField(
                  controller: _nameC,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(hintText: 'Shop name', isDense: false),
                  style: const TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _addrC,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(hintText: 'Address', isDense: false),
                  style: const TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneC,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(hintText: 'Phone', isDense: false),
                  style: const TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _gstinC,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(hintText: 'GSTIN (optional)', isDense: false),
                  style: const TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 20),
                const SectionHeader('Bill paper size', color: Ruby.ruby),
                _formatTile(
                  't80',
                  '80mm receipt',
                  'Small thermal-printer style slip - shop name, items, total',
                  Icons.receipt_long,
                ),
                const SizedBox(height: 8),
                _formatTile(
                  'a5',
                  'A5 letterhead',
                  'Full bill - header, item table, balance line, signature area',
                  Icons.picture_as_pdf_outlined,
                ),
                const SizedBox(height: 26),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('SAVE'),
                ),
                const SizedBox(height: 16),
                if (SyncService.instance.fbReady) _syncCard(),
              ],
            ),
    );
  }

  Widget _formatTile(String value, String title, String subtitle, IconData icon) {
    final selected = _format == value;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _format = value),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? Ruby.rubyLight : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? Ruby.ruby : Ruby.line, width: selected ? 1.6 : 1),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? Ruby.ruby : Ruby.muted, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: Ruby.ink)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: Ruby.muted)),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? Ruby.ruby : Ruby.faint,
            ),
          ],
        ),
      ),
    );
  }

  Widget _syncCard() {
    return ValueListenableBuilder<SyncStatus>(
      valueListenable: SyncService.instance.status,
      builder: (context, status, _) {
        final label = switch (status) {
          SyncStatus.offline => 'Signed out',
          SyncStatus.syncing => 'Syncing...',
          SyncStatus.synced => 'All data synced to Firebase',
          SyncStatus.error => 'Sync failed - will retry',
        };
        return Card(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Ruby.line),
          ),
          child: ListTile(
            leading: const Icon(Icons.cloud_sync_outlined, color: Ruby.ruby),
            title: const Text('Cloud sync', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text(label, style: const TextStyle(fontSize: 12.5)),
            trailing: TextButton(
              onPressed: () => SyncService.instance.syncNow(),
              child: const Text('Sync now'),
            ),
          ),
        );
      },
    );
  }
}
