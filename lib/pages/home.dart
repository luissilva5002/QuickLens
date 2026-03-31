import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:developer';
import 'dart:io';

// External Imports
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
// ADDED: Required to count pages for default input values
import 'package:syncfusion_flutter_pdf/pdf.dart';

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

  // Page Range Controllers
  final TextEditingController _startPageCtrl = TextEditingController();
  final TextEditingController _endPageCtrl = TextEditingController();

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
    _startPageCtrl.dispose();
    _endPageCtrl.dispose();
    super.dispose();
  }

  // ------------------ PDF LOGIC ------------------

  /// Core helper to load PDF data from any source (Picker or Drag)
  Future<void> _loadPdfData(Uint8List? bytes, String? path) async {
    // Safety check: if widget is disposed, stop immediately
    if (!mounted) return;
    if (bytes == null && path == null) return;

    // Web specific check: if on web, we MUST have bytes
    if (kIsWeb && bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Could not load file content. Try Drag & Drop instead.')),
      );
      return;
    }

    // --- NEW LOGIC: CALCULATE PAGE COUNT ---
    int totalPages = 0;
    try {
      // We need bytes to count pages using Syncfusion PdfDocument
      Uint8List? dataToCount = bytes;

      // If we are on mobile/desktop and only have a path, read the bytes now
      if (dataToCount == null && path != null && !kIsWeb) {
        final file = File(path);
        if (await file.exists()) {
          dataToCount = await file.readAsBytes();
        }
      }

      if (dataToCount != null) {
        // Open document temporarily to count pages
        final PdfDocument document = PdfDocument(inputBytes: dataToCount);
        totalPages = document.pages.count;
        document.dispose(); // Dispose immediately to free memory
      }
    } catch (e) {
      log("Error calculating page count: $e");
    }

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

      // Reset Data
      chunks.clear();
      jsonQuestions.clear();
      _processingProgress = 0.0;

      // Set Page Range Defaults based on count
      if (totalPages > 0) {
        _startPageCtrl.text = "1";
        _endPageCtrl.text = totalPages.toString();
      } else {
        _startPageCtrl.clear();
        _endPageCtrl.clear();
      }
    });
  }

  Future<void> pickPdf() async {
    try {
      final result = await FileService.pickPdfFile();
      if (result != null) {
        await _loadPdfData(result.bytes, result.path);
      }
    } catch (e) {
      log("Error picking PDF: $e");
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
    if (!mounted) return;
    if ((pdfFile == null && !kIsWeb) || (kIsWeb && pdfBytes == null)) return;

    setState(() {
      loading = true;
      _processingProgress = 0.0; // Reset progress bar
      chunks.clear();
      jsonQuestions.clear();
    });

    // Parse Page Range Inputs
    // Logic: Only parse if inferJson is TRUE. Otherwise, send null.
    int? startPage;
    int? endPage;

    if (inferJson) {
      startPage = int.tryParse(_startPageCtrl.text);
      endPage = int.tryParse(_endPageCtrl.text);
    }

    try {
      if (inferJson) {
        // --- JSON MODE ---
        if (kIsWeb) {
          jsonQuestions = await PdfQuestionExtractor.extractQuestionsFromBytes(
            pdfBytes!,
            "web_doc.pdf",
            onProgress: (p) { if(mounted) setState(() => _processingProgress = p); },
            startPage: startPage,
            endPage: endPage,
          );
        } else {
          jsonQuestions = await PdfQuestionExtractor.extractQuestionsFromFile(
            pdfFile!.path,
            onProgress: (p) { if(mounted) setState(() => _processingProgress = p); },
            startPage: startPage,
            endPage: endPage,
          );
        }
      } else {
        // --- STANDARD CHUNK MODE (Ignores Page Range) ---
        if (kIsWeb) {
          final extracted = await PdfTextExtractorService.extractParagraphsFromBytes(
            pdfBytes!,
            onProgress: (p) { if(mounted) setState(() => _processingProgress = p); },
          );
          chunks.addAll(extracted.cast<ParagraphChunk>());
        } else {
          final extracted = await PdfTextExtractorService.extractParagraphsFromFile(
            pdfFile!.path,
            onProgress: (p) { if(mounted) setState(() => _processingProgress = p); },
          );
          chunks.addAll(extracted.cast<ParagraphChunk>());
        }
      }
    } catch (e) {
      log('ERROR: PDF processing failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Processing failed: $e')));
      }
    }

    if (mounted) {
      setState(() => loading = false);
    }
  }

  // ------------------ IMAGE / OCR LOGIC ------------------

  Future<void> _processOcrRequest(Uint8List? bytes, String path) async {
    if (bytes == null && kIsWeb) return;
    if (!mounted) return;

    setState(() {
      isLoading = true;
      imageBytes = bytes;
    });

    try {
      final text = kIsWeb
          ? await _ocrService.sendToOcrSpaceWeb(bytes!, path)
          : await _ocrService.sendToOcrSpace(File(path));

      if (mounted) {
        setState(() {
          extractedText = text;
          _textController.text = extractedText;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          extractedText = "OCR failed: $e";
          _textController.text = extractedText;
        });
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No questions extracted. Please scan the PDF first.')));
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No chunks extracted. Please scan the PDF first.')));
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

  // ------------------ UI HELPERS ------------------

  InputDecoration _inlineInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
      border: InputBorder.none,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
    );
  }

  // ------------------ UI BUILD ------------------
  @override
  Widget build(BuildContext context) {
    bool isReady = extractedText.isNotEmpty && (chunks.isNotEmpty || jsonQuestions.isNotEmpty);
    bool hasPdf = (pdfFile != null || pdfBytes != null);

    // Determine status text
    String statusTitle = hasPdf ? "PDF Loaded" : "No PDF Selected";
    Widget statusSubtitle;
    if (loading) {
      statusSubtitle = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _processingProgress,
              minHeight: 4,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(kFmupYellow),
            ),
          ),
        ],
      );
    } else if (hasPdf) {
      bool hasData = chunks.isNotEmpty || jsonQuestions.isNotEmpty;
      statusSubtitle = Text(
        hasData
            ? (inferJson ? "Ready (${jsonQuestions.length} pairs extracted)" : "Ready (${chunks.length} chunks extracted)")
            : "Select pages and click Extract",
        style: TextStyle(color: kSubText, fontSize: 13, height: 1.5),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    } else {
      statusSubtitle = Text(
        "Drag & Drop or Tap Icon",
        style: TextStyle(color: kSubText, fontSize: 13, height: 1.5),
      );
    }

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

      body: Padding(
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
                    // --- HEADER ROW ---
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Row(
                        children: [
                          // 1. SELECTOR ICON (Clickable with fixed InkWell)
                          Material(
                            color: hasPdf ? kFmupYellow : Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              onTap: pickPdf,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                child: Icon(
                                    Icons.picture_as_pdf,
                                    color: hasPdf ? Colors.black : Colors.grey[400],
                                    size: 28
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 16),

                          // 2. STATUS TEXT
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  statusTitle,
                                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: kDarkText),
                                ),
                                statusSubtitle,
                              ],
                            ),
                          ),

                          // 3. INPUTS & EXTRACT BUTTON (Unified Height)
                          if (hasPdf) ...[
                            const SizedBox(width: 8),
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // COMBINED INPUT SHAPE
                                  Container(
                                    width: 130,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.grey[300]!),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: _startPageCtrl,
                                            keyboardType: TextInputType.number,
                                            textAlign: TextAlign.center,
                                            decoration: _inlineInputDecoration("From"),
                                          ),
                                        ),
                                        Container(
                                          width: 1,
                                          margin: const EdgeInsets.symmetric(vertical: 8),
                                          color: Colors.grey[300],
                                        ),
                                        Expanded(
                                          child: TextField(
                                            controller: _endPageCtrl,
                                            keyboardType: TextInputType.number,
                                            textAlign: TextAlign.center,
                                            decoration: _inlineInputDecoration("To"),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(width: 8),

                                  // EXTRACT BUTTON
                                  Material(
                                    color: kFmupYellow,
                                    borderRadius: BorderRadius.circular(8),
                                    child: InkWell(
                                      onTap: loading ? null : processPdf,
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16),
                                        alignment: Alignment.center,
                                        child: loading
                                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                                            : const Text("EXTRACT", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.black)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            const SizedBox(width: 8),
                            Text("Tap Icon", style: TextStyle(color: Colors.grey[400], fontSize: 12, fontWeight: FontWeight.bold)),
                          ]
                        ],
                      ),
                    ),

                    const Divider(height: 1, thickness: 1),

                    Container(
                      color: Colors.transparent,
                      child: SwitchListTile(
                        activeThumbColor: Colors.black,
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
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
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
    );
  }
}