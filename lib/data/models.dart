/// Plain data models. All rows carry:
///   - uuid text id (sync-safe, no autoincrement collisions across devices)
///   - updated_at  (epoch ms, used for last-write-wins sync)
///   - is_deleted  (tombstone, so deletes propagate to other devices)
///   - dirty       (local change not yet pushed to Firestore)
/// Amounts are ALWAYS integer paise.
library;

class Customer {
  final String id;
  final String name;
  final String city;
  final String phone;
  final int openingBalancePaise; // +ve = customer already owed this
  final int createdAt;
  final int updatedAt;
  final int isDeleted;
  final int dirty;

  Customer({
    required this.id,
    required this.name,
    this.city = '',
    this.phone = '',
    this.openingBalancePaise = 0,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = 0,
    this.dirty = 1,
  });

  factory Customer.fromMap(Map<String, Object?> m) => Customer(
        id: m['id'] as String,
        name: m['name'] as String,
        city: (m['city'] ?? '') as String,
        phone: (m['phone'] ?? '') as String,
        openingBalancePaise: (m['opening_balance_paise'] ?? 0) as int,
        createdAt: (m['created_at'] ?? 0) as int,
        updatedAt: (m['updated_at'] ?? 0) as int,
        isDeleted: (m['is_deleted'] ?? 0) as int,
        dirty: (m['dirty'] ?? 0) as int,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'city': city,
        'phone': phone,
        'opening_balance_paise': openingBalancePaise,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'is_deleted': isDeleted,
        'dirty': dirty,
      };

  /// Row without local-only columns (used for sync payload).
  Map<String, Object?> toSync() {
    final m = toMap()..remove('dirty');
    return m;
  }

  static Customer fromSync(Map<String, Object?> m) => Customer(
        id: m['id'] as String,
        name: m['name'] as String,
        city: (m['city'] ?? '') as String,
        phone: (m['phone'] ?? '') as String,
        openingBalancePaise: (m['opening_balance_paise'] ?? 0) as int,
        createdAt: (m['created_at'] ?? 0) as int,
        updatedAt: (m['updated_at'] ?? 0) as int,
        isDeleted: (m['is_deleted'] ?? 0) as int,
        dirty: 0,
      );

  Customer copyWith({String? name, String? city, String? phone, int? openingBalancePaise, int? updatedAt}) =>
      Customer(
        id: id,
        name: name ?? this.name,
        city: city ?? this.city,
        phone: phone ?? this.phone,
        openingBalancePaise: openingBalancePaise ?? this.openingBalancePaise,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        isDeleted: isDeleted,
        dirty: 1,
      );
}

class Product {
  final String id;
  final String name;
  final String unit;
  final double defaultQty;
  final int defaultPricePaise;
  final int trackStock; // 0/1
  final double stockQty;
  final double lowStock;
  final int createdAt;
  final int updatedAt;
  final int isDeleted;
  final int dirty;

  Product({
    required this.id,
    required this.name,
    this.unit = 'Pcs',
    this.defaultQty = 1,
    this.defaultPricePaise = 0,
    this.trackStock = 0,
    this.stockQty = 0,
    this.lowStock = 0,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = 0,
    this.dirty = 1,
  });

  factory Product.fromMap(Map<String, Object?> m) => Product(
        id: m['id'] as String,
        name: m['name'] as String,
        unit: (m['unit'] ?? 'Pcs') as String,
        defaultQty: ((m['default_qty'] ?? 1) as num).toDouble(),
        defaultPricePaise: (m['default_price_paise'] ?? 0) as int,
        trackStock: (m['track_stock'] ?? 0) as int,
        stockQty: ((m['stock_qty'] ?? 0) as num).toDouble(),
        lowStock: ((m['low_stock'] ?? 0) as num).toDouble(),
        createdAt: (m['created_at'] ?? 0) as int,
        updatedAt: (m['updated_at'] ?? 0) as int,
        isDeleted: (m['is_deleted'] ?? 0) as int,
        dirty: (m['dirty'] ?? 0) as int,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'unit': unit,
        'default_qty': defaultQty,
        'default_price_paise': defaultPricePaise,
        'track_stock': trackStock,
        'stock_qty': stockQty,
        'low_stock': lowStock,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'is_deleted': isDeleted,
        'dirty': dirty,
      };

  Map<String, Object?> toSync() => toMap()..remove('dirty');

  static Product fromSync(Map<String, Object?> m) => Product.fromMap({...m, 'dirty': 0});
}

class BillItem {
  final String id;
  final String billId;
  final String? productId;
  final String productName;
  final double qty;
  final int ratePaise;
  final int amountPaise;
  final int createdAt;

  BillItem({
    required this.id,
    required this.billId,
    this.productId,
    required this.productName,
    required this.qty,
    required this.ratePaise,
    required this.amountPaise,
    required this.createdAt,
  });

