import 'package:flutter_test/flutter_test.dart';

import 'package:ruby_invoice/core/formatters.dart';
import 'package:ruby_invoice/models/models.dart';
import 'package:ruby_invoice/models/settlement.dart';
import 'package:ruby_invoice/services/access_service.dart';

Bill _bill(int no, int totalPaise, DateTime date) => Bill(
      id: 'b$no',
      billNo: no,
      customerId: 'c1',
      customerName: 'Test',
      billDate: date.millisecondsSinceEpoch,
      billDay: Dt.dayKey(date),
      subtotalPaise: totalPaise,
      totalPaise: totalPaise,
      createdAt: date.millisecondsSinceEpoch,
      updatedAt: date.millisecondsSinceEpoch,
    );

Payment _pay(int amountPaise, DateTime date, {String? billId}) => Payment(
      id: 'p${date.millisecondsSinceEpoch}_$amountPaise',
      customerId: 'c1',
      billId: billId,
      amountPaise: amountPaise,
      payDate: date.millisecondsSinceEpoch,
      payDay: Dt.dayKey(date),
      createdAt: date.millisecondsSinceEpoch,
      updatedAt: date.millisecondsSinceEpoch,
    );

void main() {
  final d1 = DateTime(2026, 1, 10);
  final d2 = DateTime(2026, 2, 10);
  final d3 = DateTime(2026, 3, 10);

  group('FIFO Settlement', () {
    test('partial payment marks the bill partial, never settled', () {
      final s = Settlement.allocate(
        bills: [_bill(1, 100000, d1)], // ₹1000
        payments: [_pay(40000, d2)], // ₹400
      );
      expect(s.rows.single.status, SettlementStatus.partial);
      expect(s.rows.single.paidPaise, 40000);
      expect(s.rows.single.duePaise, 60000);
      expect(s.netBalancePaise, 60000);
      expect(s.advancePaise, 0);
    });

    test('oldest bill settles first, next one gets the remainder', () {
      final s = Settlement.allocate(
        bills: [_bill(1, 60000, d1), _bill(2, 40000, d2)],
        payments: [_pay(70000, d3)],
      );
      expect(s.rows[0].status, SettlementStatus.settled); // ₹600 bill
      expect(s.rows[0].paidPaise, 60000);
      expect(s.rows[1].status, SettlementStatus.partial); // ₹100 of ₹400
      expect(s.rows[1].paidPaise, 10000);
      expect(s.rows[1].duePaise, 30000);
      expect(s.netBalancePaise, 30000);
    });

    test('overpayment settles all and the rest is advance (jama extra)', () {
      final s = Settlement.allocate(
        bills: [_bill(1, 50000, d1)],
        payments: [_pay(80000, d2)],
      );
      expect(s.rows.single.status, SettlementStatus.settled);
      expect(s.advancePaise, 30000);
      expect(s.netBalancePaise, -30000);
    });

    test('payment linked to a bill settles THAT bill first', () {
      final s = Settlement.allocate(
        bills: [_bill(1, 60000, d1), _bill(2, 40000, d2)],
        payments: [
          _pay(40000, d3, billId: 'b2'), // "Received with bill #2"
          _pay(60000, d3.add(const Duration(milliseconds: 1))),
        ],
      );
      // b2 is settled by its own payment, the free ₹600 settles b1.
      expect(s.rows[0].status, SettlementStatus.settled);
      expect(s.rows[1].status, SettlementStatus.settled);
      expect(s.rows[1].paidPaise, 40000);
      expect(s.advancePaise, 0);
    });

    test('opening (old) balance is the oldest due and settles first', () {
      final s = Settlement.allocate(
        bills: [_bill(1, 50000, d1)],
        payments: [_pay(120000, d2)],
        openingBalancePaise: 100000, // ₹1000 old udhar
      );
      expect(s.rows[0].title, 'Old balance');
      expect(s.rows[0].status, SettlementStatus.settled);
      expect(s.rows[0].paidPaise, 100000);
      expect(s.rows[1].paidPaise, 20000); // ₹200 of the ₹500 bill
      expect(s.rows[1].status, SettlementStatus.partial);
      expect(s.netBalancePaise, 30000);
    });

    test('paise-level exactness: 1 paisa due stays 1 paisa', () {
      final s = Settlement.allocate(
        bills: [_bill(1, 33335, d1)], // ₹333.35
        payments: [_pay(33334, d2)], // ₹333.34
      );
      expect(s.rows.single.duePaise, 1);
      expect(s.netBalancePaise, 1);
    });

    test('invariant: payments == allocated + advance (no paisa created/lost)', () {
      final bills = [
        _bill(1, 12345, d1),
        _bill(2, 678950, d2),
        _bill(3, 1, d3),
      ];
      final pays = [
        _pay(10000, d1),
        _pay(500000, d2, billId: 'b2'),
        _pay(25000, d3),
      ];
      final s = Settlement.allocate(
        bills: bills,
        payments: pays,
        openingBalancePaise: 45678,
      );
      final totalPaid = pays.fold(0, (a, p) => a + p.amountPaise);
      expect(s.allocatedPaise + s.advancePaise, totalPaid);
      final owed = 45678 + bills.fold(0, (a, b) => a + b.totalPaise);
      expect(s.netBalancePaise, owed - totalPaid);
    });

    test('deleted rows are ignored (tombstones)', () {
      final b = _bill(1, 50000, d1);
      final liveB = Bill(
        id: b.id,
        billNo: b.billNo,
        customerId: b.customerId,
        customerName: b.customerName,
        billDate: b.billDate,
        billDay: b.billDay,
        subtotalPaise: b.subtotalPaise,
        totalPaise: b.totalPaise,
        createdAt: b.createdAt,
        updatedAt: b.updatedAt,
        isDeleted: 0,
      );
      final dead = Bill(
        id: 'dead',
        billNo: 2,
        customerId: 'c1',
        customerName: 'Test',
        billDate: d2.millisecondsSinceEpoch,
        billDay: Dt.dayKey(d2),
        subtotalPaise: 999999,
        totalPaise: 999999,
        createdAt: 0,
        updatedAt: 0,
        isDeleted: 1,
      );
      final deadPay = Payment(
        id: 'deadp',
        customerId: 'c1',
        amountPaise: 777777,
        payDate: d3.millisecondsSinceEpoch,
        payDay: Dt.dayKey(d3),
        createdAt: 0,
        updatedAt: 0,
        isDeleted: 1,
      );
      final s = Settlement.allocate(
        bills: [dead, liveB],
        payments: [_pay(20000, d3), deadPay],
      );
      expect(s.rows.length, 1);
      expect(s.rows.single.paidPaise, 20000);
    });
  });

  group('Decimal money (0% floating-point error)', () {
    test('parsePaise exact for nasty decimals', () {
      expect(Money.parsePaise('0.07'), 7);
      expect(Money.parsePaise('19.99'), 1999);
      expect(Money.parsePaise('999999999999.99'), 99999999999999);
    });

    test('line amounts survive float traps', () {
      // 0.1 + 0.2 style traps never touch the paise math.
      expect(CartLine(name: 'x', qty: 0.1, ratePaise: 999).amountPaise, 100);
      expect(CartLine(name: 'x', qty: 0.2, ratePaise: 999).amountPaise, 200);
      expect(CartLine(name: 'x', qty: 3.333, ratePaise: 15000).amountPaise, 49995);
      expect(CartLine(name: 'x', qty: 1, ratePaise: 33335).amountPaise, 33335);
    });

    test('a 10,000-line bill totals exactly (half-paise boundary)', () {
      int total = 0;
      for (var i = 0; i < 10000; i++) {
        // 0.5 x 1 paise = 0.5 paise -> rounds UP to 1 paise per line,
        // exactly 10000 paise over 10,000 lines - no drift anywhere.
        total += CartLine(name: 'x', qty: 0.5, ratePaise: 1).amountPaise;
      }
      expect(total, 10000);
      // 0.3 paise per line rounds DOWN to 0 - consistent, no paisa magic.
      expect(CartLine(name: 'x', qty: 0.3, ratePaise: 1).amountPaise, 0);
    });
  });

  group('Access control logic (admin / kill-switch rules)', () {
    final dev = 'device-A';
    final now = DateTime(2026, 11, 19);

    AccountInfo info({
      required String status,
      DateTime? expiry,
      int maxDevices = 2,
      List<String> devices = const ['device-A'],
    }) =>
        AccountInfo(
          uid: 'u1',
          businessName: 'Ruby Traders',
          phone: '+919000000000',
          status: status,
          expiryDate: expiry,
          maxDevices: maxDevices,
          registeredDevices: devices,
        );

    test('active + not expired + approved device = allowed', () {
      final i = info(status: 'active', expiry: now.add(const Duration(days: 30)));
      expect(i.evaluateFor(dev, now: now), AccessState.allowed);
    });

    test('pending blocks the app until admin approves', () {
      final i = info(status: 'pending', expiry: now.add(const Duration(days: 30)));
      expect(i.evaluateFor(dev, now: now), AccessState.pending);
    });

    test('blocked (kill-switch) locks instantly', () {
      final i = info(status: 'blocked', expiry: now.add(const Duration(days: 30)));
      expect(i.evaluateFor(dev, now: now), AccessState.blocked);
    });

    test('expired subscription locks', () {
      final i = info(status: 'active', expiry: now.subtract(const Duration(seconds: 1)));
      expect(i.evaluateFor(dev, now: now), AccessState.expired);
    });

    test('null expiry means no expiry', () {
      final i = info(status: 'active', expiry: null);
      expect(i.evaluateFor(dev, now: now), AccessState.allowed);
    });

    test('2-device limit: unknown 3rd device is rejected', () {
      final i = info(
        status: 'active',
        expiry: now.add(const Duration(days: 30)),
        devices: const ['device-A', 'device-B'],
      );
      expect(i.evaluateFor('device-C', now: now), AccessState.deviceLimit);
      expect(i.evaluateFor('device-A', now: now), AccessState.allowed);
    });

    test('free device slot auto-allows and will register', () {
      final i = info(
        status: 'active',
        expiry: now.add(const Duration(days: 30)),
        devices: const ['device-A'],
      );
      expect(i.evaluateFor('device-B', now: now), AccessState.allowed);
    });
  });
}
