import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:developer';
import 'dart:io';

// External Imports
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';

import '../keys.dart';
import '../services/extractor_service.dart';
import '../services/question_extractor.dart';

// Local Imports
import '../models/paragraph_chunk.dart';
import '../models/scored_chunk.dart';
import '../services/file_service.dart';
import '../services/ocr_service.dart';
import '../services/comparison_service.dart';
import '../widgets/pdf_navigator.dart';
import '../widgets/answer_display.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // --- STATE VARIABLES ---
  File? pdfFile;
  Uint8List? pdfBytes;

  // Data State
  List<ParagraphChunk> chunks = [];
  List<Map<String, dynamic>> jsonQuestions = [];

  // Toggles & Loading
  bool inferJson = false;
  bool loading = false; // PDF processing state
  double _processingProgress = 0.0; // 0.0 to 1.0
  bool isLoading = false; // OCR processing state

  // OCR / Text Input State
  Uint8List? imageBytes;
  String extractedText = "";
  late TextEditingController _textController;

  // Drag Interaction State
  bool _isDraggingPdf = false;
  bool _isDraggingImage = false;

  final OcrService _ocrService = OcrService(apiKey: ocrApiKey);
  final ComparisonService _comparisonService = ComparisonService();

  // --- THEME COLORS ---
  final Color kFmupYellow = const Color(0xFFD4A017);
  final Color kDarkText = const Color(0xFF1A1A1A); // High contrast black
  final Color kSubText = const Color(0xFF4A4A4A);   // High contrast grey
  final Color kBackground = const Color(0xFFF9FAFB);

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: extractedText);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  // ------------------ PDF LOGIC ------------------

  /// Core helper to load PDF data from any source (Picker or Drag)
  Future<void> _loadPdfData(Uint8List? bytes, String? path) async {
    if (bytes == null && path == null) return;

    setState(() {
      if (kIsWeb) {
        pdfBytes = bytes;
      } else {
        // On Desktop/Mobile, prefer path, fallback to bytes
        if (path != null) {
          pdfFile = File(path);
        } else if (bytes != null) {
          pdfBytes = bytes;
        }
      }
    });

    // Automatically start processing
    await processPdf();
  }

  Future<void> pickPdf() async {
    final result = await FileService.pickPdfFile();
    if (result != null) {
      await _loadPdfData(result.bytes, result.path);
    }
  }

  Future<void> _handleDroppedPdf(List<XFile> files) async {
    if (files.isEmpty) return;
    final file = files.first;

    if (!file.name.toLowerCase().endsWith('.pdf')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please drop a PDF file here.')),
        );
      }
      return;
    }

    final bytes = await file.readAsBytes();
    await _loadPdfData(bytes, file.path);
  }

  Future<void> processPdf() async {
    if ((pdfFile == null && !kIsWeb) || (kIsWeb && pdfBytes == null)) return;

    setState(() {
      loading = true;
      _processingProgress = 0.0; // Reset progress bar
      chunks.clear();
      jsonQuestions.clear();
    });

    try {
      if (inferJson) {
        // --- JSON MODE ---
        if (kIsWeb) {
          // ADDED AWAIT
          jsonQuestions = await PdfQuestionExtractor.extractQuestionsFromBytes(
            pdfBytes!,
            "web_doc.pdf",
            onProgress: (p) => setState(() => _processingProgress = p),
          );
        } else {
          // ADDED AWAIT
          jsonQuestions = await PdfQuestionExtractor.extractQuestionsFromFile(
            pdfFile!.path,
            onProgress: (p) => setState(() => _processingProgress = p),
          );
        }
      } else {
        // --- STANDARD CHUNK MODE ---
        if (kIsWeb) {
          // ADDED AWAIT
          final extracted = await PdfTextExtractorService.extractParagraphsFromBytes(
            pdfBytes!,
            onProgress: (p) => setState(() => _processingProgress = p),
          );
          chunks.addAll(extracted.cast<ParagraphChunk>());
        } else {
          // ADDED AWAIT
          final extracted = await PdfTextExtractorService.extractParagraphsFromFile(
            pdfFile!.path,
            onProgress: (p) => setState(() => _processingProgress = p),
          );
          chunks.addAll(extracted.cast<ParagraphChunk>());
        }
      }
    } catch (e) {
      log('ERROR: PDF processing failed: $e');
    }

    setState(() => loading = false);
  }

  // ------------------ IMAGE / OCR LOGIC ------------------

  Future<void> _processOcrRequest(Uint8List? bytes, String path) async {
    if (bytes == null && kIsWeb) return;

    setState(() {
      isLoading = true;
      imageBytes = bytes;
    });

    try {
      final text = kIsWeb
          ? await _ocrService.sendToOcrSpaceWeb(bytes!, path)
          : await _ocrService.sendToOcrSpace(File(path));

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

  Future<void> pickImage() async {
    final result = await FileService.pickImageFile();
    if (result == null) return;
    await _processOcrRequest(result.bytes, result.path ?? "image.png");
  }

  Future<void> _handleDroppedImage(List<XFile> files) async {
    if (files.isEmpty) return;
    final file = files.first;

    final ext = file.name.split('.').last.toLowerCase();
    if (!['png', 'jpg', 'jpeg', 'bmp', 'gif'].contains(ext)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please drop an image file (PNG, JPG).')),
        );
      }
      return;
    }

    final bytes = await file.readAsBytes();
    await _processOcrRequest(bytes, file.name);
  }

  // ------------------ COMPARISON LOGIC ------------------

  void handleComparison() async {
    if (extractedText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter text or OCR an image.')));
      return;
    }

    if (inferJson) {
      if (jsonQuestions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No questions extracted. Try picking the PDF again.')));
        return;
      }

      final bestMatch = _comparisonService.findBestMatchingQuestion(
          extractedText,
          jsonQuestions
      );

      if (bestMatch != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AnswerDisplayPage(questionData: bestMatch),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No matching question found in the PDF.')));
      }

    } else {
      if (chunks.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No chunks extracted. Try picking the PDF again.')));
        return;
      }

      final rankedChunks = await _comparisonService.compareChunks(extractedText, chunks);
      _showPdfNavigator(rankedChunks);
    }
  }

  void _showPdfNavigator(List<ScoredChunk> rankedChunks) {
    if (rankedChunks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No relevant paragraphs found.')));
      return;
    }

    if (kIsWeb) {
      final url = FileService.createPdfUrl(pdfBytes!);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TopChunkNavigatorWeb(pdfUrl: url, rankedChunks: rankedChunks),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TopChunkNavigator(pdfPath: pdfFile!.path, rankedChunks: rankedChunks),
        ),
      );
    }
  }

  // ------------------ UI BUILD ------------------
  @override
  Widget build(BuildContext context) {
    bool isReady = extractedText.isNotEmpty && (chunks.isNotEmpty || jsonQuestions.isNotEmpty);

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        title: Text('QuickLens',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1, color: kDarkText)
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey[200], height: 1),
        ),
      ),

      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.black12)),
        ),
        child: SafeArea(
          child: ElevatedButton(
            onPressed: handleComparison,
            style: ElevatedButton.styleFrom(
              backgroundColor: kFmupYellow,
              foregroundColor: kDarkText,
              padding: const EdgeInsets.symmetric(vertical: 20),
              elevation: isReady ? 2 : 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(inferJson ? Icons.saved_search : Icons.compare_arrows, size: 28),
                const SizedBox(width: 12),
                Text(
                  inferJson ? "FIND ANSWER IN PDF" : "COMPARE & NAVIGATE",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("1. SOURCE DOCUMENT",
                style: TextStyle(color: kSubText, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)
            ),
            const SizedBox(height: 12),

            DropTarget(
              onDragDone: (details) => _handleDroppedPdf(details.files),
              onDragEntered: (_) => setState(() => _isDraggingPdf = true),
              onDragExited: (_) => setState(() => _isDraggingPdf = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: _isDraggingPdf ? kFmupYellow.withOpacity(0.1) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _isDraggingPdf ? kFmupYellow : Colors.grey[300]!,
                      width: _isDraggingPdf ? 2 : 1
                  ),
                ),
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      leading: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (pdfFile != null || pdfBytes != null) ? kFmupYellow : Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.picture_as_pdf,
                            color: (pdfFile != null || pdfBytes != null) ? Colors.black : Colors.grey[400],
                            size: 28
                        ),
                      ),
                      title: Text(
                        (pdfFile != null || pdfBytes != null) ? "PDF Loaded Successfully" : "No PDF Selected",
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: kDarkText),
                      ),
                      // --- PROGRESS BAR AREA ---
                      subtitle: loading
                          ? Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: _processingProgress,
                                minHeight: 6,
                                backgroundColor: Colors.grey[200],
                                valueColor: AlwaysStoppedAnimation<Color>(kFmupYellow),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Processing... ${(_processingProgress * 100).toInt()}%",
                              style: TextStyle(fontSize: 12, color: kSubText),
                            ),
                          ],
                        ),
                      )
                          : Text(
                        (pdfFile != null || pdfBytes != null)
                            ? (inferJson ? "Mode: Intelligent JSON (${jsonQuestions.length} pairs)" : "Mode: Standard (${chunks.length} chunks)")
                            : "Drag & Drop PDF here or click Select",
                        style: TextStyle(color: kSubText, height: 1.5),
                      ),
                      trailing: TextButton(
                        onPressed: pickPdf,
                        style: TextButton.styleFrom(
                            foregroundColor: kDarkText,
                            backgroundColor: Colors.grey[100],
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
                        ),
                        child: const Text("SELECT", style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),

                    const Divider(height: 1, thickness: 1),

                    Container(
                      color: Colors.transparent,
                      child: SwitchListTile(
                        activeColor: Colors.black,
                        activeTrackColor: kFmupYellow,
                        inactiveThumbColor: Colors.grey,
                        inactiveTrackColor: Colors.grey[200],
                        tileColor: Colors.transparent,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                        title: Text("Use Intelligent JSON Search", style: TextStyle(fontWeight: FontWeight.w700, color: kDarkText)),
                        subtitle: Text("Best for Q&A documents", style: TextStyle(color: kSubText)),
                        value: inferJson,
                        onChanged: (val) {
                          setState(() => inferJson = val);
                          if (pdfFile != null || pdfBytes != null) {
                            processPdf();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            Text("2. SEARCH QUERY",
                style: TextStyle(color: kSubText, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)
            ),
            const SizedBox(height: 12),

            DropTarget(
              onDragDone: (details) => _handleDroppedImage(details.files),
              onDragEntered: (_) => setState(() => _isDraggingImage = true),
              onDragExited: (_) => setState(() => _isDraggingImage = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 300,
                decoration: BoxDecoration(
                  color: _isDraggingImage ? kFmupYellow.withOpacity(0.1) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _isDraggingImage ? kFmupYellow : Colors.grey[300]!,
                      width: _isDraggingImage ? 2 : 1
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: Colors.grey[200]!))
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 8),
                          Icon(Icons.text_fields, size: 18, color: kSubText),
                          const SizedBox(width: 8),
                          Text("Input Text / OCR", style: TextStyle(fontWeight: FontWeight.w700, color: kDarkText)),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: pickImage,
                            icon: const Icon(Icons.camera_alt_outlined, size: 18),
                            label: const Text("Scan Image"),
                            style: TextButton.styleFrom(foregroundColor: kDarkText),
                          ),
                        ],
                      ),
                    ),

                    Expanded(
                      child: isLoading
                          ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: kFmupYellow),
                            const SizedBox(height: 16),
                            Text("Extracting Text...", style: TextStyle(fontWeight: FontWeight.bold, color: kDarkText))
                          ],
                        ),
                      )
                          : Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: TextField(
                              controller: _textController,
                              maxLines: null,
                              expands: true,
                              textAlignVertical: TextAlignVertical.top,
                              style: TextStyle(fontSize: 16, height: 1.5, color: kDarkText),
                              decoration: InputDecoration.collapsed(
                                hintText: "Type your question here...",
                                hintStyle: TextStyle(color: Colors.grey[400]),
                              ),
                              onChanged: (val) => extractedText = val,
                            ),
                          ),
                          if (_isDraggingImage)
                            Container(
                              color: Colors.white.withOpacity(0.9),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.add_a_photo, size: 48, color: kFmupYellow),
                                    const SizedBox(height: 12),
                                    Text("Drop Image to Scan", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: kDarkText))
                                  ],
                                ),
                              ),
                            )
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}