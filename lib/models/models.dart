/// Plain data models. All rows carry:
///   - uuid text id (sync-safe, no autoincrement collisions across devices)
///   - updated_at  (epoch ms, used for last-write-wins sync)
///   - is_deleted  (tombstone, so deletes propagate to other devices)
///   - dirty       (local change not yet pushed to Firestore)
/// Amounts are ALWAYS integer paise.
library;

import '../core/formatters.dart';

class Customer {
  final String id;
  final String name;
  final String shopName;
  final String city;
  final String phone;
  final String address;
  final int openingBalancePaise; // +ve = customer already owed this
  final int createdAt;
  final int updatedAt;
  final int isDeleted;
  final int dirty;

  Customer({
    required this.id,
    required this.name,
    this.shopName = '',
    this.city = '',
    this.phone = '',
    this.address = '',
    this.openingBalancePaise = 0,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = 0,
    this.dirty = 1,
  });

  factory Customer.fromMap(Map<String, Object?> m) => Customer(
        id: m['id'] as String,
        name: m['name'] as String,
        shopName: (m['shop_name'] ?? '') as String,
        city: (m['city'] ?? '') as String,
        phone: (m['phone'] ?? '') as String,
        address: (m['address'] ?? '') as String,
        openingBalancePaise: (m['opening_balance_paise'] ?? 0) as int,
        createdAt: (m['created_at'] ?? 0) as int,
        updatedAt: (m['updated_at'] ?? 0) as int,
        isDeleted: (m['is_deleted'] ?? 0) as int,
        dirty: (m['dirty'] ?? 0) as int,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'shop_name': shopName,
        'city': city,
        'phone': phone,
        'address': address,
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
        shopName: (m['shop_name'] ?? '') as String,
        city: (m['city'] ?? '') as String,
        phone: (m['phone'] ?? '') as String,
        address: (m['address'] ?? '') as String,
        openingBalancePaise: (m['opening_balance_paise'] ?? 0) as int,
        createdAt: (m['created_at'] ?? 0) as int,
        updatedAt: (m['updated_at'] ?? 0) as int,
        isDeleted: (m['is_deleted'] ?? 0) as int,
        dirty: 0,
      );

  Customer copyWith({String? name, String? shopName, String? city, String? phone, String? address, int? openingBalancePaise, int? updatedAt}) =>
      Customer(
        id: id,
        name: name ?? this.name,
        shopName: shopName ?? this.shopName,
        city: city ?? this.city,
        phone: phone ?? this.phone,
        address: address ?? this.address,
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
  final String proofPath; // optional payment screenshot (UPI etc.) kept on this phone
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
    this.proofPath = '',
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
        proofPath: (m['proof_path'] ?? '') as String,
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
        'proof_path': proofPath,
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
  final String proofPath; // payment screenshot on this phone (payments only)

  LedgerEntry({
    required this.kind,
    required this.refId,
    required this.title,
    required this.date,
    required this.debitPaise,
    required this.creditPaise,
    required this.runningBalancePaise,
    this.proofPath = '',
  });
}

/// A row being built in the billing screen cart.
class CartLine {
  final String? productId;
  final String name;
  double qty;
  int ratePaise;

  CartLine({this.productId, required this.name, required this.qty, required this.ratePaise});

  /// Exact amount via the decimal package: no floating-point product,
  /// round half-up to the nearest paise. 0% rounding error by design.
  int get amountPaise => Money.lineAmountPaise(qty, ratePaise);
}

/// One purchase invoice (maal kharida ka bill): what came in, from which
/// supplier, for how much - plus an optional photo of the paper bill
/// (clicked with the camera or picked from the gallery) kept on the
/// device next to the amount, Miracle-style.
class Purchase {
  final String id;
  final int purchaseNo; // serial, like bills
  final String supplierId; // link to the suppliers table (v0.3.0)
  final String supplierName;
  final String supplierPhone;
  final String partyBillNo; // the supplier's own paper bill number
  final int subtotalPaise; // sum of item amounts (taxable value)
  final int gstTotalPaise; // sum of gst per item
  final int parcelPaise; // parcel / freight / transport charges
  final int amountPaise; // grand total = subtotal + gst + parcel
  final String note; // free note
  final String photoPath; // local absolute path, '' when there is none
  final int purchaseDate; // epoch ms (the chosen bill date)
  final String purchaseDay; // "2026-11-19" local day key
  final int createdAt;
  final int updatedAt;
  final int isDeleted;
  final int dirty;

