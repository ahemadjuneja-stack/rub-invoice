import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../core/formatters.dart';
import '../models/models.dart';

/// Bill PDFs in two formats: 80mm thermal receipt and A5 letterhead.
/// DejaVu fonts are bundled (assets/fonts/) so the rupee symbol prints
/// correctly on every device.
class PdfService {
  PdfService._();
  static final PdfService instance = PdfService._();

  pw.Font? _regular;
  pw.Font? _bold;

  Future<void> _loadFonts() async {
    if (_regular != null) return;
    _regular = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    _bold = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
  }

  Future<File> buildBillFile({
    required Bill bill,
    required List<BillItem> items,
    required Map<String, String> shop,
    String customerCity = '',
    String customerPhone = '',
    int balanceAfterPaise = 0,
  }) async {
    await _loadFonts();
    final isA5 = (shop['bill_format'] ?? 't80') == 'a5';

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: _regular!, bold: _bold!),
    );

    final shopName = (shop['shop_name'] ?? '').isNotEmpty
        ? shop['shop_name']!
        : 'Ruby Invoice';
    final shopAddr = shop['shop_addr'] ?? '';
    final shopPhone = shop['shop_phone'] ?? '';
    final gstin = shop['gstin'] ?? '';

    if (isA5) {
      doc.addPage(_a5Page(bill, items, shopName, shopAddr, shopPhone, gstin,
          customerCity, customerPhone, balanceAfterPaise));
    } else {
      doc.addPage(_thermalPage(bill, items, shopName, shopAddr, shopPhone, gstin,
          customerCity, customerPhone, balanceAfterPaise));
    }

    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/bill_${bill.billNo}_${bill.billDay}.pdf');
    await f.writeAsBytes(await doc.save());
    return f;
  }

  Future<void> shareBill({
    required Bill bill,
    required List<BillItem> items,
    required Map<String, String> shop,
    String customerCity = '',
    String customerPhone = '',
    int balanceAfterPaise = 0,
  }) async {
    final f = await buildBillFile(
      bill: bill,
      items: items,
      shop: shop,
      customerCity: customerCity,
      customerPhone: customerPhone,
      balanceAfterPaise: balanceAfterPaise,
    );
    await Share.shareXFiles(
      [XFile(f.path)],
      subject: 'Bill #${bill.billNo} - ${bill.customerName}',
      text: 'Bill #${bill.billNo} - ${Money.fmt(bill.totalPaise)}',
    );
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
