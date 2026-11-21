import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruby_invoice/services/live_ui_service.dart';

void main() {
  group('LiveUiConfig.fromMap - safe defaults', () {
    test('empty document -> every feature stays available', () {
      final c = LiveUiConfig.fromMap(const {});
      expect(c.maintenanceMode, isFalse);
      expect(c.enableBiltyUpload, isTrue);
      expect(c.enableGstFields, isTrue);
      expect(c.enableRazorpayBanner, isFalse);
      expect(c.enablePdfShare, isTrue);
      expect(c.bannerEnabled, isFalse);
      expect(c.bannerText, '');
      expect(c.primaryColor, isNull);
      expect(c.primaryLabel, '');
      expect(c.shortcuts, isEmpty);
    });

    test('flags are parsed and default-safe for wrong types', () {
      final c = LiveUiConfig.fromMap(const {
        'maintenance_mode': true,
        'enable_bilty_upload': false,
        'enable_gst_fields': false,
        'enable_pdf_share': false,
        'enable_razorpay_banner': true,
      });
      expect(c.maintenanceMode, isTrue);
      expect(c.enableBiltyUpload, isFalse);
      expect(c.enableGstFields, isFalse);
      expect(c.enablePdfShare, isFalse);
      expect(c.enableRazorpayBanner, isTrue);

      // A non-bool value can never crash parsing - falls back to default.
      final c2 = LiveUiConfig.fromMap(const {
        'enable_bilty_upload': 'yes',
        'enable_pdf_share': 1,
      });
      expect(c2.enableBiltyUpload, isTrue);
      expect(c2.enablePdfShare, isTrue);
    });

    test('banner colours parse from hex and ignore garbage', () {
      final c = LiveUiConfig.fromMap(const {
        'banner': {'enabled': true, 'text': 'Diwali offer', 'bg': '#9B111E', 'fg': 'FFFFFF'},
        'primary_color': '0A3D62',
        'primary_label': 'NEW BILL',
      });
      expect(c.bannerEnabled, isTrue);
      expect(c.bannerText, 'Diwali offer');
      expect(c.bannerBg, const Color(0xFF9B111E));
      expect(c.bannerFg, const Color(0xFFFFFFFF));
      expect(c.primaryColor, const Color(0xFF0A3D62));
      expect(c.primaryLabel, 'NEW BILL');

      final c2 = LiveUiConfig.fromMap(const {
        'banner': {'enabled': true, 'text': 'x', 'bg': 'red', 'fg': '#12'},
        'primary_color': '#ZZZZZZ',
      });
      expect(c2.bannerBg, isNull);
      expect(c2.bannerFg, isNull);
      expect(c2.primaryColor, isNull);
    });

    test('shortcuts: visible rows kept, malformed rows skipped', () {
      final c = LiveUiConfig.fromMap(const {
        'shortcuts': [
          {'id': 'sc_1', 'label': 'New Bill', 'icon': 'bill', 'color': '#9B111E', 'action': 'open:billing', 'visible': true},
          {'id': 'sc_2', 'label': 'Hidden', 'action': 'none', 'visible': false},
          {'id': 'sc_3', 'label': 'Offers', 'icon': 'gift', 'action': 'url:https://x.com'},
          {'id': '', 'label': 'no id'},
          'garbage',
        ],
      });
      expect(c.shortcuts.length, 2);
      expect(c.shortcuts[0].label, 'New Bill');
      expect(c.shortcuts[0].color, const Color(0xFF9B111E));
      expect(c.shortcuts[1].label, 'Offers');
    });
  });

  group('LiveUiConfig roundtrip', () {
    test('toMap -> fromMap preserves everything', () {
      const original = LiveUiConfig(
        maintenanceMode: true,
        enableBiltyUpload: false,
        enableGstFields: false,
        enableRazorpayBanner: true,
        enablePdfShare: false,
        bannerEnabled: true,
        bannerText: 'Offer',
        bannerBg: Color(0xFF112233),
        bannerFg: Color(0xFFF4F4F4),
        primaryColor: Color(0xFF445566),
        primaryLabel: 'NEW BILL',
        shortcuts: [
          LiveShortcut(id: 'sc_1', label: 'Ledger', icon: 'ledger',
              color: Color(0xFF000000), action: 'open:ledger'),
        ],
      );
      final back = LiveUiConfig.fromMap(original.toMap());
      expect(back.maintenanceMode, original.maintenanceMode);
      expect(back.enableBiltyUpload, original.enableBiltyUpload);
      expect(back.enableGstFields, original.enableGstFields);
      expect(back.enableRazorpayBanner, original.enableRazorpayBanner);
      expect(back.enablePdfShare, original.enablePdfShare);
      expect(back.bannerEnabled, original.bannerEnabled);
      expect(back.bannerText, original.bannerText);
      expect(back.bannerBg, original.bannerBg);
      expect(back.bannerFg, original.bannerFg);
      expect(back.primaryColor, original.primaryColor);
      expect(back.primaryLabel, original.primaryLabel);
      expect(back.shortcuts.length, 1);
      expect(back.shortcuts.first.label, 'Ledger');
      expect(back.shortcuts.first.action, 'open:ledger');
    });
  });

  group('LiveUiConfig v0.4.1 hardening - corrupt config never breaks the app', () {
    test('wrong types everywhere fall back to safe defaults (no throw)', () {
      final c = LiveUiConfig.fromMap(const {
        'banner': 'not-a-map', // banner should be a map
        'primary_label': 12345, // should be a string
        'shortcuts': {'a': 'b'}, // should be a list
        'maintenance_mode': 'yes', // should be a bool
      });
      expect(c.bannerEnabled, isFalse);
      expect(c.bannerText, '');
      expect(c.primaryLabel, '');
      expect(c.shortcuts, isEmpty);
      expect(c.maintenanceMode, isFalse);
    });

    test('shortcuts are capped at 12 visible rows', () {
      final many = List.generate(30, (i) => {
            'id': 'sc_$i',
            'label': 'Row $i',
            'action': 'open:billing',
            'visible': true,
          });
      final c = LiveUiConfig.fromMap({'shortcuts': many});
      expect(c.shortcuts, hasLength(12));
    });

    test('banner text as a number does not crash the parser', () {
      final c = LiveUiConfig.fromMap(const {
        'banner': {'enabled': true, 'text': 99, 'bg': '#9B111E'},
      });
      expect(c.bannerEnabled, isTrue);
      expect(c.bannerText, '99');
      expect(c.bannerBg, const Color(0xFF9B111E));
    });
  });

  group('parseHex', () {
    test('accepts 6 and 3-pair forms, rejects the rest', () {
      expect(parseHex('#9B111E'), const Color(0xFF9B111E));
      expect(parseHex('9B111E'), const Color(0xFF9B111E));
      expect(parseHex('  #ffffff '), const Color(0xFFFFFFFF));
      expect(parseHex('#9B111EA'), isNull); // 7 chars
      expect(parseHex('#GGGGGG'), isNull);
      expect(parseHex(''), isNull);
      expect(parseHex(null), isNull);
    });
  });
}
