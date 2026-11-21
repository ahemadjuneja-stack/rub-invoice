import 'dart:io';

import 'package:flutter/services.dart' show MethodChannel, rootBundle;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../core/app_log.dart';
import '../core/formatters.dart';
import '../data/repo.dart';
import '../models/models.dart';

/// Bill PDFs in three formats:
///   * A4 MEMO (default, v0.3.0) - the classic Shivam-style paper memo:
///     business logo printed black & white at the top, DEBIT MEMO /
///     CASH MEMO title by bill type, numbered item table with exactly
///     25 items per page (extra items flow to continuation pages),
///     grand total + discount box, signature at the bottom when one is
///     uploaded in Business Profile.
///   * A5 letterhead.
///   * 80mm thermal receipt.
/// DejaVu fonts are bundled (assets/fonts/) so the rupee symbol prints
/// correctly on every device.
class PdfService {
  PdfService._();
  static final PdfService instance = PdfService._();

  pw.Font? _regular;
  pw.Font? _bold;

  /// Number of pages the last built bill got (test contract: the A4
  /// memo paginates at exactly 25 item lines per page).
  int _lastPageCount = 0;
  int get lastPageCount => _lastPageCount;

  Future<void> _loadFonts() async {
    if (_regular != null) return;
    _regular = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    _bold = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
  }

  static const MethodChannel _pdfChannel = MethodChannel('ruby_invoice/pdf');

  /// Renders a PDF file into plain JPEG images (one per page) using the
  /// Android PdfRenderer via the platform channel. Empty list when the
  /// device cannot render - callers then share the PDF itself.
  Future<List<String>> rasterizePdfToImages(String pdfPath) async {
    try {
      if (!File(pdfPath).existsSync()) return const [];
      final res = await _pdfChannel
          .invokeMethod<List<Object?>>('renderPdfToImages', {'path': pdfPath});
      return (res ?? const []).whereType<String>().toList();
    } catch (e) {
      appLog('[pdf] rasterize failed, sharing the PDF instead: $e');
      return const [];
    }
  }

  /// Loads an image file and converts it to BLACK & WHITE (grayscale) -
  /// the printed memo always looks like ink on paper, whatever colours
  /// the uploaded logo / signature have. Returns null when missing/broken.
  pw.ImageProvider? _bwImage(String path) {
    try {
      if (path.isEmpty) return null;
      final f = File(path);
      if (!f.existsSync()) return null;
      final decoded = img.decodeImage(f.readAsBytesSync());
      if (decoded == null) return null;
      final gray = img.grayscale(decoded);
      final bytes = img.encodePng(gray);
      if (bytes.isEmpty) return null;
      return pw.MemoryImage(bytes);
    } catch (e) {
      appLog('[pdf] logo/signature load failed: $e');
      return null;
    }
  }

