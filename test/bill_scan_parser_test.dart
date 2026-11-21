// Parser contract for the AI bill scan (purchase form pre-fill).
// Pure Dart - runs on the VM without the ML Kit plugin.
import 'package:flutter_test/flutter_test.dart';

import 'package:ruby_invoice/services/bill_scan_parser.dart';

void main() {
  test('parses item lines with qty, rate, amount and GST%', () {
    final r = BillScanParser.parse([
      'SHIVAM NOVELTIES',
      'BILL NO: 1647',
      'DATE: 02/11/2026',
      'EARING PAIR 2 45 90 18%',
      'BUTI PAIR 10 30 300',
      'NAIL 5 12 60 12%',
      'PARCEL 150',
      'GRAND TOTAL 605',
    ]);
    expect(r.partyBillNo, '1647');
    expect(r.parcelPaise, 15000);
    expect(r.totalPaise, 60500);
    expect(r.lines.length, 3);
    expect(r.lines[0].name, 'EARING PAIR');
    expect(r.lines[0].qty, 2);
    expect(r.lines[0].ratePaise, 4500);
    expect(r.lines[0].amountPaise, 9000);
    expect(r.lines[0].gstPercent, 18);
    expect(r.lines[1].gstPercent, 0);
    expect(r.lines[2].gstPercent, 12);
  });

  test('handles comma-formatted amounts and x separator', () {
    final r = BillScanParser.parse([
      'Invoice No: I/2231',
      'COMPACT 1,250.00 x 2 2,500.00',
      'FOUNDATION 6 110 660',
      'TOTAL 3,160.00',
    ]);
    expect(r.partyBillNo, 'I/2231');
    expect(r.lines.length, 2);
    expect(r.lines[0].qty, 2);
    expect(r.lines[0].amountPaise, 250000);
    expect(r.lines[1].amountPaise, 66000);
    expect(r.totalPaise, 316000);
  });

  test('rejects implausible lines (qty*rate != amount)', () {
    final r = BillScanParser.parse([
      'PHONE 9876543210 12 34',
      'SOMETHING 3 50 99999',
    ]);
    expect(r.lines, isEmpty);
  });

  test('empty and garbage input never crash', () {
    final r = BillScanParser.parse([]);
    expect(r.lines, isEmpty);
    expect(r.partyBillNo, isEmpty);
    final r2 = BillScanParser.parse(['', '   ', '@@@']);
    expect(r2.lines, isEmpty);
  });
}