  Purchase({
    required this.id,
    required this.purchaseNo,
    this.supplierId = '',
    required this.supplierName,
    this.supplierPhone = '',
    this.partyBillNo = '',
    this.subtotalPaise = 0,
    this.gstTotalPaise = 0,
    this.parcelPaise = 0,
    required this.amountPaise,
    this.note = '',
    this.photoPath = '',
    required this.purchaseDate,
    required this.purchaseDay,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = 0,
    this.dirty = 1,
  });

  factory Purchase.fromMap(Map<String, Object?> m) => Purchase(
        id: m['id'] as String,
        purchaseNo: (m['purchase_no'] ?? 0) as int,
        supplierId: (m['supplier_id'] ?? '') as String,
        supplierName: (m['supplier_name'] ?? '') as String,
        supplierPhone: (m['supplier_phone'] ?? '') as String,
        partyBillNo: (m['party_bill_no'] ?? '') as String,
        subtotalPaise: (m['subtotal_paise'] ?? 0) as int,
        gstTotalPaise: (m['gst_total_paise'] ?? 0) as int,
        parcelPaise: (m['parcel_paise'] ?? 0) as int,
        amountPaise: (m['amount_paise'] ?? 0) as int,
        note: (m['note'] ?? '') as String,
        photoPath: (m['photo_path'] ?? '') as String,
        purchaseDate: (m['purchase_date'] ?? 0) as int,
        purchaseDay: (m['purchase_day'] ?? '') as String,
        createdAt: (m['created_at'] ?? 0) as int,
        updatedAt: (m['updated_at'] ?? 0) as int,
        isDeleted: (m['is_deleted'] ?? 0) as int,
        dirty: (m['dirty'] ?? 0) as int,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'purchase_no': purchaseNo,
        'supplier_id': supplierId,
        'supplier_name': supplierName,
        'supplier_phone': supplierPhone,
        'party_bill_no': partyBillNo,
        'subtotal_paise': subtotalPaise,
        'gst_total_paise': gstTotalPaise,
        'parcel_paise': parcelPaise,
        'amount_paise': amountPaise,
        'note': note,
        'photo_path': photoPath,
        'purchase_date': purchaseDate,
        'purchase_day': purchaseDay,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'is_deleted': isDeleted,
        'dirty': dirty,
      };

  Map<String, Object?> toSync() => toMap()..remove('dirty');

  static Purchase fromSync(Map<String, Object?> m) => Purchase.fromMap({...m, 'dirty': 0});
}

/// Delivery (transport) details of one saved bill: how the goods went to
/// the customer, the billty (lorry receipt) photo - kept 45 days, then
/// auto-deleted - and a free-text transport note. One row per bill.
class BillDispatch {
  final String id;
  final String billId;
  final String mode; // '' | transport | inhand | courier | pending
  final String billtyPath; // local billty photo, deletes itself after 45 days
  final int billtyAt; // epoch ms the photo was captured (retention clock)
  final String note;
  final int createdAt;
  final int updatedAt;
  final int isDeleted;
  final int dirty;

  BillDispatch({
    required this.id,
    required this.billId,
    this.mode = '',
    this.billtyPath = '',
    this.billtyAt = 0,
    this.note = '',
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = 0,
    this.dirty = 1,
  });

  static const allModes = ['transport', 'inhand', 'courier', 'pending'];

  factory BillDispatch.fromMap(Map<String, Object?> m) => BillDispatch(
        id: m['id'] as String,
        billId: m['bill_id'] as String,
        mode: (m['mode'] ?? '') as String,
        billtyPath: (m['billty_path'] ?? '') as String,
        billtyAt: (m['billty_at'] ?? 0) as int,
        note: (m['note'] ?? '') as String,
        createdAt: (m['created_at'] ?? 0) as int,
        updatedAt: (m['updated_at'] ?? 0) as int,
        isDeleted: (m['is_deleted'] ?? 0) as int,
        dirty: (m['dirty'] ?? 0) as int,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'bill_id': billId,
        'mode': mode,
        'billty_path': billtyPath,
        'billty_at': billtyAt,
        'note': note,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'is_deleted': isDeleted,
        'dirty': dirty,
      };

  Map<String, Object?> toSync() => toMap()..remove('dirty');