  /// Reads the locally stored business branding (Business Profile ->
  /// Branding: business_assets/logo.jpg + signature.jpg). Needs the app
  /// documents directory, so this is async and called once per share.
  Future<(pw.ImageProvider?, pw.ImageProvider?)> loadBranding() async {
    pw.ImageProvider? logo;
    pw.ImageProvider? sign;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}${Platform.pathSeparator}business_assets');
      final logoFile = File('${dir.path}${Platform.pathSeparator}logo.jpg');
      final signFile = File('${dir.path}${Platform.pathSeparator}signature.jpg');
      if (logoFile.existsSync()) logo = _bwImage(logoFile.path);
      if (signFile.existsSync()) sign = _bwImage(signFile.path);
    } catch (e) {
      appLog('[pdf] branding load failed: $e');
    }
    return (logo, sign);
  }

  Future<File> buildBillFile({
    required Bill bill,
    required List<BillItem> items,
    required Map<String, String> shop,
    String customerCity = '',
    String customerPhone = '',
    int balanceAfterPaise = 0,
    bool isCashMemo = false,
  }) async {
    await _loadFonts();
    final format = shop['bill_format'] ?? 'a4';

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: _regular!, bold: _bold!),
    );

    final shopName = (shop['shop_name'] ?? '').isNotEmpty
        ? shop['shop_name']!
        : 'Ruby Invoice';
    final shopAddr = shop['shop_addr'] ?? '';
    final shopPhone = shop['shop_phone'] ?? '';
    final gstin = shop['gstin'] ?? '';

    final (logo, sign) = await loadBranding();

    if (format == 'a4') {
      final pages = _a4MemoPages(
        bill, items, shopName, shopAddr, shopPhone, gstin,
        customerCity, customerPhone, balanceAfterPaise,
        isCashMemo, logo, sign,
      );
      _lastPageCount = pages.length;
      for (final page in pages) {
        doc.addPage(page);
      }
    } else if (format == 'a5') {
      _lastPageCount = 1;
      doc.addPage(_a5Page(bill, items, shopName, shopAddr, shopPhone, gstin,
          customerCity, customerPhone, balanceAfterPaise));
    } else {
      _lastPageCount = 1;
      doc.addPage(_thermalPage(bill, items, shopName, shopAddr, shopPhone, gstin,
          customerCity, customerPhone, balanceAfterPaise));
    }

    final dir = await getTemporaryDirectory();
    final memoKind = isCashMemo ? 'cash' : 'bill';
    final f = File('${dir.path}/${memoKind}_${bill.billNo}_${bill.billDay}.pdf');
    await f.writeAsBytes(await doc.save());
    return f;
  }

  /// Shares the bill the way the party reads it best: PAGE IMAGES.
  /// WhatsApp shows pictures instantly - the bill is visible without
  /// opening a PDF viewer. If image rendering is unavailable (rare)
  /// the PDF file itself is shared as fallback.
  Future<void> shareBill({
    required Bill bill,
    required List<BillItem> items,
    required Map<String, String> shop,
    String customerCity = '',
    String customerPhone = '',
    int balanceAfterPaise = 0,
    bool isCashMemo = false,
  }) async {
    final f = await buildBillFile(
      bill: bill,
      items: items,
      shop: shop,
      customerCity: customerCity,
      customerPhone: customerPhone,
      balanceAfterPaise: balanceAfterPaise,
      isCashMemo: isCashMemo,
    );
    final images = await rasterizePdfToImages(f.path);
    final text = '${isCashMemo ? 'Cash memo' : 'Bill'} #${bill.billNo} - '
        '${bill.customerName} - ${Money.fmt(bill.totalPaise)}';
    if (images.isNotEmpty) {
      await Share.shareXFiles(
        [for (final p in images) XFile(p, mimeType: 'image/jpeg')],
        subject: text,
        text: text,
      );
    } else {
      await Share.shareXFiles(
        [XFile(f.path)],
        subject: text,
        text: text,
      );
    }
  }

  // ================= A4 memo (default, Shivam-style) =================

  /// Exactly 25 item lines per page - the 26th product opens page 2,
  /// the 51st page 3, and so on (classic paper memo behaviour).
  static const int _a4ItemsPerPage = 25;

  List<pw.Page> _a4MemoPages(
    Bill bill,
    List<BillItem> items,
    String shopName,
    String shopAddr,
    String shopPhone,
    String gstin,
    String customerCity,
    String customerPhone,
    int balanceAfterPaise,
    bool isCashMemo,
    pw.ImageProvider? logo,
    pw.ImageProvider? sign,
  ) {
    final title = isCashMemo ? 'CASH MEMO' : 'DEBIT MEMO';
    final pages = <pw.Page>[];
    final chunks = <List<BillItem>>[];
    for (var i = 0; i < items.length; i += _a4ItemsPerPage) {
      chunks.add(items.sublist(
          i, (i + _a4ItemsPerPage) > items.length ? items.length : (i + _a4ItemsPerPage)));
    }

    for (var p = 0; p < chunks.length; p++) {
      final last = p == chunks.length - 1;
      final pageNo = p + 1;
      final pageTotal = chunks.length;

      pages.add(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 24),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // ---------- memo header ----------
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (logo != null)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(right: 12),
                    child: pw.Image(logo, height: 62, fit: pw.BoxFit.contain),
                  ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(shopName.toUpperCase(),
                          style: pw.TextStyle(
                              fontSize: 14, fontWeight: pw.FontWeight.bold)),
                      if (shopAddr.isNotEmpty)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 1),
                          child: pw.Text(shopAddr,
                              style: const pw.TextStyle(fontSize: 8.5)),
                        ),
                      pw.Text(
                        [
                          if (shopPhone.isNotEmpty) 'Ph: $shopPhone',
                          if (gstin.isNotEmpty) 'GSTIN: $gstin',
                        ].join('   '),
                        style: const pw.TextStyle(fontSize: 8.5),
                      ),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(title,
                        style: pw.TextStyle(
                            fontSize: 14, fontWeight: pw.FontWeight.bold,
                            letterSpacing: 1)),
                    pw.Text('Memo No: ${bill.billNo}',
                        style: const pw.TextStyle(fontSize: 9.5)),
                    pw.Text(Dt.fmtDayKey(bill.billDay),
                        style: const pw.TextStyle(fontSize: 9.5)),
                  ],
                ),
              ],
            ),
            pw.Container(
              margin: const pw.EdgeInsets.symmetric(vertical: 7),
              height: 1.2,
              color: PdfColors.black,
            ),
            // ---------- party box ----------
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(width: 0.8),
                borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('BILL TO',
                      style: pw.TextStyle(
                          fontSize: 7, fontWeight: pw.FontWeight.bold)),
                  pw.Text(bill.customerName,
                      style: pw.TextStyle(
                          fontSize: 11.5, fontWeight: pw.FontWeight.bold)),
                  if (customerCity.isNotEmpty || customerPhone.isNotEmpty)
                    pw.Text(
                      [customerCity, customerPhone]
                          .where((e) => e.isNotEmpty)
                          .join('   |   '),
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
            // ---------- item table (25 rows per page) ----------
            pw.Text(
              pageTotal > 1 ? 'Items (page $pageNo of $pageTotal)' : 'Items',
              style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 3),
            _a4ItemTable(chunks[p], p * _a4ItemsPerPage),
            if (last) ...[
              pw.SizedBox(height: 10),
              // ---------- totals ----------
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Received the above goods in good condition.',
                            style: const pw.TextStyle(fontSize: 8.5)),
                        if (bill.note.isNotEmpty)
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(top: 4),
                            child: pw.Text('Note: ${bill.note}',
                                style: const pw.TextStyle(fontSize: 8.5)),
                          ),
                      ],
                    ),
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      if (bill.discountPaise > 0) ...[
                        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
                          pw.Text('Subtotal',
                              style: pw.TextStyle(
                                  fontSize: 10, fontWeight: pw.FontWeight.bold)),
                          pw.SizedBox(width: 14),
                          pw.Text(Money.fmt(bill.subtotalPaise),
                              style: const pw.TextStyle(fontSize: 10)),
                        ]),
                        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
                          pw.Text('Trade discount',
                              style: const pw.TextStyle(fontSize: 10)),
                          pw.SizedBox(width: 14),
                          pw.Text('- ${Money.fmt(bill.discountPaise)}',
                              style: const pw.TextStyle(fontSize: 10)),
                        ]),
                        pw.SizedBox(height: 3),
                      ],
                      pw.Container(
                        width: 190,
                        padding: const pw.EdgeInsets.symmetric(
                            vertical: 6, horizontal: 9),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(width: 1),
                          borderRadius: const pw.BorderRadius.all(
                              pw.Radius.circular(4)),
                          color: PdfColors.grey100,
                        ),
                        child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('GRAND TOTAL',
                                style: pw.TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: pw.FontWeight.bold)),
                            pw.Text(Money.fmt(bill.totalPaise),
                                style: pw.TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: pw.FontWeight.bold)),
                          ],
                        ),
                      ),
                      if (balanceAfterPaise > 0)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 4),
                          child: pw.Text(
                            'Balance due (all bills): ${Money.fmt(balanceAfterPaise)}',
                            style: pw.TextStyle(
                                fontSize: 8.5,
                                fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              pw.Spacer(),
              // ---------- signature ----------
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Column(
                    children: [
                      if (sign != null)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 2),
                          child: pw.Image(sign, height: 46,
                              fit: pw.BoxFit.contain),
                        ),
                      pw.Container(
                        width: 150,
                        decoration: const pw.BoxDecoration(
                            border: pw.Border(
                                bottom: pw.BorderSide(width: 0.8))),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text('For $shopName',
                          style: pw.TextStyle(
                              fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Authorised Signatory',
                          style: const pw.TextStyle(fontSize: 7.5)),
                    ],
                  ),
                ],
              ),
            ] else ...[
              pw.Spacer(),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text('Continued on next page...',
                    style: const pw.TextStyle(fontSize: 8.5)),
              ),
            ],
            pw.Spacer(),
            // ---------- memo footer ----------
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 6),
              decoration: const pw.BoxDecoration(
                  border: pw.Border(
                      top: pw.BorderSide(width: 0.6))),
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                // Same-to-same with the paper memo: just the business
                // phone at the bottom, nothing else.
                shopPhone,
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
          ],
        ),
      ));
    }
    return pages;
  }

  pw.Widget _a4ItemTable(List<BillItem> items, int startNo) {
    return pw.TableHelper.fromTextArray(
      headers: ['#', 'Product', 'Qty', 'Rate', 'Amount'],
      data: [
        for (var i = 0; i < items.length; i++)
          [
            '${startNo + i + 1}',
            items[i].productName,
            _qtyText(items[i].qty),
            Money.fmt(items[i].ratePaise, withSymbol: false),
            Money.fmt(items[i].amountPaise, withSymbol: false),
          ]
      ],
      columnWidths: const {
        0: pw.FixedColumnWidth(30),
        1: pw.FlexColumnWidth(5.2),
        2: pw.FlexColumnWidth(1.6),
        3: pw.FlexColumnWidth(2.1),
        4: pw.FlexColumnWidth(2.5),
      },
      headerStyle: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 9.5),
      cellAlignment: pw.Alignment.centerLeft,
      headerAlignment: pw.Alignment.centerLeft,
      headerDecoration:
          const pw.BoxDecoration(color: PdfColors.grey200),
      border: pw.TableBorder.all(width: 0.6),
      cellPadding:
          const pw.EdgeInsets.symmetric(vertical: 3.5, horizontal: 6),
    );
  }

  // ================= A4 PURCHASE memo (v0.3.0) =================

  Future<void> sharePurchase({
    required Purchase purchase,
    required List<PurchaseItem> items,
  }) async {
    final f = await buildPurchaseFile(purchase: purchase, items: items);
    final images = await rasterizePdfToImages(f.path);
    final text = 'Purchase #${purchase.purchaseNo} - '
        '${purchase.supplierName} - ${Money.fmt(purchase.amountPaise)}';
    if (images.isNotEmpty) {
      await Share.shareXFiles(
        [for (final p in images) XFile(p, mimeType: 'image/jpeg')],
        subject: text,
        text: text,
      );
    } else {
      await Share.shareXFiles(
        [XFile(f.path)],
        subject: text,
        text: text,
      );
    }
  }

  Future<File> buildPurchaseFile({
    required Purchase purchase,
    required List<PurchaseItem> items,
  }) async {
    await _loadFonts();
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: _regular!, bold: _bold!),
    );

    final shop = await Repo.instance.shopProfile();
    final shopName = (shop['shop_name'] ?? '').isNotEmpty
        ? shop['shop_name']!
        : 'Ruby Invoice';
    final shopAddr = shop['shop_addr'] ?? '';
    final shopPhone = shop['shop_phone'] ?? '';
    final (logo, sign) = await loadBranding();

    const perPage = 25;
    final chunks = <List<PurchaseItem>>[];
    for (var i = 0; i < items.length; i += perPage) {
      chunks.add(items.sublist(
          i, (i + perPage) > items.length ? items.length : (i + perPage)));
    }
    if (chunks.isEmpty) chunks.add(const []);

    for (var p = 0; p < chunks.length; p++) {
      final last = p == chunks.length - 1;
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 24),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (logo != null)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(right: 12),
                    child: pw.Image(logo, height: 62, fit: pw.BoxFit.contain),
                  ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(shopName.toUpperCase(),
                          style: pw.TextStyle(
                              fontSize: 15, fontWeight: pw.FontWeight.bold)),
                      if (shopAddr.isNotEmpty)
                        pw.Text(shopAddr,
                            style: const pw.TextStyle(fontSize: 8.5)),
                      if (shopPhone.isNotEmpty)
                        pw.Text('Ph: $shopPhone',
                            style: const pw.TextStyle(fontSize: 8.5)),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('PURCHASE MEMO',
                        style: pw.TextStyle(
                            fontSize: 15,
                            fontWeight: pw.FontWeight.bold,
                            letterSpacing: 1)),
                    pw.Text('No: ${purchase.purchaseNo}',
                        style: const pw.TextStyle(fontSize: 9.5)),
                    pw.Text(Dt.fmtDayKey(purchase.purchaseDay),
                        style: const pw.TextStyle(fontSize: 9.5)),
                  ],
                ),
              ],
            ),
            pw.Container(
              margin: const pw.EdgeInsets.symmetric(vertical: 7),
              height: 1.2,
              color: PdfColors.black,
            ),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(width: 0.8),
                borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('PURCHASE FROM',
                      style: pw.TextStyle(
                          fontSize: 7, fontWeight: pw.FontWeight.bold)),
                  pw.Text(purchase.supplierName,
                      style: pw.TextStyle(
                          fontSize: 11.5, fontWeight: pw.FontWeight.bold)),
                  if (purchase.supplierPhone.isNotEmpty)
                    pw.Text(purchase.supplierPhone,
                        style: const pw.TextStyle(fontSize: 9)),
                  if (purchase.partyBillNo.isNotEmpty)
                    pw.Text('Party bill no: ${purchase.partyBillNo}',
                        style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
            if (chunks.length > 1)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Text('Items (page ${p + 1} of ${chunks.length})',
                    style: pw.TextStyle(
                        fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
              ),
            pw.TableHelper.fromTextArray(
              headers: ['#', 'Product', 'Qty', 'Rate', 'GST%', 'Amount'],
              data: [
                for (var i = 0; i < chunks[p].length; i++)
                  [
                    '${p * perPage + i + 1}',
                    chunks[p][i].productName,
                    _qtyText(chunks[p][i].qty),
                    Money.fmt(chunks[p][i].ratePaise, withSymbol: false),
                    chunks[p][i].gstPercent == 0
                        ? '-'
                        : chunks[p][i].gstPercent.toStringAsFixed(0),
                    Money.fmt(chunks[p][i].amountPaise, withSymbol: false),
                  ]
              ],
              columnWidths: const {
                0: pw.FixedColumnWidth(28),
                1: pw.FlexColumnWidth(4.6),
                2: pw.FlexColumnWidth(1.4),
                3: pw.FlexColumnWidth(1.9),
                4: pw.FlexColumnWidth(1.1),
                5: pw.FlexColumnWidth(2.3),
              },
              headerStyle: pw.TextStyle(
                  fontSize: 9.5, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 9.5),
              cellAlignment: pw.Alignment.centerLeft,
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey200),
              border: pw.TableBorder.all(width: 0.6),
              cellPadding:
                  const pw.EdgeInsets.symmetric(vertical: 3.5, horizontal: 6),
            ),
            if (last) ...[
              pw.SizedBox(height: 10),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: purchase.note.isNotEmpty
                        ? pw.Text('Note: ${purchase.note}',
                            style: const pw.TextStyle(fontSize: 8.5))
                        : pw.SizedBox(),
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.end,
                          children: [
                            pw.Text('Subtotal (goods)',
                                style: const pw.TextStyle(fontSize: 10)),
                            pw.SizedBox(width: 14),
                            pw.Text(Money.fmt(purchase.subtotalPaise),
                                style: const pw.TextStyle(fontSize: 10)),
                          ]),
                      pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.end,
                          children: [
                            pw.Text('GST total',
                                style: const pw.TextStyle(fontSize: 10)),
                            pw.SizedBox(width: 14),
                            pw.Text(Money.fmt(purchase.gstTotalPaise),
                                style: const pw.TextStyle(fontSize: 10)),
                          ]),
                      pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.end,
                          children: [
                            pw.Text('Parcel / transport',
                                style: const pw.TextStyle(fontSize: 10)),
                            pw.SizedBox(width: 14),
                            pw.Text(Money.fmt(purchase.parcelPaise),
                                style: const pw.TextStyle(fontSize: 10)),
                          ]),
                      pw.SizedBox(height: 4),
                      pw.Container(
                        width: 200,
                        padding: const pw.EdgeInsets.symmetric(
                            vertical: 6, horizontal: 9),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(width: 1),
                          borderRadius: const pw.BorderRadius.all(
                              pw.Radius.circular(4)),
                          color: PdfColors.grey100,
                        ),
                        child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('GRAND TOTAL',
                                style: pw.TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: pw.FontWeight.bold)),
                            pw.Text(Money.fmt(purchase.amountPaise),
                                style: pw.TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: pw.FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Column(
                    children: [
                      if (sign != null)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 2),
                          child: pw.Image(sign,
                              height: 46, fit: pw.BoxFit.contain),
                        ),
                      pw.Container(
                        width: 150,
                        decoration: const pw.BoxDecoration(
                            border: pw.Border(
                                bottom: pw.BorderSide(width: 0.8))),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text('For $shopName',
                          style: pw.TextStyle(
                              fontSize: 9.5,
                              fontWeight: pw.FontWeight.bold)),
                      pw.Text('Received the above goods',
                          style: const pw.TextStyle(fontSize: 7.5)),
                    ],
                  ),
                ],
              ),
            ] else ...[
              pw.Spacer(),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text('Continued on next page...',
                    style: const pw.TextStyle(fontSize: 8.5)),
              ),
            ],
            pw.Spacer(),
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 6),
              decoration: const pw.BoxDecoration(
                  border: pw.Border(top: pw.BorderSide(width: 0.6))),
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                // Same-to-same with the paper memo: phone only.
                shopPhone,
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
          ],
        ),
      ));
    }

    final dir = await getTemporaryDirectory();
    final f = File(
        '${dir.path}/purchase_${purchase.purchaseNo}_${purchase.purchaseDay}.pdf');
    await f.writeAsBytes(await doc.save());
    return f;
  }

  // ---------- 80mm thermal receipt ----------

  pw.MultiPage _thermalPage(
    Bill bill,
    List<BillItem> items,
    String shopName,
    String shopAddr,
    String shopPhone,
    String gstin,
    String customerCity,
    String customerPhone,
    int balanceAfterPaise,
  ) {
    final head = <pw.Widget>[
      pw.Center(
        child: pw.Text(
          shopName.toUpperCase(),
          style: pw.TextStyle(fontSize: 12.5, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
      ),
      if (shopAddr.isNotEmpty)
        pw.Center(
          child: pw.Text(shopAddr,
              style: const pw.TextStyle(fontSize: 7.5), textAlign: pw.TextAlign.center),
        ),
      pw.Center(
        child: pw.Text(
          [
            if (shopPhone.isNotEmpty) 'Ph: $shopPhone',
            if (gstin.isNotEmpty) 'GSTIN: $gstin',
          ].join('  |  '),
          style: const pw.TextStyle(fontSize: 7.5),
          textAlign: pw.TextAlign.center,
        ),
      ),
      pw.Container(
        margin: const pw.EdgeInsets.symmetric(vertical: 5),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(width: 0.8)),
        ),
      ),
      pw.Center(
        child: pw.Text('BILL',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, letterSpacing: 2)),
      ),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Bill No: ${bill.billNo}', style: const pw.TextStyle(fontSize: 8.5)),
          pw.Text(Dt.fmtDayKey(bill.billDay), style: const pw.TextStyle(fontSize: 8.5)),
        ],
      ),
      pw.SizedBox(height: 2),
      pw.Text(bill.customerName,
          style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
      if (customerCity.isNotEmpty || customerPhone.isNotEmpty)
        pw.Text(
          [customerCity, customerPhone].where((e) => e.isNotEmpty).join('  |  '),
          style: const pw.TextStyle(fontSize: 8),
        ),
      pw.Container(
        margin: const pw.EdgeInsets.only(top: 5, bottom: 2),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
        ),
      ),
    ];

    final table = pw.TableHelper.fromTextArray(
      headers: ['Item', 'Qty', 'Rate', 'Amount'],
      data: [
        for (final it in items)
          [
            it.productName,
            _qtyText(it.qty),
            Money.fmt(it.ratePaise, withSymbol: false),
            Money.fmt(it.amountPaise, withSymbol: false),
          ]
      ],
      columnWidths: const {
        0: pw.FlexColumnWidth(4.4),
        1: pw.FlexColumnWidth(1.7),
        2: pw.FlexColumnWidth(2.2),
        3: pw.FlexColumnWidth(2.6),
      },
      headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellAlignment: pw.Alignment.centerLeft,
      cellPadding: const pw.EdgeInsets.symmetric(vertical: 2),
      headerDecoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
      ),
    );

    final foot = <pw.Widget>[
      pw.Container(
        margin: const pw.EdgeInsets.only(top: 4),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(width: 0.5)),
        ),
      ),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('TOTAL', style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
          pw.Text(Money.fmt(bill.totalPaise),
              style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
        ],
      ),
      if (bill.note.isNotEmpty) pw.Text('Note: ${bill.note}', style: const pw.TextStyle(fontSize: 7.5)),
      pw.SizedBox(height: 8),
      pw.Center(
        child: pw.Text('Thank you! Visit again.',
            style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
      ),
      pw.Center(
        child: pw.Text('Powered by Ruby Invoice', style: const pw.TextStyle(fontSize: 6.5)),
      ),
    ];

    return pw.MultiPage(
      pageFormat: const PdfPageFormat(226, 842, marginAll: 12),
      build: (context) => [
        ...head,
        table,
        ...foot,
      ],
    );
  }

  // ---------- A5 letterhead ----------

  pw.Page _a5Page(
    Bill bill,
    List<BillItem> items,
    String shopName,
    String shopAddr,
    String shopPhone,
    String gstin,
    String customerCity,
    String customerPhone,
    int balanceAfterPaise,
  ) {
    return pw.Page(
      pageFormat: const PdfPageFormat(420, 595, marginAll: 24),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(shopName.toUpperCase(),
                        style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
                    if (shopAddr.isNotEmpty)
                      pw.Text(shopAddr, style: const pw.TextStyle(fontSize: 8.5)),
                    pw.Text(
                      [
                        if (shopPhone.isNotEmpty) 'Ph: $shopPhone',
                        if (gstin.isNotEmpty) 'GSTIN: $gstin',
                      ].join('   '),
                      style: const pw.TextStyle(fontSize: 8.5),
                    ),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('BILL', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.Text('No: ${bill.billNo}', style: const pw.TextStyle(fontSize: 10)),
                  pw.Text(Dt.fmtDayKey(bill.billDay), style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ],
          ),
          pw.Container(
            margin: const pw.EdgeInsets.symmetric(vertical: 8),
            height: 1.2,
            color: PdfColors.black,
          ),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: 0.7),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('BILL TO', style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                pw.Text(bill.customerName,
                    style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold)),
                pw.Text(
                  [customerCity, customerPhone].where((e) => e.isNotEmpty).join('   |   '),
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: ['#', 'Item', 'Qty', 'Rate', 'Amount'],
            data: [
              for (var i = 0; i < items.length; i++)
                [
                  '${i + 1}',
                  items[i].productName,
                  _qtyText(items[i].qty),
                  Money.fmt(items[i].ratePaise, withSymbol: false),
                  Money.fmt(items[i].amountPaise, withSymbol: false),
                ]
            ],
            columnWidths: const {
              0: pw.FixedColumnWidth(24),
              1: pw.FlexColumnWidth(5),
              2: pw.FlexColumnWidth(1.6),
              3: pw.FlexColumnWidth(2.2),
              4: pw.FlexColumnWidth(2.6),
            },
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            border: pw.TableBorder.all(width: 0.6),
            cellPadding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 5),
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Container(
                    width: 170,
                    padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(width: 0.9),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                      color: PdfColors.grey100,
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('TOTAL', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                        pw.Text(Money.fmt(bill.totalPaise),
                            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ),
                  if (balanceAfterPaise > 0)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 4),
                      child: pw.Text(
                        'Balance due (all bills): ${Money.fmt(balanceAfterPaise)}',
                        style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (bill.note.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 8),
              child: pw.Text('Note: ${bill.note}', style: const pw.TextStyle(fontSize: 9)),
            ),
          pw.Spacer(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Powered by Ruby Invoice', style: const pw.TextStyle(fontSize: 7.5)),
                ],
              ),
              pw.Column(
                children: [
                  pw.Container(width: 130, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.7)))),
                  pw.SizedBox(height: 4),
                  pw.Text('For $shopName', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Authorised Signatory', style: const pw.TextStyle(fontSize: 7.5)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _qtyText(double qty) {
    if (qty == qty.roundToDouble()) {
      return qty.round().toString();
    }
    return qty.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
}
