import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:pdfx/pdfx.dart';
import 'dart:html' as html;
import 'dart:math' as math;
import 'keys.dart'; // Your API key for OCR
import 'ExtarctorService.dart'; // Your paragraph extraction logic

// Add print statements to show what's happening
import 'dart:developer';

void main() {
  runApp(const QuickLensApp());
}

// --- NEW DATA MODEL FOR RANKING ---
class ScoredChunk {
  final ParagraphChunk chunk;
  final double score;

  ScoredChunk({required this.chunk, required this.score});
}
// ----------------------------------

class QuickLensApp extends StatelessWidget {
  const QuickLensApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QuickLens',
      theme: ThemeData(primarySwatch: Colors.amber),
      home: const HomePage(),
    );
  }
}

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
  List<Map<String, Map<double, List<String>>>> compatibles = [];

  // Using a placeholder for API key, assume 'ocrApiKey' is defined in 'keys.dart'
  final String apiKey = ocrApiKey;

  // ------------------ PICK PDF ------------------
  Future<void> pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: kIsWeb,
    );

    if (result != null) {
      if (kIsWeb) {
        pdfBytes = result.files.first.bytes;
        log('DEBUG: PDF picked (Web). Bytes loaded: ${pdfBytes!.length}');
      } else if (result.files.single.path != null) {
        pdfFile = File(result.files.single.path!);
        log('DEBUG: PDF picked (Mobile). Path: ${pdfFile!.path}');
      }
      await splitPdf();
    }
  }

  // ------------------ EXTRACT PARAGRAPHS ------------------
  Future<void> splitPdf() async {
    if ((pdfFile == null && !kIsWeb) || (kIsWeb && pdfBytes == null)) return;

    setState(() {
      loading = true;
      chunks.clear();
    });

    log('DEBUG: Starting PDF split...');

    try {
      if (kIsWeb) {
        chunks.addAll(PdfTextExtractorService.extractParagraphsFromBytes(pdfBytes!));
      } else {
        chunks.addAll(PdfTextExtractorService.extractParagraphsFromFile(pdfFile!.path));
      }
      log('DEBUG: Split complete. Total chunks: ${chunks.length}');
    } catch (e) {
      log('ERROR: PDF split failed: $e');
    }

    setState(() => loading = false);
  }

  // ------------------ CREATE PDF URL (Web) ------------------
  String createPdfUrl(Uint8List pdfBytes) {
    final blob = html.Blob([pdfBytes], 'application/pdf');
    return html.Url.createObjectUrlFromBlob(blob);
  }

  // ------------------ PICK IMAGE (OCR) & OCR API CALLS ------------------
  Future<void> pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: kIsWeb,
    );

    if (result != null) {
      if (kIsWeb) {
        await _handleFileBytes(result.files.first.bytes!, result.files.first.name);
      } else if (result.files.single.path != null) {
        await _handleFile(File(result.files.single.path!));
      }
    }
  }

  Future<void> _handleFile(File file) async {
    setState(() => isLoading = true);
    final bytes = await file.readAsBytes();
    setState(() => imageBytes = bytes);

    try {
      final text = await _sendToOcrSpace(file);
      setState(() => extractedText = text);
    } catch (e) {
      setState(() => extractedText = "OCR failed: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _handleFileBytes(Uint8List bytes, String filename) async {
    setState(() => isLoading = true);
    setState(() => imageBytes = bytes);

    try {
      final text = await _sendToOcrSpaceWeb(bytes, filename);
      setState(() => extractedText = text);
    } catch (e) {
      setState(() => extractedText = "OCR failed: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<String> _sendToOcrSpace(File file) async {
    log('DEBUG: Sending image to OCR.space (Mobile)...');
    final uri = Uri.parse('https://api.ocr.space/parse/image');
    final request = http.MultipartRequest('POST', uri);
    request.headers['apikey'] = apiKey;
    request.fields['language'] = 'por';
    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    final response = await request.send();
    final respStr = await response.stream.bytesToString();
    final data = json.decode(respStr);

    log('DEBUG: OCR Response Status: ${response.statusCode}');

    if (data['IsErroredOnProcessing'] == true) {
      final error = data['ErrorMessage'] ?? 'Unknown OCR error';
      log('ERROR: OCR API Error: $error');
      throw Exception(error);
    }

    final parsedResults = data['ParsedResults'] as List;
    if (parsedResults.isEmpty) return '';

    final extracted = parsedResults.map((r) => r['ParsedText'] ?? '').join('\n');
    log('DEBUG: OCR Extracted Text (${extracted.length} chars): ${extracted.substring(0, extracted.length.clamp(0, 100))}...');
    return extracted;
  }

  Future<String> _sendToOcrSpaceWeb(Uint8List bytes, String filename) async {
    log('DEBUG: Sending image to OCR.space (Web)...');
    final uri = Uri.parse('https://api.ocr.space/parse/image');
    final request = http.MultipartRequest('POST', uri);
    request.headers['apikey'] = apiKey;
    request.fields['language'] = 'por';
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));

    final response = await request.send();
    final respStr = await response.stream.bytesToString();
    final data = json.decode(respStr);

    log('DEBUG: OCR Response Status: ${response.statusCode}');

    if (data['IsErroredOnProcessing'] == true) {
      final error = data['ErrorMessage'] ?? 'Unknown OCR error';
      log('ERROR: OCR API Error: $error');
      throw Exception(error);
    }

    final parsedResults = data['ParsedResults'] as List;
    if (parsedResults.isEmpty) return '';

    final extracted = parsedResults.map((r) => r['ParsedText'] ?? '').join('\n');
    log('DEBUG: OCR Extracted Text (${extracted.length} chars): ${extracted.substring(0, extracted.length.clamp(0, 100))}...');
    return extracted;
  }

  // ------------------ TOKENIZER/COMPARISON LOGIC (F1 Score) ------------------
  List<String> tokenize(String text) {
    final cleaned = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-zA-Z0-9áàãâéêíóôõúç\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');

    return cleaned.split(" ").where((w) => w.trim().isNotEmpty).toList();
  }

  final Set<String> stopwords = {};

  List<String> filterMeaningful(List<String> words) {
    return words
        .where((w) =>
    w.length > 2 && !stopwords.contains(w) && !RegExp(r'^\d+$').hasMatch(w))
        .toList();
  }

  Map<String, int> wordCounts(List<String> words) {
    final map = <String, int>{};
    for (var w in words) {
      map[w] = (map[w] ?? 0) + 1;
    }
    return map;
  }

  // UPDATED: Calculates F1 Score with minimal logging
  double scoreChunk(List<String> ocrWordsRaw, List<String> chunkWordsRaw, int chunkIndex, int page) {
    final ocrMeaningful = filterMeaningful(ocrWordsRaw);
    final chunkMeaningful = filterMeaningful(chunkWordsRaw);

    final ocrMap = wordCounts(ocrMeaningful);
    final chunkMap = wordCounts(chunkMeaningful);

    int M_Match = 0;
    ocrMap.forEach((word, count) {
      if (chunkMap.containsKey(word)) {
        M_Match += (count < chunkMap[word]! ? count : chunkMap[word]!);
      }
    });

    int M_OCR = ocrMap.values.fold(0, (sum, count) => sum + count);
    int M_Chunk = chunkMap.values.fold(0, (sum, count) => sum + count);

    if (M_OCR == 0 || M_Chunk == 0) {
      log('SCORE | Index: $chunkIndex (Page $page) | Score: 0.0');
      return 0.0;
    }

    final double R = M_Match / M_OCR;
    final double P = M_Match / M_Chunk;

    if (P + R == 0) {
      log('SCORE | Index: $chunkIndex (Page $page) | Score: 0.0');
      return 0.0;
    }

    final double F1_Score = 2 * (P * R) / (P + R);

    // REDUCED LOGGING: Only output the final score for each chunk
    log('SCORE | Index: $chunkIndex (Page $page) | Score: ${F1_Score.toStringAsFixed(4)}');

    return F1_Score;
  }

  // Returns a ranked list of ScoredChunk objects
  Future<List<ScoredChunk>> compareChunks() async {
    if (extractedText.isEmpty || chunks.isEmpty) {
      log('DEBUG: Comparison skipped. OCR text empty or no chunks.');
      return [];
    }

    log('\n############################################');
    log('DEBUG: Starting Chunk Comparison...');

    List<String> ocrWordsRaw = tokenize(extractedText);

    List<ScoredChunk> scoredList = [];

    for (int i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      List<String> chunkWordsRaw = tokenize(chunk.text);

      // Calculate score and use page/index for minimal log output
      double score = scoreChunk(ocrWordsRaw, chunkWordsRaw, i, chunk.page);

      // Only add chunks with a score greater than 0
      if (score > 0) {
        scoredList.add(ScoredChunk(chunk: chunk, score: score));
      }
    }

    // Sort the list by score in descending order
    scoredList.sort((a, b) => b.score.compareTo(a.score));

    // REDUCED LOGGING: Only log the top 5 results
    log('\nDEBUG: Comparison Finished. Total relevant chunks found: ${scoredList.length}');
    scoredList.take(5).forEach((sc) {
      log('  RANKED RESULT | Rank: ${scoredList.indexOf(sc) + 1}, Score: ${sc.score.toStringAsFixed(4)}, Page: ${sc.chunk.page}');
    });
    log('############################################\n');


    setState(() {});
    return scoredList;
  }


  // ------------------ SHOW PDF NAVIGATOR (NOW ACCEPTS RANKED LIST) ------------------
  void showPdfNavigator(List<ScoredChunk> rankedChunks) {
    if (rankedChunks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No relevant paragraphs found matching the OCR text.')),
      );
      return;
    }
    if ((pdfFile == null && !kIsWeb) || (kIsWeb && pdfBytes == null)) return;

    log('DEBUG: Navigating to ranked chunk list...');

    if (kIsWeb) {
      final url = createPdfUrl(pdfBytes!);
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

  // ------------------ UI (BUTTON UPDATED) ------------------
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
              label: const Text("Pick Image"),
              style: buttonStyle,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(12)),
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                  child: SelectableText(
                    extractedText.isEmpty ? "OCR text will appear here" : extractedText,
                    style: const TextStyle(fontSize: 16, height: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () async {
                if (chunks.isEmpty || extractedText.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please select a PDF and extract text from an image first.')),
                  );
                  return;
                }

                final rankedChunks = await compareChunks();
                showPdfNavigator(rankedChunks);
              },
              icon: const Icon(Icons.compare_arrows),
              label: const Text("Compare & Show Top Chunks"),
              style: buttonStyle.copyWith(
                padding: const MaterialStatePropertyAll(EdgeInsets.symmetric(vertical: 20)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------ NEW CONTAINER FOR RANKED NAVIGATION (MOBILE) ------------------
class TopChunkNavigator extends StatefulWidget {
  final String pdfPath;
  final List<ScoredChunk> rankedChunks;

  const TopChunkNavigator({
    super.key,
    required this.pdfPath,
    required this.rankedChunks,
  });

  @override
  State<TopChunkNavigator> createState() => _TopChunkNavigatorState();
}

class _TopChunkNavigatorState extends State<TopChunkNavigator> {
  int currentRankIndex = 0; // 0-based index for the rankedChunks list

  void _navigateToRank(int index) {
    setState(() {
      currentRankIndex = index.clamp(0, widget.rankedChunks.length - 1);
      log('DEBUG: Navigating to Rank ${currentRankIndex + 1}');
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rankedChunks.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('No Matches Found')),
        body: const Center(child: Text('No relevant paragraphs found in the PDF.')),
      );
    }

    // Get the chunk for the current rank
    final currentChunk = widget.rankedChunks[currentRankIndex];
    // The PdfController uses a 0-based index for initialPage
    final targetPageIndex0Based = currentChunk.chunk.page - 1;

    // Use the existing PDF viewer, passing the target page
    return PdfChunkNavigator(
      key: ValueKey(currentChunk.chunk.page), // Force rebuild of PdfChunkNavigator when rank changes
      pdfPath: widget.pdfPath,
      targetPage: targetPageIndex0Based,
      // Pass the navigation controls into the viewer
      navigationControls: _buildNavigationControls(),
      currentRank: currentRankIndex + 1,
      maxRank: widget.rankedChunks.length,
      currentScore: currentChunk.score,
    );
  }

  Widget _buildNavigationControls() {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
            onPressed: currentRankIndex > 0
                ? () => _navigateToRank(currentRankIndex - 1)
                : null,
          ),
          Text(
            'Rank ${currentRankIndex + 1} / ${widget.rankedChunks.length}',
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios, color: Colors.white),
            onPressed: currentRankIndex < widget.rankedChunks.length - 1
                ? () => _navigateToRank(currentRankIndex + 1)
                : null,
          ),
        ],
      ),
    );
  }
}

