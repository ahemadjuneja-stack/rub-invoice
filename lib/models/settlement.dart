import 'models.dart';

/// How much of a bill is still outstanding.
enum SettlementStatus { unpaid, partial, settled }

/// One settle-able row in a customer's account: either the opening
/// ("old") balance or a bill. `paidPaise` is how much money has been
/// applied to it, `duePaise` what is still outstanding.
class SettlementRow {
  final String refId; // bill id ('' for the opening-balance row)
  final String title;
  final int billNo; // 0 for opening
  final DateTime date;
  final int amountPaise; // total owed for this row
  final int paidPaise; // money applied to this row
  final SettlementStatus status;

  SettlementRow({
    required this.refId,
    required this.title,
    required this.billNo,
    required this.date,
    required this.amountPaise,
    required this.paidPaise,
    required this.status,
  });

  int get duePaise => amountPaise - paidPaise;
}

/// Result of running the FIFO allocator for one customer.
class Settlement {
  final List<SettlementRow> rows; // chronological (oldest first)
  final int allocatedPaise; // money applied to rows
  final int advancePaise; // money left over = customer's advance (jama extra)
  final int netBalancePaise; // +ve = udhar (owes), -ve = advance, 0 = settled

  Settlement({
    required this.rows,
    required this.allocatedPaise,
    required this.advancePaise,
    required this.netBalancePaise,
  });

  int get unpaidCount =>
      rows.where((r) => r.status == SettlementStatus.unpaid).length;
  int get partialCount =>
      rows.where((r) => r.status == SettlementStatus.partial).length;
  int get settledCount =>
      rows.where((r) => r.status == SettlementStatus.settled).length;

  /// FIFO bill settlement - the exact accounting rule:
  ///
  ///  1. The opening ("old") balance, if positive, is the oldest due and
  ///     is settled first.
  ///  2. A payment recorded WITH a bill (payment.billId) belongs to that
  ///     bill: it is applied there first, capped at the bill total.
  ///     Any leftover flows into the common pool.
  ///  3. Everything else forms a pool that is poured over the rows in
  ///     date order - the OLDEST bill settles first, then the next, and
  ///     so on ("marks older unpaid/partial bills as settled/partially
  ///     paid accurately").
  ///  4. Money left after every row is settled is the customer's advance.
  ///
  /// All math is on integer paise: allocation can never lose or create a
  /// paisa. Invariant (asserted in tests):
  ///   sum(payments) == allocatedPaise + advancePaise
  ///   netBalancePaise == sum(row amounts) - sum(payments)
  static Settlement allocate({
    required List<Bill> bills,
    required List<Payment> payments,
    int openingBalancePaise = 0,
  }) {
    final live = bills.where((b) => b.isDeleted == 0).toList()
      ..sort((a, b) {
        final c = a.billDate.compareTo(b.billDate);
        if (c != 0) return c;
        return a.billNo.compareTo(b.billNo);
      });
    final pays = payments.where((p) => p.isDeleted == 0).toList()
      ..sort((a, b) => a.payDate.compareTo(b.payDate));

    // Internal mutable rows.
    final refIds = <String>[]; // bill id or 'opening'
    final titles = <String>[];
    final billNos = <int>[];
    final dates = <int>[]; // epoch ms
    final amounts = <int>[];
    final paid = <int>[];
    final byId = <String, int>{}; // bill id -> row index

    if (openingBalancePaise > 0) {
      refIds.add('opening');
      titles.add('Old balance');
      billNos.add(0);
      dates.add(0); // oldest possible -> settles first
      amounts.add(openingBalancePaise);
      paid.add(0);
    }
    for (final b in live) {
      byId[b.id] = refIds.length;
      refIds.add(b.id);
      titles.add('Bill #${b.billNo}');
      billNos.add(b.billNo);
      dates.add(b.billDate);
      amounts.add(b.totalPaise);
      paid.add(0);
    }

    int remainingDue(int i) => amounts[i] - paid[i];

    // Stage 1 - payments tied to a specific bill settle that bill first.
    int pool = 0;
    for (final p in pays) {
      final bid = p.billId;
      final idx = (bid == null || bid.isEmpty) ? -1 : (byId[bid] ?? -1);
      if (idx >= 0 && remainingDue(idx) > 0) {
        final take = p.amountPaise < remainingDue(idx)
            ? p.amountPaise
            : remainingDue(idx);
        paid[idx] += take;
        pool += p.amountPaise - take;
      } else {
        pool += p.amountPaise;
      }
    }

    // Stage 2 - pour the pool over rows oldest first.
    for (int i = 0; i < refIds.length && pool > 0; i++) {
      final take = pool < remainingDue(i) ? pool : remainingDue(i);
      paid[i] += take;
      pool -= take;
    }

    final advance = pool;
    final allocated = pays.fold(0, (s, p) => s + p.amountPaise) - advance;

    final rows = <SettlementRow>[];
    for (int i = 0; i < refIds.length; i++) {
      final status = paid[i] == 0
          ? SettlementStatus.unpaid
          : paid[i] >= amounts[i]
              ? SettlementStatus.settled
              : SettlementStatus.partial;
      rows.add(SettlementRow(
        refId: refIds[i],
        title: titles[i],
        billNo: billNos[i],
        date: DateTime.fromMillisecondsSinceEpoch(dates[i]),
        amountPaise: amounts[i],
        paidPaise: paid[i],
        status: status,
      ));
    }

    final totalOwed = amounts.fold(0, (s, a) => s + a);
    final totalPaid = pays.fold(0, (s, p) => s + p.amountPaise);
    return Settlement(
      rows: rows,
      allocatedPaise: allocated,
      advancePaise: advance,
      netBalancePaise: totalOwed - totalPaid,
    );
  }
}
