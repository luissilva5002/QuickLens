import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:path/path.dart' as p;

class PdfQuestionExtractor {

  // --- 1. ENTRY POINTS ---

  /// Extract questions from a file path with optional page range (1-based index)
  static Future<List<Map<String, dynamic>>> extractQuestionsFromFile(
      String path, {
        Function(double)? onProgress,
        int? startPage,
        int? endPage,
      }) async {
    log('DEBUG: Extracting questions from file: $path (Pages: $startPage - $endPage)');
    final bytes = await File(path).readAsBytes();
    final fileName = p.basename(path);
    return _extractQuestionsAndPrint(bytes, fileName,
        onProgress: onProgress, startPage: startPage, endPage: endPage);
  }

  /// Extract questions from bytes with optional page range (1-based index)
  static Future<List<Map<String, dynamic>>> extractQuestionsFromBytes(
      Uint8List bytes,
      String fileName, {
        Function(double)? onProgress,
        int? startPage,
        int? endPage,
      }) async {
    return _extractQuestionsAndPrint(bytes, fileName,
        onProgress: onProgress, startPage: startPage, endPage: endPage);
  }

  // --- 2. ORCHESTRATION ---

  static Future<List<Map<String, dynamic>>> _extractQuestionsAndPrint(
      Uint8List bytes,
      String fileName, {
        Function(double)? onProgress,
        int? startPage,
        int? endPage,
      }) async {

    final results = await _extractQuestionsFromBytesInternal(
        bytes, fileName,
        onProgress: onProgress, startPage: startPage, endPage: endPage);

    // Debug Printing
    final String jsonOutput = const JsonEncoder.withIndent('  ').convert(results);
    log("---------------- EXTRACTED JSON QUESTIONS START ----------------");
    final pattern = RegExp('.{1,800}');
    pattern.allMatches(jsonOutput).forEach((match) => print(match.group(0)));
    log("---------------- EXTRACTED JSON QUESTIONS END ------------------");

    return results;
  }

  static Future<List<Map<String, dynamic>>> _extractQuestionsFromBytesInternal(
      Uint8List bytes,
      String fileName, {
        Function(double)? onProgress,
        int? startPage,
        int? endPage,
      }) async {

    final PdfDocument document = PdfDocument(inputBytes: bytes);
    List<_StyledLine> allLines = [];
    int totalPages = document.pages.count;

    // --- RANGE LOGIC ---
    // User inputs 1-based index (e.g., page 1 to 5). We convert to 0-based index (0 to 4).
    // If null, default to full document.
    int startIdx = (startPage != null && startPage > 0) ? startPage - 1 : 0;
    int endIdx = (endPage != null && endPage > 0) ? endPage - 1 : totalPages - 1;

    // Safety clamps to ensure we don't crash on invalid inputs
    if (startIdx >= totalPages) startIdx = totalPages - 1;
    if (endIdx >= totalPages) endIdx = totalPages - 1;
    if (endIdx < startIdx) endIdx = startIdx;

    int totalPagesToProcess = (endIdx - startIdx) + 1;
    int processedCount = 0;

    log("DEBUG: Processing pages ${startIdx + 1} to ${endIdx + 1}");

    // STEP 1: Extract Lines (Loop restricted to range)
    for (int i = startIdx; i <= endIdx; i++) {
      await Future.delayed(Duration.zero); // Unblock UI

      processedCount++;
      if (onProgress != null) onProgress(processedCount / totalPagesToProcess);

      // Syncfusion extraction specific to this page index
      List<TextLine> textLines = PdfTextExtractor(document)
          .extractTextLines(startPageIndex: i, endPageIndex: i);

      for (var line in textLines) {
        bool isMarkedAnswer = false;
        // Check for bold styling
        for (var word in line.wordCollection) {
          if (word.fontStyle.contains(PdfFontStyle.bold)) {
            isMarkedAnswer = true;
            break;
          }
        }
        allLines.add(_StyledLine(
          text: line.text.trim(), // Trim immediately
          isAnswerMarked: isMarkedAnswer,
          pageIndex: i + 1,
          bounds: line.bounds,
        ));
      }
    }
    document.dispose();

    // STEP 2: Group Blocks
    List<List<_StyledLine>> blocks = _splitIntoBlocks(allLines);

    // STEP 3: Parse Logic
    List<Map<String, dynamic>> results = [];

    for (var block in blocks) {
      // A. Try parsing as True/False Group
      var tfResult = _parseTrueFalseGroup(block, fileName);
      if (tfResult != null) {
        results.add(tfResult);
        continue;
      }

      // B. Try parsing as Multiple Choice
      var mcResult = _parseMultipleChoice(block, fileName);
      if (mcResult != null) {
        results.add(mcResult);
      }
    }

    return results;
  }

  // --- 3. BLOCK SPLITTER (Existing logic) ---

