import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../core/app_log.dart';
import 'bill_scan_parser.dart';

/// AI bill scan for purchase invoices (v0.3.0):
///
/// "Agar poore bill ka Capture liya jaye to automatically AI hi usko
/// scane karke sara data apne aap fill kar dena chahiye."
///
/// Implementation: fully ON-DEVICE text recognition - no cloud, no data
/// leaves the phone (the photo never travels anywhere). The recognizer
/// reads the paper bill's text, and [BillScanParser] (pure Dart, unit
/// tested) extracts the party bill number, item lines with GST%, parcel
/// charges and the printed grand total. The purchase form then pre-fills
/// and the owner reviews before saving.
class BillScanService {
  BillScanService._();
  static final BillScanService instance = BillScanService._();

  /// Scans the bill photo at [imagePath] and returns the pre-fill data,
  /// or null when nothing usable was read.
  Future<BillScanResult?> scan(String imagePath) async {
    TextRecognizer? recognizer;
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final result = await recognizer.processImage(inputImage);
      final lines = result.text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (lines.isEmpty) return null;
      return BillScanParser.parse(lines);
    } catch (e) {
      appLog('[scan] failed: $e');
      return null;
    } finally {
      try {
        await recognizer?.close();
      } catch (_) {}
    }
  }
}
