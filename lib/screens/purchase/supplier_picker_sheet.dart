import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/repo.dart';
import 'suppliers_screen.dart';

/// THE purchase-party picker (used by the purchase form, the purchase
/// return form and the purchase menu).
///
/// Why this exists: the old picker only listed already-saved parties -
/// a first-time user saw an empty sheet, nothing could be selected and
/// the only way forward was hunting for the small "new party" button at
/// the bottom. This picker always offers every escape route:
///   * search (name / city / shop) and tap to choose instantly
///   * "Add `what you typed` as new party" - one tap opens the party
///     form with the name already filled; after saving, the party is
///     chosen automatically
///   * an always-visible ADD NEW PARTY button at the top
class SupplierPickerSheet extends StatefulWidget {
  final String title;

  /// When set, this party is chosen without showing anything (used by
  /// the inline add flow so the user never loses their place).
  const SupplierPickerSheet({super.key, required this.title});

  @override
  State<SupplierPickerSheet> createState() => _SupplierPickerSheetState();
}

class _SupplierPickerSheetState extends State<SupplierPickerSheet> {
  final _searchC = TextEditingController();
  List<Map<String, Object?>> _rows = [];
  bool _loading = true;

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
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _pick(Map<String, Object?> row) async {
    final sup = await Repo.instance.getSupplier(row['id'] as String);
    if (!mounted || sup == null) return;
    Navigator.pop(context, sup);
  }

  /// Opens the party form (name prefilled with what the user typed) and
  /// returns the freshly saved party as the picked result.
  Future<void> _addNew() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SupplierFormSheet(initialName: _searchC.text.trim()),
    );
    if (saved != true) return;
    final q = _searchC.text.trim().toLowerCase();
    final rows = await Repo.instance.searchSuppliers(_searchC.text.trim());
    Map<String, Object?>? exact;
    for (final r in rows) {
      if ((r['name'] as String? ?? '').toLowerCase() == q) {
        exact = r;
        break;
      }
    }
    exact ??= rows.isNotEmpty ? rows.first : null;
    if (exact != null) {
      final sup = await Repo.instance.getSupplier(exact['id'] as String);
      if (!mounted) return;
      if (sup != null) {
        Navigator.pop(context, sup);
        return;
      }
    }
    if (mounted) _filter();
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchC.text.trim();
    final hasExact = _rows
        .any((r) => (r['name'] as String? ?? '').toLowerCase() == q.toLowerCase());
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
            Text(widget.title,
                style: const TextStyle(
                    fontSize: 16.5, fontWeight: FontWeight.w800, color: Ruby.ink)),
            const SizedBox(height: 12),
            TextField(
              controller: _searchC,
              autofocus: true,
              onChanged: (_) => _filter(),
              decoration: const InputDecoration(
                hintText: 'Search party name, city, shop...',
                isDense: true,
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _addNew,
              icon: const Icon(Icons.person_add_alt_1, size: 18),
              label: const Text('ADD NEW PARTY',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Ruby.ruby)),
              )
            else if (_rows.isEmpty && q.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18, horizontal: 8),
                child: Text(
                  'No purchase party saved yet. Tap ADD NEW PARTY above - '
                  'enter the party name, city, phone and address; after that '
                  'every purchase bill for this party is one tap away.',
                  style: TextStyle(fontSize: 12.5, height: 1.5, color: Ruby.muted),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _rows.length + (q.isNotEmpty && !hasExact ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == _rows.length) {
                      // Inline add: the typed name is not a saved party
                      // yet - offer it directly (the "choose nahi hoti"
                      // fix: the next step is always visible).
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.person_add_alt_1,
                            color: Ruby.ruby, size: 20),
                        title: Text(
                          'Add "$q" as new party',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, color: Ruby.ruby),
                        ),
                        onTap: _addNew,
                      );
                    }
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
          ],
        ),
      ),
    );
  }
}
