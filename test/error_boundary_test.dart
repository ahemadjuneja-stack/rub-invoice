import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruby_invoice/core/error_boundary.dart';

/// GOAL 2 (v0.4.1): BUG ISOLATION TESTS.
///
/// A module is broken ON PURPOSE here and the assertions check that
///   1. only THAT module shows the "temporarily unavailable - Retry"
///      card, and
///   2. the rest of the app (sibling modules) keeps rendering and
///      working - exactly the guarantee a shopkeeper needs: a broken
///      PDF/billty/banner must never take billing down.
void main() {
  testWidgets('a crashing module shows only its retry card - siblings keep working',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            // Module 1: deliberately broken (the classic null-in-build bug).
            ErrorBoundary(
              module: 'Billty photo',
              builder: (_) {
                const String? name = null;
                return Text(name!.toUpperCase()); // throws on purpose
              },
            ),
            // Sibling module: the bill list must keep rendering.
            const Text('BILL #12 - SHREE TEXTILES'),
            // Sibling module 2.
            ElevatedButton(onPressed: () {}, child: const Text('Save bill')),
          ],
        ),
      ),
    ));
    await tester.pump();

    // The broken module is replaced by its card...
    expect(find.textContaining('Billty photo temporarily unavailable'),
        findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    // ...and the rest of the app is STILL THERE.
    expect(find.text('BILL #12 - SHREE TEXTILES'), findsOneWidget);
    expect(find.text('Save bill'), findsOneWidget);
  });

  testWidgets('Retry brings a fixed module back', (tester) async {
    bool healthy = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ErrorBoundary(
          module: 'Ledger',
          builder: (_) {
            if (!healthy) throw StateError('data not ready');
            return const Text('LEDGER OK');
          },
        ),
      ),
    ));
    await tester.pump();
    expect(find.textContaining('Ledger temporarily unavailable'), findsOneWidget);

    // "Fix" the module, then press Retry.
    healthy = true;
    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(find.text('LEDGER OK'), findsOneWidget);
    expect(find.textContaining('temporarily unavailable'), findsNothing);
  });

  testWidgets('two broken modules stay independent (own retry, own card)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            ErrorBoundary(
              module: 'Banner',
              compact: true,
              builder: (_) => throw Exception('banner boom'),
            ),
            ErrorBoundary(
              module: 'PDF share',
              compact: true,
              builder: (_) => throw Exception('pdf boom'),
            ),
            const Text('Billing still fine'),
          ],
        ),
      ),
    ));
    await tester.pump();

    expect(find.textContaining('Banner temporarily unavailable'), findsOneWidget);
    expect(find.textContaining('PDF share temporarily unavailable'),
        findsOneWidget);
    expect(find.text('Billing still fine'), findsOneWidget);
    expect(find.text('RETRY'), findsNWidgets(2));
  });

  test('guard() swallows a failing async operation (button handler safety)',
      () async {
    // GOAL 2: fire-and-forget handlers (upload, share, cleanup) must
    // never bubble an exception into the zone / crash the app.
    var reached = false;
    await RubyErrorGuard.guard(() async {
      throw Exception('camera exploded');
    }, where: 'test:billty_upload');
    // The line above did not throw - guard isolated the failure.
    reached = true;
    expect(reached, isTrue);
  });
}
