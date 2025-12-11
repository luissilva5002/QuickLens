import 'dart:io';
import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart';

// FIX: Import the centralized model definition and the vector service
import '../models/paragraph_chunk.dart';
import 'vectorisation_service.dart'; // Assuming this is the correct path

class PdfTextExtractorService {

  final WebVectorService _vectorService;

  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  PdfTextExtractorService(this._vectorService);
// ... rest of the class


  /// Must be called once before any extraction/vectorization.
  /// This loads the heavy TFLite model and vocabulary.
  Future<void> initialize() async {
    if (!_vectorService.isLoaded) {
      await _vectorService.loadModel();
    }
    _isInitialized = true;
    print('PDF Extractor initialized and Vector Service loaded.');
  }

  // --- Public Extraction Methods ---

  /// Extracts paragraphs from the PDF at [path] and vectorizes each one.
  Future<List<ParagraphChunk>> extractAndVectorizeFromFile(String path) async {
    if (!_isInitialized) {
      throw StateError('Service not initialized. Call initialize() first.');
    }
    final bytes = File(path).readAsBytesSync();
    return _extractAndVectorizeFromBytesInternal(bytes);
  }

  /// Extracts paragraphs from the PDF [bytes] for web and vectorizes each one.
  Future<List<ParagraphChunk>> extractAndVectorizeFromBytes(Uint8List bytes) async {
    if (!_isInitialized) {
      throw StateError('Service not initialized. Call initialize() first.');
    }
    return _extractAndVectorizeFromBytesInternal(bytes);
  }

  // --- Internal Helper with Vectorization Logic ---

  Future<List<ParagraphChunk>> _extractAndVectorizeFromBytesInternal(Uint8List bytes) async {
    final PdfDocument document = PdfDocument(inputBytes: bytes);
    List<ParagraphChunk> textChunks = [];
    List<ParagraphChunk> vectorizedChunks = [];

    // 1. Synchronously Extract Text Chunks from PDF
    for (int pageIndex = 0; pageIndex < document.pages.count; pageIndex++) {
      final String pageText = PdfTextExtractor(document).extractText(
        startPageIndex: pageIndex,
        endPageIndex: pageIndex,
      );

      final List<String> pageParagraphs = _splitIntoParagraphs(pageText);

      for (final p in pageParagraphs) {
        textChunks.add(
          ParagraphChunk(
            page: pageIndex + 1,
            text: p,
          ),
        );
      }
    }

    document.dispose(); // Release the PDF document

    // 2. Asynchronously Vectorize Each Chunk
    print('Starting vectorization of ${textChunks.length} paragraphs...');

    // We use a Future.wait or a simple loop for sequential processing
    // A simple loop ensures memory safety and avoids overwhelming the TFLite interpreter.
    for (final chunk in textChunks) {
      try {
        final List<double> vector = await _vectorService.vectorizeText(chunk.text);

        vectorizedChunks.add(
          ParagraphChunk(
            page: chunk.page,
            text: chunk.text,
            vector: vector, // <-- Vector is stored
          ),
        );
      } catch (e) {
        print('Error vectorizing chunk on page ${chunk.page}: $e. Adding chunk without vector.');
        // If vectorization fails, still add the chunk, but without a vector.
        vectorizedChunks.add(chunk);
      }
    }

    print('Completed vectorization. Total vectorized chunks: ${vectorizedChunks.length}');
    return vectorizedChunks;
  }

  /// Split text into paragraphs based on blank lines.
  static List<String> _splitIntoParagraphs(String rawText) {
    return rawText
        .split(RegExp(r'\n\s*\n')) // Split on blank lines / empty lines
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
}