import 'dart:io';
import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/paragraph_chunk.dart';

class PdfTextExtractorService {

  // Changed to Future
  static Future<List<ParagraphChunk>> extractParagraphsFromFile(String path, {Function(double)? onProgress}) async {
    final bytes = await File(path).readAsBytes();
    return _extractParagraphsFromBytesInternal(bytes, onProgress: onProgress);
  }

  // Changed to Future
  static Future<List<ParagraphChunk>> extractParagraphsFromBytes(Uint8List bytes, {Function(double)? onProgress}) async {
    return _extractParagraphsFromBytesInternal(bytes, onProgress: onProgress);
  }

  static Future<List<ParagraphChunk>> _extractParagraphsFromBytesInternal(
      Uint8List bytes,
      {Function(double)? onProgress}
      ) async { // Marked async
    final PdfDocument document = PdfDocument(inputBytes: bytes);
    List<ParagraphChunk> paragraphs = [];
    int totalPages = document.pages.count;

    for (int pageIndex = 0; pageIndex < totalPages; pageIndex++) {
      // --- CRITICAL FIX: YIELD TO UI THREAD ---
      await Future.delayed(Duration.zero);

      if (onProgress != null) {
        onProgress((pageIndex + 1) / totalPages);
      }

      final String pageText = PdfTextExtractor(document).extractText(
        startPageIndex: pageIndex,
        endPageIndex: pageIndex,
      );

      final List<String> pageParagraphs = _splitIntoParagraphs(pageText);

      for (final p in pageParagraphs) {
        paragraphs.add(ParagraphChunk(page: pageIndex + 1, text: p));
      }
    }

    document.dispose();
    return paragraphs;
  }

  static List<String> _splitIntoParagraphs(String rawText) {
    return rawText
        .split(RegExp(r'\n\s*\n'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
}