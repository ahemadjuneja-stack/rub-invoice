import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../data/repo.dart';
import '../../services/sync_service.dart';
import '../../widgets/widgets.dart';

/// Inventory: save products once (name + default qty + price + optional
/// stock). During billing, typing the name auto-fills everything and you
/// can still edit the values on the fly.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _searchC = TextEditingController();
  List<Product> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final list = await Repo.instance.searchProducts(_searchC.text);
    if (!mounted) return;
    setState(() {
      _products = list;
      _loading = false;
    });
  }

  Future<void> _openForm({Product? product}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductFormScreen(product: product)),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inventory')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchC,
              onChanged: (_) => _reload(),
              decoration: InputDecoration(
                hintText: 'Search product',
                prefixIcon: const Icon(Icons.search, color: Ruby.ruby),
                suffixIcon: _searchC.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18, color: Ruby.muted),
                        onPressed: () {
                          _searchC.clear();
                          _reload();
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Ruby.ruby))
                : _products.isEmpty
                    ? const EmptyState(
                        icon: Icons.inventory_2_outlined,
                        title: 'No products yet',
                        subtitle:
                            'Add products here first (e.g. Socks Black, qty 1, price 50). '
                            'Then in billing, typing "S" will suggest them instantly.',
                      )
                    : ListView.builder(
                        itemCount: _products.length,
                        itemBuilder: (context, i) {
                          final p = _products[i];
                          return ListTile(
                            title: Text(
                              p.name,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: Ruby.ink),
                            ),
                            subtitle: Text(
                              '${Money.fmt(p.defaultPricePaise)} / ${p.unit}  •  default qty ${_qty(p.defaultQty)}',
                              style: const TextStyle(fontSize: 12.5, color: Ruby.muted),
                            ),
                            trailing: p.trackStock == 1 ? _stockChip(p) : null,
                            onTap: () => _openForm(product: p),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'inventory_fab',
        onPressed: () => _openForm(),
        child: const Icon(Icons.add, size: 30),
      ),
    );
  }

  Widget _stockChip(Product p) {
    final low = p.lowStock > 0 && p.stockQty <= p.lowStock;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: low ? Ruby.rubyLight : Ruby.fieldBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'Stock ${_qty(p.stockQty)}',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: low ? Ruby.ruby : Ruby.muted,
        ),
      ),
    );
  }

  String _qty(double q) {
    if (q == q.roundToDouble()) return q.round().toString();
    return q.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
}

// ---------------- add / edit product ----------------

class ProductFormScreen extends StatefulWidget {
  final Product? product;
  const ProductFormScreen({super.key, this.product});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _nameC = TextEditingController();
  final _qtyC = TextEditingController(text: '1');
  final _priceC = TextEditingController();
  final _stockC = TextEditingController();
  final _lowC = TextEditingController();

  String _unit = 'Pcs';
  bool _trackStock = false;
  bool _saving = false;

  static const _units = ['Pcs', 'Pair', 'Dozen', 'Box', 'Mtr', 'Kg', 'Other'];

  bool get _isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    if (p != null) {
      _nameC.text = p.name;
      _unit = _units.contains(p.unit) ? p.unit : 'Other';
      _qtyC.text = _qtyText(p.defaultQty);
      _priceC.text = Money.fmtRupeesInput(p.defaultPricePaise);
      _trackStock = p.trackStock == 1;
      _stockC.text = _qtyText(p.stockQty);
      _lowC.text = p.lowStock == 0 ? '' : _qtyText(p.lowStock);
    }
  }

  @override
  void dispose() {
    _nameC.dispose();
    _qtyC.dispose();
    _priceC.dispose();
    _stockC.dispose();
    _lowC.dispose();
    super.dispose();
  }

  String _qtyText(double q) {
    if (q == q.roundToDouble()) return q.round().toString();
    return q.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  Future<void> _save() async {
    final name = _nameC.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'Product name is required', error: true);
      return;
    }
    final qty = double.tryParse(_qtyC.text.trim().replaceAll(',', '')) ?? 1;
    if (qty <= 0) {
      showSnack(context, 'Default quantity must be more than 0', error: true);
      return;
    }
    final price = Money.parsePaise(_priceC.text);

    // duplicate name check
    final existing = await Repo.instance.productByName(name);
    if (!mounted) return;
    if (existing != null && existing.id != widget.product?.id) {
      showSnack(context, 'A product with this name already exists', error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        final p = widget.product!;
        await Repo.instance.upsertProduct(Product(
          id: p.id,
          name: name,
          unit: _unit,
          defaultQty: qty,
          defaultPricePaise: price,
          trackStock: _trackStock ? 1 : 0,
          stockQty: _trackStock ? (double.tryParse(_stockC.text) ?? 0) : p.stockQty,
          lowStock: _trackStock ? (double.tryParse(_lowC.text) ?? 0) : p.lowStock,
          createdAt: p.createdAt,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ));
      } else {
        await Repo.instance.newProduct(
          name: name,
          unit: _unit,
          defaultQty: qty,
          defaultPricePaise: price,
          trackStock: _trackStock ? 1 : 0,
          stockQty: _trackStock ? (double.tryParse(_stockC.text) ?? 0) : 0,
          lowStock: _trackStock ? (double.tryParse(_lowC.text) ?? 0) : 0,
        );
      }
      SyncService.instance.syncSoon();
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Delete product?',
      message: '"${widget.product!.name}" will be hidden from suggestions. Old bills keep their record.',
      ok: 'Delete',
      dangerous: true,
    );
    if (!ok) return;
    await Repo.instance.deleteProduct(widget.product!.id);
    SyncService.instance.syncSoon();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Product' : 'New Product'),
        actions: [
          if (_isEdit)
            IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameC,
            textCapitalization: TextCapitalization.words,
            autofocus: !_isEdit,
            decoration: const InputDecoration(hintText: 'Product name (e.g. Socks Black) *', isDense: false),
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  value: _unit,
                  decoration: const InputDecoration(hintText: 'Unit', isDense: false),
                  items: [
                    for (final u in _units) DropdownMenuItem(value: u, child: Text(u, style: const TextStyle(fontSize: 14))),
                  ],
                  onChanged: (v) => setState(() => _unit = v ?? 'Pcs'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _qtyC,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
                  decoration: const InputDecoration(hintText: 'Default qty *', isDense: false),
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _priceC,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
            decoration: const InputDecoration(hintText: 'Default price (₹) *', isDense: false),
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeColor: Ruby.ruby,
            title: const Text('Track stock', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
            subtitle: const Text('Stock reduces automatically with every bill', style: TextStyle(fontSize: 12.5)),
            value: _trackStock,
            onChanged: (v) => setState(() => _trackStock = v),
          ),
          if (_trackStock) ...[
            TextField(
              controller: _stockC,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
              decoration: const InputDecoration(hintText: 'Current stock', isDense: false),
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _lowC,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
              decoration: const InputDecoration(
                hintText: 'Low stock alert at (optional)',
                isDense: false,
                helperText: 'Shows a red badge in inventory when stock reaches this level',
              ),
              style: const TextStyle(fontSize: 15),
            ),
          ],
          const SizedBox(height: 26),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('SAVE PRODUCT'),
          ),
        ],
      ),
    );
  }
}