  factory BillItem.fromMap(Map<String, Object?> m) => BillItem(
        id: m['id'] as String,
        billId: m['bill_id'] as String,
        productId: m['product_id'] as String?,
        productName: m['product_name'] as String,
        qty: ((m['qty'] ?? 0) as num).toDouble(),
        ratePaise: (m['rate_paise'] ?? 0) as int,
        amountPaise: (m['amount_paise'] ?? 0) as int,
        createdAt: (m['created_at'] ?? 0) as int,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'bill_id': billId,
        'product_id': productId,
        'product_name': productName,
        'qty': qty,
        'rate_paise': ratePaise,
        'amount_paise': amountPaise,
        'created_at': createdAt,
      };

  Map<String, Object?> toSync() => toMap();
}

class Bill {
  final String id;
  final int billNo;
  final String customerId;
  final String customerName; // snapshot
  final int billDate; // epoch ms
  final String billDay; // "2026-11-19" local
  final int subtotalPaise;
  final int discountPaise;
  final int totalPaise;
  final String note;
  final int createdAt;
  final int updatedAt;
  final int isDeleted;
  final int dirty;

  Bill({
    required this.id,
    required this.billNo,
    required this.customerId,
    required this.customerName,
    required this.billDate,
    required this.billDay,
    required this.subtotalPaise,
    this.discountPaise = 0,
    required this.totalPaise,
    this.note = '',
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = 0,
    this.dirty = 1,
  });

  factory Bill.fromMap(Map<String, Object?> m) => Bill(
        id: m['id'] as String,
        billNo: (m['bill_no'] ?? 0) as int,
        customerId: m['customer_id'] as String,
        customerName: (m['customer_name'] ?? '') as String,
        billDate: (m['bill_date'] ?? 0) as int,
        billDay: (m['bill_day'] ?? '') as String,
        subtotalPaise: (m['subtotal_paise'] ?? 0) as int,
        discountPaise: (m['discount_paise'] ?? 0) as int,
        totalPaise: (m['total_paise'] ?? 0) as int,
        note: (m['note'] ?? '') as String,
        createdAt: (m['created_at'] ?? 0) as int,
        updatedAt: (m['updated_at'] ?? 0) as int,
        isDeleted: (m['is_deleted'] ?? 0) as int,
        dirty: (m['dirty'] ?? 0) as int,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'bill_no': billNo,
        'customer_id': customerId,
        'customer_name': customerName,
        'bill_date': billDate,
        'bill_day': billDay,
        'subtotal_paise': subtotalPaise,
        'discount_paise': discountPaise,
        'total_paise': totalPaise,
        'note': note,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'is_deleted': isDeleted,
        'dirty': dirty,
      };

  Map<String, Object?> toSync() => toMap()..remove('dirty');

  static Bill fromSync(Map<String, Object?> m) => Bill.fromMap({...m, 'dirty': 0});
}

class Payment {
  final String id;
  final String customerId;
  final String? billId;
  final int amountPaise;
  final int payDate; // epoch ms
  final String payDay; // local day key
  final String mode; // cash | upi | bank | other
  final String note;
  final int createdAt;
  final int updatedAt;
  final int isDeleted;
  final int dirty;

  Payment({
    required this.id,
    required this.customerId,
    this.billId,
    required this.amountPaise,
    required this.payDate,
    required this.payDay,
    this.mode = 'cash',
    this.note = '',
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = 0,
    this.dirty = 1,
  });

  factory Payment.fromMap(Map<String, Object?> m) => Payment(
        id: m['id'] as String,
        customerId: m['customer_id'] as String,
        billId: m['bill_id'] as String?,
        amountPaise: (m['amount_paise'] ?? 0) as int,
        payDate: (m['pay_date'] ?? 0) as int,
        payDay: (m['pay_day'] ?? '') as String,
        mode: (m['mode'] ?? 'cash') as String,
        note: (m['note'] ?? '') as String,
        createdAt: (m['created_at'] ?? 0) as int,
        updatedAt: (m['updated_at'] ?? 0) as int,
        isDeleted: (m['is_deleted'] ?? 0) as int,
        dirty: (m['dirty'] ?? 0) as int,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'customer_id': customerId,
        'bill_id': billId,
        'amount_paise': amountPaise,
        'pay_date': payDate,
        'pay_day': payDay,
        'mode': mode,
        'note': note,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'is_deleted': isDeleted,
        'dirty': dirty,
      };

  Map<String, Object?> toSync() => toMap()..remove('dirty');

  static Payment fromSync(Map<String, Object?> m) => Payment.fromMap({...m, 'dirty': 0});
}

/// One merged row in the customer ledger (bills + payments chronological).
class LedgerEntry {
  final String kind; // 'bill' | 'payment' | 'opening'
  final String refId;
  final String title;
  final DateTime date;
  final int debitPaise; // bills increase what customer owes
  final int creditPaise; // payments reduce it
  final int runningBalancePaise;

  LedgerEntry({
    required this.kind,
    required this.refId,
    required this.title,
    required this.date,
    required this.debitPaise,
    required this.creditPaise,
    required this.runningBalancePaise,
  });
}

/// A row being built in the billing screen cart.
class CartLine {
  final String? productId;
  final String name;
  double qty;
  int ratePaise;

  CartLine({this.productId, required this.name, required this.qty, required this.ratePaise});

  int get amountPaise => (qty * ratePaise).round();
}