  static List<List<_StyledLine>> _splitIntoBlocks(List<_StyledLine> lines) {
    List<List<_StyledLine>> blocks = [];
    List<_StyledLine> currentBlock = [];

    if (lines.isEmpty) return blocks;
    currentBlock.add(lines[0]);

    for (int i = 1; i < lines.length; i++) {
      var prev = lines[i - 1];
      var curr = lines[i];

      bool newPage = curr.pageIndex != prev.pageIndex;
      double gap = curr.bounds.top - (prev.bounds.top + prev.bounds.height);

      // Adjusted gap logic: 1.5x height is usually a good paragraph break
      bool bigGap = gap > (prev.bounds.height * 1.5);

      if (newPage || bigGap) {
        if (currentBlock.isNotEmpty) blocks.add(List.from(currentBlock));
        currentBlock = [];
      }
      currentBlock.add(curr);
    }
    if (currentBlock.isNotEmpty) blocks.add(currentBlock);
    return blocks;
  }

  // --- 4. PARSING HELPERS ---

  static final RegExp _numberingRegex = RegExp(r"^\s*\d+(?:\.\d+)*\.\s*");
  static final RegExp _tfStartPattern = RegExp(r"^\d+(?:\.\d+)*\.");
  static final RegExp _tfEndPattern = RegExp(r"(?:[\-\–]\s*)?(V|F)$");
  static final RegExp _optionPattern = RegExp(r"^[A-Ea-e][\.\)]\s*(.+)$");

  static String _stripNumbering(String text) {
    return text.replaceFirst(_numberingRegex, "").trim();
  }

  // --- Multi-line True/False Parser ---
  static Map<String, dynamic>? _parseTrueFalseGroup(
      List<_StyledLine> block, String fileName) {

    List<String> questionHeader = [];
    List<Map<String, dynamic>> items = [];

    String? pendingStatement;
    String pendingFullText = "";

    bool foundFirstItem = false;

    for (var line in block) {
      String text = line.text;

      // SCENARIO 1: We are already building a multi-line item
      if (pendingStatement != null) {
        pendingStatement = pendingStatement! + " " + text;
        pendingFullText += " " + text;

        final endMatch = _tfEndPattern.firstMatch(text);
        if (endMatch != null) {
          String vf = endMatch.group(1)!;

          String cleanStatement = pendingStatement!.substring(0, pendingStatement!.length - endMatch.group(0)!.length).trim();
          cleanStatement = _stripNumbering(cleanStatement);

          items.add({
            "statement": cleanStatement,
            "answer": vf == "V",
            "original_text": pendingFullText
          });
          pendingStatement = null;
          pendingFullText = "";
        }
        continue;
      }

      // SCENARIO 2: Check if this is a NEW item starting with a number
      if (_tfStartPattern.hasMatch(text)) {
        foundFirstItem = true;

        final endMatch = _tfEndPattern.firstMatch(text);

        if (endMatch != null) {
          String vf = endMatch.group(1)!;
          String cleanStatement = text.substring(0, text.length - endMatch.group(0)!.length).trim();
          cleanStatement = _stripNumbering(cleanStatement);

          items.add({
            "statement": cleanStatement,
            "answer": vf == "V",
            "original_text": text
          });
        } else {
          pendingStatement = text;
          pendingFullText = text;
        }
      }
      // SCENARIO 3: It's header text
      else if (!foundFirstItem) {
        questionHeader.add(text);
      }
    }

    if (items.isEmpty) return null;

    int page = block.isNotEmpty ? block[0].pageIndex : 1;

    return {
      "type": "true_false_group",
      "question": questionHeader.join(" ").trim(),
      "options": items,
      "location": {
        "file": fileName,
        "page": page,
      }
    };
  }

  // --- Multiple Choice Parser ---
  static Map<String, dynamic>? _parseMultipleChoice(
      List<_StyledLine> block, String fileName) {
    List<String> questionLines = [];
    List<_OptionBuilder> optionBuilders = [];
    bool parsingOptions = false;

    int page = block.isNotEmpty ? block[0].pageIndex : 1;

    for (var line in block) {
      final match = _optionPattern.firstMatch(line.text);

      if (match != null) {
        parsingOptions = true;
        String optionText = match.group(1)!.trim();
        optionBuilders.add(_OptionBuilder(
            text: optionText,
            isMarked: line.isAnswerMarked
        ));
      } else {
        if (parsingOptions) {
          if (optionBuilders.isNotEmpty) {
            var currentOpt = optionBuilders.last;
            currentOpt.text += " " + line.text.trim();
            if (line.isAnswerMarked) currentOpt.isMarked = true;
          }
        } else {
          questionLines.add(_stripNumbering(line.text));
        }
      }
    }

    List<String> finalOptions = [];
    String? correctOption;

    for (var opt in optionBuilders) {
      finalOptions.add(opt.text);
      if (opt.isMarked) {
        correctOption = opt.text;
      }
    }

    if (finalOptions.isEmpty || correctOption == null) {
      return null;
    }

    return {
      "type": "multiple_choice",
      "question": questionLines.join(" ").trim(),
      "options": finalOptions,
      "correct_option": correctOption,
      "location": {
        "file": fileName,
        "page": page,
      }
    };
  }
}

// --- Data Classes ---

class _StyledLine {
  final String text;
  final bool isAnswerMarked;
  final int pageIndex;
  final Rect bounds;
  _StyledLine({required this.text, required this.isAnswerMarked, required this.pageIndex, required this.bounds});
}

class _OptionBuilder {
  String text;
  bool isMarked;
  _OptionBuilder({required this.text, required this.isMarked});
}