import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repo.dart';
import '../../models/models.dart';
import '../../services/sync_service.dart';
import '../../widgets/widgets.dart';
import 'supplier_ledger_screen.dart';

/// Purchase parties (suppliers) - "Surat Shardha Cosmetic" etc. Every
/// supplier has a live balance: opening + purchases - returns - payments.
/// Positive = we still owe them (bakaya).
class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
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

  Future<void> _openForm({Supplier? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SupplierFormSheet(existing: existing),
    );
    if (saved == true) {
      SyncService.instance.syncSoon();
      _filter();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: RubyAppBar(
        title: 'Purchase Parties',
        subtitle: 'Suppliers - goods come from these parties',
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Ruby.ruby,
        foregroundColor: Colors.white,
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('NEW PARTY',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: TextField(
              controller: _searchC,
              onChanged: (_) => _filter(),
              decoration: const InputDecoration(
                hintText: 'Search party name, city...',
                isDense: true,
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: _rows.isEmpty
                ? const EmptyState(
                    icon: Icons.local_shipping_outlined,
                    title: 'No purchase parties yet',
                    subtitle:
                        'Add the shops you buy from (Surat, Mumbai, local agents). '
                        'Purchase bills, returns and payments stay party-wise.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final r = _rows[i];
                      final balance = (r['balance_paise'] ?? 0) as int;
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () async {
                          final sup = await Repo.instance
                              .getSupplier(r['id'] as String);
                          if (!mounted || sup == null) return;
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  SupplierLedgerScreen(supplier: sup),
                            ),
                          );
                          _filter();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Ruby.line),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: Ruby.rubyLight,
                                child: Text(
                                  (r['name'] as String? ?? '?')
                                      .substring(0, 1)
                                      .toUpperCase(),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: Ruby.ruby),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(r['name'] as String? ?? '',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15,
                                            color: Ruby.ink)),
                                    if ((r['city'] as String? ?? '')
                                            .isNotEmpty ||
                                        (r['phone'] as String? ?? '')
                                            .isNotEmpty)
                                      Text(
                                        [
                                          r['city'] as String? ?? '',
                                          r['phone'] as String? ?? '',
                                        ]
                                            .where((e) => e.isNotEmpty)
                                            .join('  |  '),
                                        style: const TextStyle(
                                            fontSize: 12, color: Ruby.muted),
                                      ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    balance > 0
                                        ? 'BAKAYA ${Money.fmt(balance)}'
                                        : balance < 0
                                            ? 'ADV ${Money.fmt(-balance)}'
                                            : 'SETTLED',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: balance > 0
                                          ? Ruby.ruby
                                          : Ruby.green,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Add / edit a purchase party (bottom sheet form).
class SupplierFormSheet extends StatefulWidget {
  final Supplier? existing;

  /// Prefills the party name (used by the picker's inline "Add '<typed
  /// name>' as new party" flow - the name the user searched for is
  /// already in the form when it opens).
  final String initialName;
  const SupplierFormSheet({this.existing, this.initialName = ''});

  @override
  State<SupplierFormSheet> createState() => SupplierFormSheetState();
}

class SupplierFormSheetState extends State<SupplierFormSheet> {
  late final TextEditingController _nameC;
  late final TextEditingController _shopC;
  late final TextEditingController _cityC;
  late final TextEditingController _phoneC;
  late final TextEditingController _addrC;
  late final TextEditingController _openingC;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameC = TextEditingController(text: e?.name ?? widget.initialName);
    _shopC = TextEditingController(text: e?.shopName ?? '');
    _cityC = TextEditingController(text: e?.city ?? '');
    _phoneC = TextEditingController(text: e?.phone ?? '');
    _addrC = TextEditingController(text: e?.address ?? '');
    _openingC = TextEditingController(
        text: e == null ? '' : Money.fmtRupeesInput(e.openingBalancePaise));
  }

  @override
  void dispose() {
    _nameC.dispose();
    _shopC.dispose();
    _cityC.dispose();
    _phoneC.dispose();
    _addrC.dispose();
    _openingC.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameC.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'Enter the party name', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final opening = Money.parsePaise(_openingC.text);
      if (widget.existing == null) {
        await Repo.instance.newSupplier(
          name: name,
          shopName: _shopC.text.trim(),
          city: _cityC.text.trim(),
          phone: _phoneC.text.trim(),
          address: _addrC.text.trim(),
          openingBalancePaise: opening,
        );
      } else {
        final e = widget.existing!;
        await Repo.instance.upsertSupplier(Supplier(
          id: e.id,
          name: name,
          shopName: _shopC.text.trim(),
          city: _cityC.text.trim(),
          phone: _phoneC.text.trim(),
          address: _addrC.text.trim(),
          // opening balance stays admin-of-the-past: editable until any
          // transaction exists is a nicety we skip - the field edits here.
          openingBalancePaise: opening,
          createdAt: e.createdAt,
          updatedAt: e.updatedAt,
          isDeleted: e.isDeleted,
          dirty: 1,
        ));
      }
      if (mounted) {
        showSnack(context, 'Party saved');
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) {
        showSnack(context, 'Could not save - try again', error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existing == null ? 'New Purchase Party' : 'Edit Party',
              style: const TextStyle(
                  fontSize: 16.5, fontWeight: FontWeight.w800, color: Ruby.ink),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nameC,
              autofocus: widget.existing == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Party name *'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _shopC,
              textCapitalization: TextCapitalization.words,
              decoration:
                  const InputDecoration(hintText: 'Firm / shop name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _cityC,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'City'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _phoneC,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(hintText: 'Phone'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _addrC,
              maxLines: 2,
              decoration: const InputDecoration(hintText: 'Address'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _openingC,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                hintText: 'Opening balance (jo pehle se bakaya hai)',
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('SAVE',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, letterSpacing: 1)),
            ),
          ],
        ),
      ),
    );
  }
}
