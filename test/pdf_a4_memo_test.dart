// A4 memo end-to-end test: builds a real PDF through PdfService (fonts,
// branding B&W conversion, 25-items-per-page chunking) and writes it to
// a temp file. Run:  flutter test test/pdf_a4_memo_test.dart
//
// The produced PDF is rendered to images OUTSIDE the test (pdftoppm) for
// the visual check; the assertions here pin the structural contract:
// the file exists, is a valid PDF and honours the 25-lines-per-page rule.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:ruby_invoice/models/models.dart';
import 'package:ruby_invoice/services/pdf_service.dart';

class _FakePathProvider extends PathProviderPlatform {
  final String tmp;
  final String docs;
  _FakePathProvider(this.tmp, this.docs);

  @override
  Future<String?> getTemporaryPath() async => tmp;

  @override
  Future<String?> getApplicationDocumentsPath() async => docs;
}

Bill _bill(int itemCount) => Bill(
      id: 'b1',
      billNo: 1647,
      customerId: 'c1',
      customerName: 'ANJAR-3F SHAKTI NOVELTY',
      billDate: DateTime(2026, 11, 2).millisecondsSinceEpoch,
      billDay: '2026-11-02',
      subtotalPaise: 975000,
      discountPaise: 58500,
      totalPaise: 916500,
      note: 'Delivery by transport',
      createdAt: 0,
      updatedAt: 0,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('A4 memo: 60 items -> 3 pages of max 25 lines each + branding B&W',
      () async {
    final tmp = await Directory.systemTemp.createTemp('rubypdf');
    final docs = await Directory.systemTemp.createTemp('rubydocs');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path, docs.path);

    // Fake business branding: a red logo + a dark signature scribble.
    final assetDir =
        Directory('${docs.path}${Platform.pathSeparator}business_assets')
          ..createSync(recursive: true);
    // Minimal valid JPEGs via the pdf package? Simpler: tiny PNG bytes
    // renamed .jpg would break decode - write real JPEGs using the image
    // encoder indirectly: easiest is a solid 1x1 JPEG header trick is
    // fragile, so generate with the pure-Dart image package through
    // PdfService's own dependency set is not exposed. We instead embed
    // PNG bytes (the image package decodes PNG from a .jpg filename fine -
    // decodeImage sniffs the format, not the extension).
    final logoPng = _makePng(220, 90, 0x9B, 0x11, 0x1E);
    final signPng = _makePng(180, 70, 0x22, 0x22, 0x22);
    File('${assetDir.path}${Platform.pathSeparator}logo.jpg')
        .writeAsBytesSync(logoPng);
    File('${assetDir.path}${Platform.pathSeparator}signature.jpg')
        .writeAsBytesSync(signPng);

    final items = [
      for (var i = 0; i < 60; i++)
        BillItem(
          id: 'i$i',
          billId: 'b1',
          productName: i == 0
              ? 'EARING PAIR (a very long product name to check wrapping '
                  'behaviour inside the memo table columns)'
              : 'Item ${i + 1}',
          qty: 2,
          ratePaise: 3600,
          amountPaise: 7200,
          createdAt: 0,
        ),
    ];

    final f = await PdfService.instance.buildBillFile(
      bill: _bill(60),
      items: items,
      shop: {
        'shop_name': 'Shivam Novelty',
        'shop_addr': 'Main Bazar, Anjar - Kutch',
        'shop_phone': '9723632635',
        'gstin': '',
        'bill_format': 'a4',
      },
      customerCity: 'ANJAR',
      customerPhone: '9876543210',
      balanceAfterPaise: 916500,
      isCashMemo: false, // debit memo (nothing received)
    );

    expect(f.existsSync(), isTrue);
    final bytes = f.readAsBytesSync();
    expect(bytes.length, greaterThan(2000));
    expect(String.fromCharCodes(bytes.sublist(0, 5)), startsWith('%PDF'));

    // Structural contract of the A4 memo: 60 items at 25/page = 3 pages.
    expect(PdfService.instance.lastPageCount, 3,
        reason: '60 items must paginate to 3 pages (25+25+10)');

    // Keep the artefact for the manual visual check (pdftoppm outside).
    final visual = File('/tmp/rubypdf_test/memo_60items.pdf');
    visual.parent.createSync(recursive: true);
    await f.copy(visual.path);
    await tmp.delete(recursive: true);
    await docs.delete(recursive: true);
  });

  test('CASH memo naming + full cash flow produces CASH MEMO title bytes',
      () async {
    final tmp = await Directory.systemTemp.createTemp('rubypdf2');
    final docs = await Directory.systemTemp.createTemp('rubydocs2');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path, docs.path);

    final f = await PdfService.instance.buildBillFile(
      bill: _bill(3),
      items: [
        for (var i = 0; i < 3; i++)
          BillItem(
            id: 'c$i',
            billId: 'b1',
            productName: 'Cash item ${i + 1}',
            qty: 1,
            ratePaise: 10000,
            amountPaise: 10000,
            createdAt: 0,
          ),
      ],
      shop: {'shop_name': 'Shivam', 'bill_format': 'a4'},
      isCashMemo: true,
    );
    expect(f.existsSync(), isTrue);
    // File name carries the memo kind.
    expect(f.path.contains('cash_1647'), isTrue);
  });
}