  static BillDispatch fromSync(Map<String, Object?> m) => BillDispatch.fromMap({...m, 'dirty': 0});

  /// Short label shown wherever the bill opens.
  String get modeLabel {
    if (mode == 'transport') return 'Transport';
    if (mode == 'inhand') return 'In Hand';
    if (mode == 'courier') return 'Courier';
    if (mode == 'pending') return 'Transport Pending';
    return 'Not set';
  }
}

// =====================================================================
// v0.3.0 PURCHASE MODULE - full billing-style purchase system
// =====================================================================

/// A purchase party (supplier) - "Surat Shardha Cosmetic" etc. Mirror of
/// Customer: same sync-ready row shape, its own ledger.
class Supplier {
  final String id;
  final String name;
  final String shopName;
  final String city;
  final String phone;
  final String address;
  final int openingBalancePaise; // +ve = we already owed this supplier
  final int createdAt;
  final int updatedAt;
  final int isDeleted;
  final int dirty;

  Supplier({
    required this.id,
    required this.name,
    this.shopName = '',
    this.city = '',
    this.phone = '',
    this.address = '',
    this.openingBalancePaise = 0,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = 0,
    this.dirty = 1,
  });

  factory Supplier.fromMap(Map<String, Object?> m) => Supplier(
        id: m['id'] as String,
        name: m['name'] as String,
        shopName: (m['shop_name'] ?? '') as String,
        city: (m['city'] ?? '') as String,
        phone: (m['phone'] ?? '') as String,
        address: (m['address'] ?? '') as String,
        openingBalancePaise: (m['opening_balance_paise'] ?? 0) as int,
        createdAt: (m['created_at'] ?? 0) as int,
        updatedAt: (m['updated_at'] ?? 0) as int,
        isDeleted: (m['is_deleted'] ?? 0) as int,
        dirty: (m['dirty'] ?? 0) as int,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'shop_name': shopName,
        'city': city,
        'phone': phone,
        'address': address,
        'opening_balance_paise': openingBalancePaise,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'is_deleted': isDeleted,
        'dirty': dirty,
      };

  Map<String, Object?> toSync() => toMap()..remove('dirty');

  static Supplier fromSync(Map<String, Object?> m) =>
      Supplier.fromMap({...m, 'dirty': 0});
}

/// One line of a purchase bill: what came in, how much of it, at which
/// rate, and how much GST applies to THIS product.
class PurchaseItem {
  final String id;
  final String purchaseId;
  final String? productId;
  final String productName;
  final double qty;
  final int ratePaise;
  final double gstPercent; // per-product GST, e.g. 18
  final int amountPaise; // qty * rate (gst NOT compounded into amount)
  final int createdAt;
  final int updatedAt;
  final int isDeleted;
  final int dirty;

  PurchaseItem({
    required this.id,
    required this.purchaseId,
    this.productId,
    required this.productName,
    required this.qty,
    required this.ratePaise,
    this.gstPercent = 0,
    required this.amountPaise,
    required this.createdAt,
    this.updatedAt = 0,
    this.isDeleted = 0,
    this.dirty = 1,
  });

  factory PurchaseItem.fromMap(Map<String, Object?> m) => PurchaseItem(
        id: m['id'] as String,
        purchaseId: m['purchase_id'] as String,
        productId: m['product_id'] as String?,
        productName: m['product_name'] as String,
        qty: ((m['qty'] ?? 0) as num).toDouble(),
        ratePaise: (m['rate_paise'] ?? 0) as int,
        gstPercent: ((m['gst_percent'] ?? 0) as num).toDouble(),
        amountPaise: (m['amount_paise'] ?? 0) as int,
        createdAt: (m['created_at'] ?? 0) as int,
        updatedAt: (m['updated_at'] ?? 0) as int,
        isDeleted: (m['is_deleted'] ?? 0) as int,
        dirty: (m['dirty'] ?? 0) as int,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'purchase_id': purchaseId,
        'product_id': productId,
        'product_name': productName,
        'qty': qty,
        'rate_paise': ratePaise,
        'gst_percent': gstPercent,
        'amount_paise': amountPaise,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'is_deleted': isDeleted,
        'dirty': dirty,
      };

  Map<String, Object?> toSync() => toMap()..remove('dirty');