// ------------------ NEW CONTAINER FOR RANKED NAVIGATION (WEB) ------------------
class TopChunkNavigatorWeb extends StatefulWidget {
  final String pdfUrl;
  final List<ScoredChunk> rankedChunks;

  const TopChunkNavigatorWeb({
    super.key,
    required this.pdfUrl,
    required this.rankedChunks,
  });

  @override
  State<TopChunkNavigatorWeb> createState() => _TopChunkNavigatorWebState();
}

class _TopChunkNavigatorWebState extends State<TopChunkNavigatorWeb> {
  int currentRankIndex = 0;

  void _navigateToRank(int index) {
    setState(() {
      currentRankIndex = index.clamp(0, widget.rankedChunks.length - 1);
      log('DEBUG: Navigating to Rank ${currentRankIndex + 1}');
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rankedChunks.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('No Matches Found')),
        body: const Center(child: Text('No relevant paragraphs found in the PDF.')),
      );
    }

    final currentChunk = widget.rankedChunks[currentRankIndex];
    final targetPageIndex0Based = currentChunk.chunk.page - 1;

    return PdfChunkNavigatorWeb(
      key: ValueKey(currentChunk.chunk.page), // Force rebuild of PdfChunkNavigatorWeb when rank changes
      pdfUrl: widget.pdfUrl,
      targetPage: targetPageIndex0Based,
      navigationControls: _buildNavigationControls(),
      currentRank: currentRankIndex + 1,
      maxRank: widget.rankedChunks.length,
      currentScore: currentChunk.score,
    );
  }

  Widget _buildNavigationControls() {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
            onPressed: currentRankIndex > 0
                ? () => _navigateToRank(currentRankIndex - 1)
                : null,
          ),
          Text(
            'Rank ${currentRankIndex + 1} / ${widget.rankedChunks.length}',
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios, color: Colors.white),
            onPressed: currentRankIndex < widget.rankedChunks.length - 1
                ? () => _navigateToRank(currentRankIndex + 1)
                : null,
          ),
        ],
      ),
    );
  }
}

