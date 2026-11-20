import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repo.dart';
import '../../models/models.dart';
import '../../services/sync_service.dart';
import '../../widgets/widgets.dart';

/// SALES RETURN (customer): kisi party ka maal wapas aaya. The amount is
/// credited in that customer's ledger (jama) with the full item detail -
/// what came back, how much, at which rate.
class SalesReturnScreen extends StatefulWidget {
  const SalesReturnScreen({super.key});

  @override
  State<SalesReturnScreen> createState() => _SalesReturnScreenState();
}

class _SalesReturnScreenState extends State<SalesReturnScreen> {
  List<SalesReturn> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await Repo.instance.salesReturns();
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  Future<void> _openForm() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _SalesReturnFormSheet(),
    );
    if (saved == true) {
      SyncService.instance.syncSoon();
      _reload();
    }
  }

  Future<void> _openDetails(SalesReturn r) async {
    final items = await Repo.instance.salesReturnItems(r.id);
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(18),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.customerName,
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Ruby.ink)),
                      Text(
                        'Return #${r.returnNo}  |  ${Dt.fmtDate(Dt.dayStartOf(r.returnDate))}',
                        style:
                            const TextStyle(fontSize: 12, color: Ruby.muted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final ok = await confirmDialog(
                      context,
                      title: 'Delete return #${r.returnNo}?',
                      message:
                          'The credit in ${r.customerName}\'s account will be '
                          'removed.',
                      ok: 'Delete',
                      dangerous: true,
                    );
                    if (ok) {
                      await Repo.instance.deleteSalesReturn(r.id);
                      SyncService.instance.syncSoon();
                      _reload();
                    }
                  },
                  icon: const Icon(Icons.delete_outline, color: Ruby.ruby),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final it in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Ruby.line, width: 0.9),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(it.productName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: Ruby.ink)),
                      ),
                      Text(
                        '${Qty.fmt(it.qty)} x ${Money.fmt(it.ratePaise, withSymbol: false)}',
                        style: const TextStyle(
                            fontSize: 11.5, color: Ruby.muted),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        Money.fmt(it.amountPaise),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: Ruby.ink),
                      ),
                    ],
                  ),
                ),
              ),
            const Divider(height: 20),
            Row(
              children: [
                const Text('TOTAL CREDIT',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Ruby.ruby)),
                const Spacer(),
                Text(Money.fmt(r.amountPaise),
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Ruby.ink)),
              ],
            ),
            if (r.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Note: ${r.note}',
                    style: const TextStyle(fontSize: 12.5, color: Ruby.muted)),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: RubyAppBar(
        title: 'Sales Return',
        subtitle: 'Customer ka wapas aaya maal',
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Ruby.ruby,
        foregroundColor: Colors.white,
        onPressed: _openForm,
        icon: const Icon(Icons.add),
        label: const Text('NEW RETURN',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Ruby.ruby))
          : _items.isEmpty
              ? const EmptyState(
                  icon: Icons.keyboard_return,
                  title: 'Koi sales return nahi hui',
                  subtitle:
                      'Jab koi party maal wapas bheje to NEW RETURN dabao - '
                      'poori detail ke saath amount uske account me jama '
                      '(credit) ho jayega.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final r = _items[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _openDetails(r),
                      child: Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Ruby.line),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: Ruby.greenLight,
                              child: const Icon(Icons.keyboard_return,
                                  size: 18, color: Ruby.green),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.customerName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14.5,
                                        color: Ruby.ink),
                                  ),
                                  Text(
                                    'Return #${r.returnNo}  |  ${Dt.fmtDate(Dt.dayStartOf(r.returnDate))}'
                                    '${r.note.isNotEmpty ? '  |  ${r.note}' : ''}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 11.5, color: Ruby.muted),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '- ${Money.fmt(r.amountPaise)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: Ruby.green),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

/// New sales return form: pick the customer, add item lines, save. The
/// ledger credit happens automatically (repo merges sales_returns into
/// the customer ledger).
class _SalesReturnFormSheet extends StatefulWidget {
  const _SalesReturnFormSheet();

  @override
  State<_SalesReturnFormSheet> createState() => _SalesReturnFormSheetState();
}

class _SalesReturnFormSheetState extends State<_SalesReturnFormSheet> {
  final TextEditingController _searchC = TextEditingController();
  final TextEditingController _nameC = TextEditingController();
  final TextEditingController _qtyC = TextEditingController();
  final TextEditingController _rateC = TextEditingController();
  final TextEditingController _noteC = TextEditingController();
  List<Map<String, Object?>> _customers = [];
  Customer? _customer;
  final List<CartLine> _lines = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _filterCustomers('');
  }

  @override
  void dispose() {
    _searchC.dispose();
    _nameC.dispose();
    _qtyC.dispose();
    _rateC.dispose();
    _noteC.dispose();
    super.dispose();
  }

  Future<void> _filterCustomers(String q) async {
    final rows = await Repo.instance.searchCustomers(q);
    if (!mounted) return;
    setState(() => _customers = rows);
  }

  int get _totalPaise => _lines.fold(0, (s, l) => s + l.amountPaise);

  Future<void> _pickCustomer(Map<String, Object?> row) async {
    final c = await Repo.instance.getCustomer(row['id'] as String);
    if (!mounted || c == null) return;
    setState(() => _customer = c);
  }

  void _addLine() {
    final name = _nameC.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'Product name likhiye');
      return;
    }
    final qty = double.tryParse(_qtyC.text.trim().replaceAll(',', '')) ?? 0;
    final rate = Money.parsePaise(_rateC.text);
    if (qty <= 0 || rate <= 0) {
      showSnack(context, 'Quantity aur rate likhiye');
      return;
    }
    setState(() {
      _lines.add(CartLine(name: name, qty: qty, ratePaise: rate));
      _nameC.clear();
      _qtyC.clear();
      _rateC.clear();
    });
  }

  Future<void> _save() async {
    if (_customer == null) {
      showSnack(context, 'Customer choose karo', error: true);
      return;
    }
    if (_lines.isEmpty) {
      showSnack(context, 'Kam se kam 1 item add karo');
      return;
    }
    setState(() => _saving = true);
    try {
      await Repo.instance.saveSalesReturn(
        customerId: _customer!.id,
        customerName: _customer!.name,
        lines: _lines,
        note: _noteC.text.trim(),
      );
      if (mounted) {
        showSnack(context,
            'Sales return saved - ${_customer!.name} ke account me jama ho gaya');
        Navigator.pop(context, true);
      }
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
            const Text('New Sales Return',
                style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: Ruby.ink)),
            const SizedBox(height: 12),
            if (_customer == null) ...[
              TextField(
                controller: _searchC,
                autofocus: true,
                onChanged: _filterCustomers,
                decoration: const InputDecoration(
                  hintText: 'Customer search karo...',
                  isDense: true,
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 8),
              ...[
                for (final r in _customers.take(5))
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.people_alt_outlined,
                        color: Ruby.ruby, size: 20),
                    title: Text(r['name'] as String? ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(r['city'] as String? ?? '',
                        style: const TextStyle(fontSize: 11.5)),
                    onTap: () => _pickCustomer(r),
                  ),
              ],
            ] else ...[
              InkWell(
                onTap: () => setState(() => _customer = null),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Ruby.rubyLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person, color: Ruby.ruby, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_customer!.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Ruby.ruby)),
                      ),
                      const Text('TAP TO CHANGE',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Ruby.faint)),
                    ],
                  ),
                ),
              ),
            ],
            if (_customer != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameC,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        hintText: 'Product name',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 58,
                    child: TextField(
                      controller: _qtyC,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        hintText: 'Qty',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 9),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 70,
                    child: TextField(
                      controller: _rateC,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        hintText: 'Rate',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 9),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _addLine,
                    icon: const Icon(Icons.add_circle,
                        color: Ruby.ruby, size: 26),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _lines.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Text('${i + 1}.',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Ruby.ruby)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(_lines[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: Ruby.ink)),
                      ),
                      Text(
                        '${Qty.fmt(_lines[i].qty)} x ${Money.fmt(_lines[i].ratePaise, withSymbol: false)}',
                        style: const TextStyle(
                            fontSize: 11, color: Ruby.muted),
                      ),
                      const SizedBox(width: 8),
                      Text(Money.fmt(_lines[i].amountPaise),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: Ruby.ink)),
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 15,
                          icon: const Icon(Icons.close, color: Ruby.faint),
                          onPressed: () =>
                              setState(() => _lines.removeAt(i)),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_lines.isNotEmpty)
                Row(
                  children: [
                    const Text('TOTAL CREDIT',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Ruby.ruby)),
                    const Spacer(),
                    Text(Money.fmt(_totalPaise),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: Ruby.ink)),
                  ],
                ),
              const SizedBox(height: 10),
              TextField(
                controller: _noteC,
                decoration: const InputDecoration(
                    hintText: 'Note (kya wapas aaya, kyun)'),
              ),
            ],
            const SizedBox(height: 14),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46)),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('SAVE RETURN (ACCOUNT ME JAMA)',
                      style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}