  /// GST paise for this line: amount * gst% / 100, half-up to paise.
  int get gstPaise => ((amountPaise * gstPercent) / 100).round();
}

/// A line being built in the purchase form (mirrors CartLine).
class PurchaseCartLine {
  final String? productId;
  final String name;
  double qty;
  int ratePaise;
  double gstPercent;

  PurchaseCartLine({
    this.productId,
    required this.name,
    required this.qty,
    required this.ratePaise,
    this.gstPercent = 0,
  });

  int get amountPaise => Money.lineAmountPaise(qty, ratePaise);
  int get gstPaise => ((amountPaise * gstPercent) / 100).round();
}

/// Purchase RETURN: goods sent back to a supplier. Reduces what we owe
/// the supplier (credit in the supplier ledger).
class PurchaseReturn {
  final String id;
  final int returnNo;
  final String supplierId;
  final String supplierName; // snapshot
  final int amountPaise; // grand total of returned goods (ex GST)
  final int gstTotalPaise;
  final String note;
  final int returnDate;
  final String returnDay;
  final int createdAt;
  final int updatedAt;
  final int isDeleted;
  final int dirty;

  PurchaseReturn({
    required this.id,
    required this.returnNo,
    this.supplierId = '',
    required this.supplierName,
    required this.amountPaise,
    this.gstTotalPaise = 0,
    this.note = '',
    required this.returnDate,
    required this.returnDay,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = 0,
    this.dirty = 1,
  });

  factory PurchaseReturn.fromMap(Map<String, Object?> m) => PurchaseReturn(
        id: m['id'] as String,
        returnNo: (m['return_no'] ?? 0) as int,
        supplierId: (m['supplier_id'] ?? '') as String,
        supplierName: (m['supplier_name'] ?? '') as String,
        amountPaise: (m['amount_paise'] ?? 0) as int,
        gstTotalPaise: (m['gst_total_paise'] ?? 0) as int,
        note: (m['note'] ?? '') as String,
        returnDate: (m['return_date'] ?? 0) as int,
        returnDay: (m['return_day'] ?? '') as String,
        createdAt: (m['created_at'] ?? 0) as int,
        updatedAt: (m['updated_at'] ?? 0) as int,
        isDeleted: (m['is_deleted'] ?? 0) as int,
        dirty: (m['dirty'] ?? 0) as int,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'return_no': returnNo,
        'supplier_id': supplierId,
        'supplier_name': supplierName,
        'amount_paise': amountPaise,
        'gst_total_paise': gstTotalPaise,
        'note': note,
        'return_date': returnDate,
        'return_day': returnDay,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'is_deleted': isDeleted,
        'dirty': dirty,
      };

  Map<String, Object?> toSync() => toMap()..remove('dirty');

  static PurchaseReturn fromSync(Map<String, Object?> m) =>
      PurchaseReturn.fromMap({...m, 'dirty': 0});
}

class PurchaseReturnItem {
  final String id;
  final String returnId;
  final String productName;
  final double qty;
  final int ratePaise;
  final double gstPercent;
  final int amountPaise;
  final int createdAt;
  final int updatedAt;
  final int isDeleted;
  final int dirty;

  PurchaseReturnItem({
    required this.id,
    required this.returnId,
    required this.productName,
    required this.qty,
    required this.ratePaise,
    this.gstPercent = 0,
    required this.amountPaise,
    required this.createdAt,
    this.updatedAt = 0,
    this.isDeleted = 0,
    this.dirty = 1,
  });

  factory PurchaseReturnItem.fromMap(Map<String, Object?> m) =>
      PurchaseReturnItem(
        id: m['id'] as String,
        returnId: m['return_id'] as String,
        productName: m['product_name'] as String,
        qty: ((m['qty'] ?? 0) as num).toDouble(),
        ratePaise: (m['rate_paise'] ?? 0) as int,
        gstPercent: ((m['gst_percent'] ?? 0) as num).toDouble(),
        amountPaise: (m['amount_paise'] ?? 0) as int,
        createdAt: (m['created_at'] ?? 0) as int,
        updatedAt: (m['updated_at'] ?? 0) as int,
        isDeleted: (m['is_deleted'] ?? 0) as int,
        dirty: (m['dirty'] ?? 0) as int,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'return_id': returnId,
        'product_name': productName,
        'qty': qty,
        'rate_paise': ratePaise,
        'gst_percent': gstPercent,
        'amount_paise': amountPaise,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'is_deleted': isDeleted,
        'dirty': dirty,
      };

