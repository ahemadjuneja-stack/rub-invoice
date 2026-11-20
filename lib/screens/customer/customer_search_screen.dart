import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repo.dart';
import '../../services/bill_draft_service.dart';
import '../billing/billing_screen.dart';
import '../../widgets/widgets.dart';
import '../ledger/ledger_screen.dart';
import 'customer_form_screen.dart';

enum CustomerSearchMode { pickForBilling, browse }

/// Search customers by name / city / phone. Type "Rajkot" and every
/// Rajkot customer appears instantly; type a new name and you can add
/// the customer on the spot.
class CustomerSearchScreen extends StatefulWidget {
  final CustomerSearchMode mode;
  const CustomerSearchScreen({super.key, this.mode = CustomerSearchMode.pickForBilling});

  @override
  State<CustomerSearchScreen> createState() => _CustomerSearchScreenState();
}

class _CustomerSearchScreenState extends State<CustomerSearchScreen> {
  final _searchC = TextEditingController();
  List<Map<String, Object?>> _results = [];
  bool _searched = false;
  BillDraft? _draft;

  @override
  void initState() {
    super.initState();
    _filter();
    _loadDraft();
  }

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  Future<void> _loadDraft() async {
    final d = await BillDraftService.instance.load();
    if (!mounted) return;
    setState(() => _draft = (d != null && d.lines.isNotEmpty) ? d : null);
  }

  /// Opens the saved draft straight in the billing screen, exactly
  /// where the user left it.
  Future<void> _resumeDraft() async {
    final d = _draft;
    if (d == null) return;
    final cust = await Repo.instance.getCustomer(d.customerId);
    if (!mounted) return;
    if (cust == null) {
      await BillDraftService.instance.clear();
      await _loadDraft();
      if (mounted) showSnack(context, 'Draft removed - customer no longer exists');
      return;
    }
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => BillingScreen(customer: cust)),
    );
  }

  Future<void> _filter() async {
    final rows = await Repo.instance.searchCustomers(_searchC.text);
    if (!mounted) return;
    setState(() {
      _results = rows;
      _searched = true;
    });
  }

  int _balanceOf(Map<String, Object?> row) => (row['balance_paise'] ?? 0) as int;

  Future<void> _openCustomer(Map<String, Object?> row) async {
    final id = row['id'] as String;
    final name = row['name'] as String;
    if (widget.mode == CustomerSearchMode.pickForBilling) {
      final cust = await Repo.instance.getCustomer(id);
      if (!mounted || cust == null) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => BillingScreen(customer: cust)),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LedgerScreen(customerId: id, customerName: name)),
    );
  }

  Future<void> _addNew() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerFormScreen(prefillName: _searchC.text.trim()),
      ),
    );
    _filter();
  }

  @override
  Widget build(BuildContext context) {
    final isBilling = widget.mode == CustomerSearchMode.pickForBilling;
    return Scaffold(
      appBar: RubyAppBar(title: isBilling ? 'Select Customer' : 'Customers'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchC,
              autofocus: true,
              onChanged: (v) => _filter(),
              decoration: InputDecoration(
                hintText: 'Search name, city or phone (e.g. Rajkot)',
                prefixIcon: const Icon(Icons.search, color: Ruby.ruby),
                suffixIcon: _searchC.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18, color: Ruby.muted),
                        onPressed: () {
                          _searchC.clear();
                          _filter();
                        },
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _addNewTile(),
          ),
          if (isBilling && _draft != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: _draftTile(_draft!),
            ),
          Expanded(
            child: _results.isEmpty
                ? (_searched
                    ? EmptyState(
                        icon: Icons.person_search_outlined,
                        title: 'No customers found',
                        subtitle: 'Add a new customer with the red button above, then start billing.',
                      )
                    : const SizedBox.shrink())
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, i) {
                      final row = _results[i];
                      final balance = _balanceOf(row);
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Ruby.rubyLight,
                          child: Text(
                            ((row['name'] as String?)?.isNotEmpty == true)
                                ? (row['name'] as String)[0].toUpperCase()
                                : '?',
                            style: const TextStyle(color: Ruby.ruby, fontWeight: FontWeight.w800),
                          ),
                        ),
                        title: Text(
                          row['name'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: Ruby.ink),
                        ),
                        subtitle: Text(
                          [
                            row['shop_name'],
                            row['city'],
                            row['phone'],
                          ].where((e) => (e as String?)?.isNotEmpty == true).join('  •  '),
                          style: const TextStyle(fontSize: 12.5, color: Ruby.muted),
                        ),
                        trailing: _balanceChip(balance),
                        onTap: () => _openCustomer(row),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _addNewTile() {
    final q = _searchC.text.trim();
    return Material(
      color: Ruby.rubyLight,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _addNew,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.person_add_alt_1, color: Ruby.ruby, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  q.isEmpty
                      ? 'Add new customer'
                      : 'Add "$q" as new customer',
                  style: const TextStyle(
                    color: Ruby.ruby,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: Ruby.ruby),
            ],
          ),
        ),
      ),
    );
  }

  Widget _draftTile(BillDraft d) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _resumeDraft,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Ruby.ruby, width: 1.2),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.receipt_long, color: Ruby.ruby, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Resume unfinished bill',
                      style: TextStyle(
                          color: Ruby.ruby,
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${d.customerName}  •  ${Money.fmt(d.totalPaise)}  •  tap to continue',
                      style: const TextStyle(fontSize: 12, color: Ruby.muted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward, color: Ruby.ruby, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _balanceChip(int balancePaise) {
    if (balancePaise == 0) {
      return const Text('Settled', style: TextStyle(fontSize: 12, color: Ruby.muted));
    }
    final due = balancePaise > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: due ? Ruby.rubyLight : Ruby.greenLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        due ? 'Due ${Money.fmt(balancePaise)}' : 'Adv ${Money.fmt(-balancePaise)}',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: due ? Ruby.ruby : Ruby.green,
        ),
      ),
    );
  }
}
