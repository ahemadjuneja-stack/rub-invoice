import 'package:flutter_test/flutter_test.dart';

import 'package:ruby_invoice/core/formatters.dart';
import 'package:ruby_invoice/data/models.dart';

void main() {
  group('Money.parsePaise', () {
    test('plain rupees', () {
      expect(Money.parsePaise('1250'), 125000);
      expect(Money.parsePaise('0'), 0);
    });
    test('decimals', () {
      expect(Money.parsePaise('1250.5'), 125050);
      expect(Money.parsePaise('0.1'), 10);
      expect(Money.parsePaise('12.345'), 1235); // rounds, never truncates
    });
    test('commas and symbols', () {
      expect(Money.parsePaise('1,250.50'), 125050);
      expect(Money.parsePaise('\u{20B9} 12,500'), 1250000);
    });
    test('garbage is safe zero', () {
      expect(Money.parsePaise(''), 0);
      expect(Money.parsePaise('abc'), 0);
      expect(Money.parsePaise('-5'), 0);
    });
  });

  group('Money.fmt (Indian grouping)', () {
    test('formats thousands', () {
      expect(Money.fmt(1250000), '\u{20B9} 12,500.00');
    });
    test('formats lakhs Indian style', () {
      expect(Money.fmt(123456789), '\u{20B9} 12,34,567.89');
    });
    test('negative and symbolless', () {
      expect(Money.fmt(-5000), '-\u{20B9} 50.00');
      expect(Money.fmt(1250000, withSymbol: false), '12,500.00');
    });
    test('rate input echo', () {
      expect(Money.fmtRupeesInput(45000), '450');
      expect(Money.fmtRupeesInput(1250), '12.5');
    });
  });

  group('Bill math', () {
    test('line amount = round(qty x ratePaise)', () {
      expect(CartLine(name: 'x', qty: 3, ratePaise: 5000).amountPaise, 15000);
      expect(CartLine(name: 'x', qty: 3.333, ratePaise: 15000).amountPaise, 49995);
      expect(CartLine(name: 'x', qty: 2.5, ratePaise: 1000).amountPaise, 2500);
    });
    test('sum of many lines stays exact (integer paise)', () {
      int total = 0;
      for (var i = 0; i < 1000; i++) {
        total += CartLine(name: 'x', qty: 0.1, ratePaise: 999).amountPaise;
      }
      // 0.1*999 = 99.9 -> 100 paise per line, 1000 lines = 100000
      expect(total, 100000);
    });
  });

  group('Dt', () {
    test('day keys', () {
      final d = DateTime(2026, 11, 19, 14, 30);
      expect(Dt.dayKey(d), '2026-11-19');
      expect(Dt.ymOf('2026-11-19'), '2026-11');
      expect(Dt.fromDayKey('2026-11-19').day, 19);
    });
    test('labels', () {
      expect(Dt.labelFor(Dt.todayKey()), 'Today');
      expect(Dt.labelFor(Dt.yesterdayKey()), 'Yesterday');
      expect(Dt.labelFor('2025-01-05'), '5 Jan');
    });
  });
}