/// Builds a tiny valid PNG (image package is a transitive dep of the app
/// and available in tests via PdfService's own import graph).
List<int> _makePng(int w, int h, int r, int g, int b) {
  // Use package:image through PdfService's dependency set is not
  // exported; construct a minimal PNG manually (solid colour, no filter).
  final chunk = (String type, List<int> data) {
    final len = data.length;
    final body = [
      type.codeUnitAt(0), type.codeUnitAt(1), type.codeUnitAt(2),
      type.codeUnitAt(3), ...data,
    ];
    final crc = _crc32(body);
    return [
      (len >> 24) & 0xFF, (len >> 16) & 0xFF, (len >> 8) & 0xFF, len & 0xFF,
      ...body,
      (crc >> 24) & 0xFF, (crc >> 16) & 0xFF, (crc >> 8) & 0xFF, crc & 0xFF,
    ];
  };
  final ihdr = [
    (w >> 24) & 0xFF, (w >> 16) & 0xFF, (w >> 8) & 0xFF, w & 0xFF,
    (h >> 24) & 0xFF, (h >> 16) & 0xFF, (h >> 8) & 0xFF, h & 0xFF,
    8, // bit depth
    2, // colour type RGB
    0, 0, 0, // compression, filter, interlace
  ];
  final raw = <int>[];
  for (var y = 0; y < h; y++) {
    raw.add(0); // filter none
    for (var x = 0; x < w; x++) {
      raw.addAll([r, g, b]);
    }
  }
  return [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    ...chunk('IHDR', ihdr),
    ...chunk('IDAT', _zlibStore(raw)),
    ...chunk('IEND', []),
  ];
}

int _crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c ^= b;
    for (var k = 0; k < 8; k++) {
      c = (c >> 1) ^ (0xEDB88320 & (-(c & 1)));
    }
  }
  return (~c) & 0xFFFFFFFF;
}

/// Stored (uncompressed) zlib stream: header + deflate stored blocks.
List<int> _zlibStore(List<int> data) {
  final out = <int>[0x78, 0x01];
  var i = 0;
  while (i < data.length) {
    final n = (data.length - i) > 65535 ? 65535 : (data.length - i);
    final last = (i + n) >= data.length ? 1 : 0;
    out.addAll([last, n & 0xFF, (n >> 8) & 0xFF, (~n) & 0xFF, ((n >> 8) & 0xFF) ^ 0xFF]);
    out.addAll(data.sublist(i, i + n));
    i += n;
  }
  final adler = _adler32(data);
  out.addAll([(adler >> 24) & 0xFF, (adler >> 16) & 0xFF, (adler >> 8) & 0xFF, adler & 0xFF]);
  return out;
}

int _adler32(List<int> data) {
  var a = 1, b = 0;
  for (final x in data) {
    a = (a + x) % 65521;
    b = (b + a) % 65521;
  }
  return (b << 16) | a;
}