  Map<String, Object?> toSync() => toMap()..remove('dirty');

  int get gstPaise => ((amountPaise * gstPercent) / 100).round();
}

/// Money WE pay a supplier (settlement of the supplier account).
class SupplierPayment {
  final String id;
  final String supplierId;
  final int amountPaise;
  final int payDate;
  final String payDay;
  final String mode; // cash | upi | bank | other
  final String note;
  final int createdAt;
  final int updatedAt;
  final int isDeleted;
  final int dirty;

  SupplierPayment({
    required this.id,
    required this.supplierId,
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

  factory SupplierPayment.fromMap(Map<String, Object?> m) => SupplierPayment(
        id: m['id'] as String,
        supplierId: m['supplier_id'] as String,
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
        'supplier_id': supplierId,
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

  static SupplierPayment fromSync(Map<String, Object?> m) =>
      SupplierPayment.fromMap({...m, 'dirty': 0});
}

/// SALES RETURN: goods a customer sent back. Credited in that customer's
/// ledger (jama) with the full item detail.
class SalesReturn {
  final String id;
  final int returnNo;
  final String customerId;
  final String customerName; // snapshot
  final int amountPaise;
  final String note;
  final int returnDate;
  final String returnDay;
  final int createdAt;
  final int updatedAt;
  final int isDeleted;
  final int dirty;

  SalesReturn({
    required this.id,
    required this.returnNo,
    required this.customerId,
    required this.customerName,
    required this.amountPaise,
    this.note = '',
    required this.returnDate,
    required this.returnDay,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = 0,
    this.dirty = 1,
  });

  factory SalesReturn.fromMap(Map<String, Object?> m) => SalesReturn(
        id: m['id'] as String,
        returnNo: (m['return_no'] ?? 0) as int,
        customerId: m['customer_id'] as String,
        customerName: (m['customer_name'] ?? '') as String,
        amountPaise: (m['amount_paise'] ?? 0) as int,
        note: (m['note'] ?? '') as String,
        returnDate: (m['return_date'] ?? 0) as int,
        returnDay: (m['return_day'] ?? '') as String,
        createdAt: (m['created_at'] ?? 0) as int,
        updatedAt: (m['updated_at'] ?? 0) as int,
        isDeleted: (m['is_deleted'] ?? 0) as int,
        dirty: (m['dirty'] ?? 0) as int,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'return_no': returnNo,
        'customer_id': customerId,
        'customer_name': customerName,
        'amount_paise': amountPaise,
        'note': note,
        'return_date': returnDate,
        'return_day': returnDay,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'is_deleted': isDeleted,
        'dirty': dirty,
      };

  Map<String, Object?> toSync() => toMap()..remove('dirty');

  static SalesReturn fromSync(Map<String, Object?> m) =>
      SalesReturn.fromMap({...m, 'dirty': 0});
}

class SalesReturnItem {
  final String id;
  final String returnId;
  final String productName;
  final double qty;
  final int ratePaise;
  final int amountPaise;
  final int createdAt;
  final int updatedAt;
  final int isDeleted;
  final int dirty;

  SalesReturnItem({
    required this.id,
    required this.returnId,
    required this.productName,
    required this.qty,
    required this.ratePaise,
    required this.amountPaise,
    required this.createdAt,
    this.updatedAt = 0,
    this.isDeleted = 0,
    this.dirty = 1,
  });

  factory SalesReturnItem.fromMap(Map<String, Object?> m) => SalesReturnItem(
        id: m['id'] as String,
        returnId: m['return_id'] as String,
        productName: m['product_name'] as String,
        qty: ((m['qty'] ?? 0) as num).toDouble(),
        ratePaise: (m['rate_paise'] ?? 0) as int,
        amountPaise: (m['amount_paise'] ?? 0) as int,
        createdAt: (m['created_at'] ?? 0) as int,
        updatedAt: (m['updated_at'] ?? 0) as int,
        isDeleted: (m['is_deleted'] ?? 0) as int,
        dirty: (m['dirty'] ?? 0) as int,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'return_id': returnId,
        'product_name': productName,
        'qty': qty,
        'rate_paise': ratePaise,
        'amount_paise': amountPaise,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'is_deleted': isDeleted,
        'dirty': dirty,
      };

  Map<String, Object?> toSync() => toMap()..remove('dirty');
}