// ------------------ MODIFIED PDF VIEWER WITH NAVIGATION CONTROLS SLOT ------------------
// This widget is now more generic and accepts the navigation UI from its parent.

class PdfChunkNavigator extends StatefulWidget {
  final String pdfPath;
  final int targetPage;
  final Widget navigationControls;
  final int currentRank;
  final int maxRank;
  final double currentScore;


  const PdfChunkNavigator({
    super.key,
    required this.pdfPath,
    required this.targetPage,
    required this.navigationControls,
    required this.currentRank,
    required this.maxRank,
    required this.currentScore,
  });

  @override
  State<PdfChunkNavigator> createState() => _PdfChunkNavigatorState();
}

class _PdfChunkNavigatorState extends State<PdfChunkNavigator> {
  late PdfController controller;
  double currentPageFraction = 0.0;
  int totalPages = 0;

  @override
  void initState() {
    super.initState();
    _initController(widget.targetPage);
  }

  void _initController(int targetPage) {
    // Controller is initialized here, but animateToPage is used in didUpdateWidget for navigation
    controller = PdfController(
      document: PdfDocument.openFile(widget.pdfPath),
      initialPage: targetPage,
    );

    currentPageFraction = targetPage.toDouble();

    controller.document.then((doc) {
      if(mounted) {
        setState(() => totalPages = doc.pagesCount);
        // Ensure we jump to the correct page if the document load was async
        controller.animateToPage(targetPage, duration: Duration.zero, curve: Curves.ease);
      }
    });
  }

