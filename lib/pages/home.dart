import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:developer';
import 'dart:io';

// External Imports
import '../keys.dart';
import '../services/extractor_service.dart';

// Local Imports
import '../models/paragraph_chunk.dart';
import '../models/scored_chunk.dart';
import '../services/file_service.dart';
import '../services/ocr_service.dart';
import '../services/comparison_service.dart';
import '../services/vectorisation_service.dart';
import '../widgets/pdf_navigator.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  File? pdfFile;
  Uint8List? pdfBytes;
  List<ParagraphChunk> chunks = [];
  bool loading = false;

  Uint8List? imageBytes;
  String extractedText = "";
  bool isLoading = false;

  late TextEditingController _textController;

  // FIX: New Service Instantiation
  final WebVectorService _vectorService = WebVectorService();
  late PdfTextExtractorService _pdfExtractorService; // Will be initialized in initState

  final OcrService _ocrService = OcrService(apiKey: ocrApiKey);
  final ComparisonService _comparisonService = ComparisonService(); // Will be updated later

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: extractedText);

    // FIX 1: Initialize the new extractor service with the vector service dependency
    _pdfExtractorService = PdfTextExtractorService(_vectorService);

    // FIX 2: Start model loading asynchronously
    _initializeServices();
  }

  // Method to handle asynchronous initialization (TFLite model loading)
  Future<void> _initializeServices() async {
    try {
      // This loads the TFLite model and vocab only once when the app starts.
      await _pdfExtractorService.initialize();
      log('DEBUG: TFLite model loaded successfully.');
    } catch (e) {
      log('FATAL ERROR: Failed to load TFLite model or vocab: $e');
      // In a real app, you would show a persistent error to the user here.
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _vectorService.dispose(); // FIX 3: IMPORTANT: Close the TFLite interpreter
    super.dispose();
  }

  // ------------------ PICK PDF & EXTRACT PARAGRAPHS ------------------
  Future<void> pickPdf() async {
    final result = await FileService.pickPdfFile();

    if (result != null) {
      if (kIsWeb) {
        pdfBytes = result.bytes;
      } else {
        pdfFile = File(result.path!);
      }
      await splitPdf(); // This now calls the new async method
    }
  }

  // FIX: Update splitPdf to use the instance methods and be asynchronous
  Future<void> splitPdf() async {
    if ((pdfFile == null && !kIsWeb) || (kIsWeb && pdfBytes == null)) return;

    // Optional: Re-check initialization, especially if initialization failed earlier
    if (!_pdfExtractorService.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('TFLite Model not ready. Please wait or check logs.')),
      );
      return;
    }

    setState(() {
      loading = true;
      chunks.clear();
    });

    log('DEBUG: Starting PDF split and vectorization...');

    try {
      List<ParagraphChunk> extracted;
      if (kIsWeb) {
        // FIX: CALL ASYNC INSTANCE METHOD for web
        extracted = await _pdfExtractorService.extractAndVectorizeFromBytes(pdfBytes!);
      } else {
        // FIX: CALL ASYNC INSTANCE METHOD for mobile/desktop
        extracted = await _pdfExtractorService.extractAndVectorizeFromFile(pdfFile!.path);
      }

      // The result is already List<ParagraphChunk>, no need for .cast()
      chunks.addAll(extracted);

      log('DEBUG: Vectorization complete. Total chunks: ${chunks.length}');
    } catch (e) {
      log('ERROR: PDF processing failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF Processing Failed: $e')),
      );
    }

    setState(() => loading = false);
  }

  // ------------------ PICK IMAGE (OCR) & OCR API CALLS ------------------
  // ... [pickImage method remains the same] ...
  Future<void> pickImage() async {
    final result = await FileService.pickImageFile();

    if (result == null) return;

    setState(() {
      isLoading = true;
      imageBytes = result.bytes;
    });

    try {
      final text = kIsWeb
          ? await _ocrService.sendToOcrSpaceWeb(result.bytes!, result.path!)
          : await _ocrService.sendToOcrSpace(File(result.path!));

      setState(() {
        extractedText = text;
        _textController.text = extractedText;
      });
    } catch (e) {
      setState(() {
        extractedText = "OCR failed: $e";
        _textController.text = extractedText;
      });
    } finally {
      setState(() => isLoading = false);
    }
  }


  // ------------------ TOKENIZER/COMPARISON LOGIC ------------------
  // FIX: This method will eventually need updating to use the vector service
  // to vectorize extractedText before comparison! (Leaving for next step)
  Future<List<ScoredChunk>> compareChunks() async {
    if (extractedText.isEmpty || chunks.isEmpty) {
      log('DEBUG: Comparison skipped. Search text empty or no chunks.');
      return [];
    }

    // NOTE: This call to _comparisonService.compareChunks is where the next
    // vectorization work will focus (vectorizing 'extractedText').
    return _comparisonService.compareChunks(extractedText, chunks);
  }


  // ------------------ SHOW PDF NAVIGATOR ------------------
  // ... [showPdfNavigator method remains the same] ...
  void showPdfNavigator(List<ScoredChunk> rankedChunks) {
    if (rankedChunks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No relevant paragraphs found matching the search text.')),
      );
      return;
    }
    if ((pdfFile == null && !kIsWeb) || (kIsWeb && pdfBytes == null)) return;

    log('DEBUG: Navigating to ranked chunk list...');

    if (kIsWeb) {
      final url = FileService.createPdfUrl(pdfBytes!);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TopChunkNavigatorWeb(
              pdfUrl: url,
              rankedChunks: rankedChunks
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TopChunkNavigator(
              pdfPath: pdfFile!.path,
              rankedChunks: rankedChunks
          ),
        ),
      );
    }
  }

  // ------------------ UI ------------------
  @override
  Widget build(BuildContext context) {
    const fmupYellow = Color(0xFFD4A017);
    final buttonStyle = ElevatedButton.styleFrom(
      backgroundColor: fmupYellow,
      foregroundColor: Colors.black,
      padding: const EdgeInsets.symmetric(vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('QuickLens')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: pickPdf,
              icon: const Icon(Icons.picture_as_pdf),
              label: Text(pdfFile == null && pdfBytes == null ? 'Pick PDF' : 'PDF Selected'),
              style: buttonStyle,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: pickImage,
              icon: const Icon(Icons.image),
              label: const Text("Pick Image (OCR)"),
              style: buttonStyle,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(12)),
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : TextFormField(
                  controller: _textController,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    hintText: "Enter OCR text or type your own search text here...",
                    border: InputBorder.none,
                  ),
                  style: const TextStyle(fontSize: 16, height: 1.5),
                  onChanged: (newText) {
                    extractedText = newText;
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () async {
                if (chunks.isEmpty || extractedText.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please select a PDF and extract text from an image/type text first.')),
                  );
                  return;
                }

                final rankedChunks = await compareChunks();
                showPdfNavigator(rankedChunks);
              },
              icon: const Icon(Icons.compare_arrows),
              label: const Text("Compare & Show Top Chunks"),
              style: buttonStyle.copyWith(
                padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 20)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}