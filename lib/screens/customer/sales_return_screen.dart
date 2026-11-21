import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repo.dart';
import '../../models/models.dart';
import '../../services/return_draft_service.dart';
import '../../services/sync_service.dart';
import '../../widgets/widgets.dart';
import 'sales_return_entry_screen.dart';

/// SALES RETURN list: every return the shop received, party-wise. The
/// amount of each return is already credited (minus) in that customer's
/// account - the ledger merges bills, payments and returns into ONE net
/// figure, so the hisab always matches.
///
/// NEW RETURN opens the billing-style entry screen: entry boxes on top,
/// Enter walks ahead, add as many products as needed. An unfinished
/// return survives back press / phone call as a draft and can be
/// resumed with one tap from the banner below.
class SalesReturnScreen extends StatefulWidget {
  const SalesReturnScreen({super.key});

  @override
  State<SalesReturnScreen> createState() => _SalesReturnScreenState();
}

class _SalesReturnScreenState extends State<SalesReturnScreen> {
  List<SalesReturn> _items = [];
  ReturnDraft? _draft;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await Repo.instance.salesReturns();
    final d = await ReturnDraftService.instance.load();
    if (!mounted) return;
    setState(() {
      _items = list;
      _draft = (d != null && d.lines.isNotEmpty) ? d : null;
      _loading = false;
    });
  }

  /// Pick a customer, then open the billing-style entry screen.
  Future<void> _newReturn() async {
    final Customer? c = await showModalBottomSheet<Customer>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _CustomerPickerSheet(),
    );
    if (c == null || !mounted) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => SalesReturnEntryScreen(customer: c)),
    );
    if (saved == true) {
      SyncService.instance.syncSoon();
    }
    _reload();
  }

  Future<void> _resumeDraft() async {
    final d = _draft;
    if (d == null) return;
    final c = await Repo.instance.getCustomer(d.customerId);
    if (!mounted) return;
    if (c == null) {
      await ReturnDraftService.instance.clear();
      _reload();
      return;
    }
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => SalesReturnEntryScreen(customer: c)),
    );
    if (saved == true) {
      SyncService.instance.syncSoon();
    }
    _reload();
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
                          'removed and the account balance will go back up.',
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
      appBar: const RubyAppBar(
        title: 'Sales Return',
        subtitle: 'Goods returned by customers - credited to their account',
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Ruby.ruby,
        foregroundColor: Colors.white,
        onPressed: _newReturn,
        icon: const Icon(Icons.add),
        label: const Text('NEW RETURN',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Ruby.ruby))
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
              children: [
                if (_draft != null) ...[
                  _draftBanner(),
                  const SizedBox(height: 10),
                ],
                if (_items.isEmpty && _draft == null)
                  const EmptyState(
                    icon: Icons.keyboard_return,
                    title: 'No sales returns yet',
                    subtitle:
                        'When a party returns goods, tap NEW RETURN. Every item '
                        'goes in with its qty and rate, and the amount is '
                        'credited (minus) in that party\'s account with full '
                        'details.',
                  )
                else
                  for (final r in _items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
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
                      ),
                    ),
              ],
            ),
    );
  }

  Widget _draftBanner() {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _resumeDraft,
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Ruby.rubyLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Ruby.ruby.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.replay_outlined, color: Ruby.ruby, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Resume unfinished return',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          color: Ruby.ruby)),
                  Text(
                    '${_draft!.customerName}  |  ${_draft!.lines.length} items  |  ${Money.fmt(_draft!.totalPaise)}',
                    style: const TextStyle(fontSize: 11.5, color: Ruby.muted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: Ruby.ruby),
          ],
        ),
      ),
    );
  }
}

/// Search + pick the customer whose goods came back (same flow as the
/// billing screen: party first, bill after).
class _CustomerPickerSheet extends StatefulWidget {
  const _CustomerPickerSheet();

  @override
  State<_CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<_CustomerPickerSheet> {
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
    final rows = await Repo.instance.searchCustomers(_searchC.text);
    if (!mounted) return;
    setState(() => _rows = rows);
  }

  Future<void> _pick(Map<String, Object?> row) async {
    final c = await Repo.instance.getCustomer(row['id'] as String);
    if (!mounted || c == null) return;
    Navigator.pop(context, c);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Select customer',
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
                hintText: 'Search customer name, city...',
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
                    leading: const Icon(Icons.people_alt_outlined,
                        color: Ruby.ruby, size: 20),
                    title: Text(r['name'] as String? ?? '',
                        style:
                            const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(r['city'] as String? ?? '',
                        style: const TextStyle(fontSize: 11.5)),
                    onTap: () => _pick(r),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