  // Handle updates when the parent navigator changes the currentRank
  @override
  void didUpdateWidget(covariant PdfChunkNavigator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.targetPage != oldWidget.targetPage) {
      // If the target page changed, just animate to the new page.
      controller.animateToPage(
        widget.targetPage,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      // Update local state to reflect the new page fraction immediately
      setState(() => currentPageFraction = widget.targetPage.toDouble());
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void jumpToFractionPage(double pageFraction) {
    pageFraction = pageFraction.clamp(0.0, (totalPages - 1).toDouble());
    setState(() => currentPageFraction = pageFraction);

    int nearestPage = currentPageFraction.round();
    controller.animateToPage(
      nearestPage,
      duration: const Duration(milliseconds: 50),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    int currentPage = currentPageFraction.round();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("PDF Viewer – Page ${currentPage + 1}/$totalPages"),
            Text(
              'Rank ${widget.currentRank} (Score: ${widget.currentScore.toStringAsFixed(4)})',
              style: const TextStyle(fontSize: 14, color: Colors.black54),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(
                  child: PdfView(
                    controller: controller,
                    scrollDirection: Axis.vertical,
                  ),
                ),
                Container(
                  width: 16,
                  color: Colors.black12,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      double thumbHeight =
                      totalPages > 0 ? constraints.maxHeight / totalPages * 3 : 0;

                      return GestureDetector(
                        onVerticalDragUpdate: (details) {
                          double scaleFactor = (totalPages - 1) / (constraints.maxHeight - thumbHeight);
                          double pageFraction = currentPageFraction + details.delta.dy * scaleFactor;
                          jumpToFractionPage(pageFraction);
                        },
                        child: Stack(
                          children: [
                            Positioned(
                              top: ((currentPageFraction / (totalPages - 1)) *
                                  (constraints.maxHeight - thumbHeight)),
                              left: 2,
                              right: 2,
                              child: Container(
                                height: thumbHeight,
                                decoration: BoxDecoration(
                                  color: Colors.grey[600],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // Navigation controls placed at the bottom
          widget.navigationControls,
        ],
      ),
    );
  }
}

// ------------------ MODIFIED WEB PDF VIEWER WITH NAVIGATION CONTROLS SLOT ------------------
class PdfChunkNavigatorWeb extends StatefulWidget {
  final String pdfUrl;
  final int targetPage;
  final Widget navigationControls;
  final int currentRank;
  final int maxRank;
  final double currentScore;

  const PdfChunkNavigatorWeb({
    super.key,
    required this.pdfUrl,
    required this.targetPage,
    required this.navigationControls,
    required this.currentRank,
    required this.maxRank,
    required this.currentScore,
  });

  @override
  State<PdfChunkNavigatorWeb> createState() => _PdfChunkNavigatorWebState();
}

class _PdfChunkNavigatorWebState extends State<PdfChunkNavigatorWeb> {
  late PdfController controller;
  double currentPageFraction = 0.0;
  int totalPages = 0;
  bool loading = true;

  Uint8List? _pdfBytes; // Cache bytes for controller reuse

  @override
  void initState() {
    super.initState();
    _loadPdf(widget.targetPage);
  }

  Future<void> _loadPdf(int targetPage) async {
    setState(() => loading = true);

    // Only fetch bytes if not already cached
    if (_pdfBytes == null) {
      final response = await http.get(Uri.parse(widget.pdfUrl));
      if (response.statusCode != 200) {
        throw Exception("Failed to load PDF from web");
      }
      _pdfBytes = response.bodyBytes;
    }

    // Initialize controller only if needed
    if (_pdfBytes != null) {
      controller = PdfController(
        document: PdfDocument.openData(_pdfBytes!),
        initialPage: targetPage,
      );
    }

    currentPageFraction = targetPage.toDouble();

    controller.document.then((doc) {
      if(mounted) {
        setState(() {
          totalPages = doc.pagesCount;
          loading = false;
        });
        controller.animateToPage(targetPage, duration: Duration.zero, curve: Curves.ease);
      }
    });
  }

  // Handle updates when the parent navigator changes the currentRank
  @override
  void didUpdateWidget(covariant PdfChunkNavigatorWeb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.targetPage != oldWidget.targetPage) {
      // If the target page changed, just animate to the new page.
      controller.animateToPage(
        widget.targetPage,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      // Update local state to reflect the new page fraction immediately
      setState(() => currentPageFraction = widget.targetPage.toDouble());
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void jumpToFractionPage(double pageFraction) {
    pageFraction = pageFraction.clamp(0.0, (totalPages - 1).toDouble());
    setState(() => currentPageFraction = pageFraction);

    int nearestPage = currentPageFraction.round();
    controller.animateToPage(
      nearestPage,
      duration: const Duration(milliseconds: 50),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    int currentPage = currentPageFraction.round();

    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("PDF Viewer – Page ${currentPage + 1}/$totalPages"),
            Text(
              'Rank ${widget.currentRank} (Score: ${widget.currentScore.toStringAsFixed(4)})',
              style: const TextStyle(fontSize: 14, color: Colors.black54),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(
                  child: PdfView(
                    controller: controller,
                    scrollDirection: Axis.vertical,
                  ),
                ),
                Container(
                  width: 16,
                  color: Colors.black12,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      double thumbHeight =
                      totalPages > 0 ? constraints.maxHeight / totalPages * 3 : 0;

                      return GestureDetector(
                        onVerticalDragUpdate: (details) {
                          double scaleFactor =
                              (totalPages - 1) / (constraints.maxHeight - thumbHeight);
                          double pageFraction = currentPageFraction + details.delta.dy * scaleFactor;
                          jumpToFractionPage(pageFraction);
                        },
                        child: Stack(
                          children: [
                            Positioned(
                              top: ((currentPageFraction / (totalPages - 1)) *
                                  (constraints.maxHeight - thumbHeight)),
                              left: 2,
                              right: 2,
                              child: Container(
                                height: thumbHeight,
                                decoration: BoxDecoration(
                                  color: Colors.grey[600],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // Navigation controls placed at the bottom
          widget.navigationControls,
        ],
      ),
    );
  }
}