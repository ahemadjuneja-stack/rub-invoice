import 'package:flutter_test/flutter_test.dart';
import 'package:ruby_invoice/services/action_router.dart';

/// GOAL 1 (v0.4.1): the action router is a STRICT whitelist.
/// Anything that is not open:<screen-in-list>, url:http(s)://... or
/// dial:<phone digits> must be IGNORED - never navigated, never thrown.
void main() {
  group('ActionRouter.parse - open:', () {
    test('every whitelisted screen parses', () {
      for (final s in ActionRouter.screens) {
        final r = ActionRouter.parse('OPEN:$s');
        expect(r, isA<OpenScreenRoute>(), reason: 'open:$s');
        expect((r as OpenScreenRoute).screen, s);
      }
    });

    test('case and whitespace tolerant', () {
      expect(ActionRouter.parse('  open:Billing '), isA<OpenScreenRoute>());
    });

    test('unknown screen is ignored (not thrown)', () {
      expect(ActionRouter.parse('open:delete_all_bills'), isA<IgnoredRoute>());
      expect(ActionRouter.parse('open:'), isA<IgnoredRoute>());
    });
  });

  group('ActionRouter.parse - url:', () {
    test('http and https with a host are allowed', () {
      expect(ActionRouter.parse('url:https://wa.me/919876543210'),
          isA<UrlRoute>());
      expect(ActionRouter.parse('url:http://example.com/x'),
          isA<UrlRoute>());
    });

    test('non-http schemes are ignored', () {
      expect(ActionRouter.parse('url:ftp://x.com'), isA<IgnoredRoute>());
      expect(ActionRouter.parse('url:file:///etc/passwd'), isA<IgnoredRoute>());
      expect(ActionRouter.parse('url:javascript:alert(1)'), isA<IgnoredRoute>());
      expect(ActionRouter.parse('url:intent:#Intent;...'), isA<IgnoredRoute>());
    });

    test('no host is ignored', () {
      expect(ActionRouter.parse('url:https://'), isA<IgnoredRoute>());
      expect(ActionRouter.parse('url:   '), isA<IgnoredRoute>());
    });
  });

  group('ActionRouter.parse - dial:', () {
    test('plain phone numbers are allowed', () {
      final r = ActionRouter.parse('dial:+91 98765 43210');
      expect(r, isA<DialRoute>());
      expect((r as DialRoute).number, '+91 98765 43210');
    });

    test('non-phone payloads are ignored', () {
      expect(ActionRouter.parse('dial:https://evil.com'), isA<IgnoredRoute>());
      expect(ActionRouter.parse('dial:rm -rf /'), isA<IgnoredRoute>());
      expect(ActionRouter.parse('dial:'), isA<IgnoredRoute>());
    });
  });

  group('ActionRouter.parse - everything else', () {
    test('unknown schemes, none and garbage are ignored', () {
      expect(ActionRouter.parse('none'), isA<IgnoredRoute>());
      expect(ActionRouter.parse('intent:#Intent;launch'), isA<IgnoredRoute>());
      expect(ActionRouter.parse('market://details?id=x'), isA<IgnoredRoute>());
      expect(ActionRouter.parse(''), isA<IgnoredRoute>());
      expect(ActionRouter.parse('   '), isA<IgnoredRoute>());
      expect(ActionRouter.parse('shady:payload'), isA<IgnoredRoute>());
    });

    test('isAllowed mirrors parse', () {
      expect(ActionRouter.isAllowed('open:billing'), isTrue);
      expect(ActionRouter.isAllowed('open:format_the_phone'), isFalse);
      expect(ActionRouter.isAllowed('url:https://ok.com'), isTrue);
      expect(ActionRouter.isAllowed('dial:9876543210'), isTrue);
      expect(ActionRouter.isAllowed('dial:<script>'), isFalse);
    });
  });

  group('capList', () {
    test('caps runaway shortcut lists at max', () {
      final rows = List<int>.generate(30, (i) => i);
      expect(capList(rows, max: 12), hasLength(12));
      expect(capList(const [1, 2, 3], max: 12), hasLength(3));
    });
  });
}
