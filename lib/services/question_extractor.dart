import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:path/path.dart' as p;

class PdfQuestionExtractor {

  // Changed to Future
  static Future<List<Map<String, dynamic>>> extractQuestionsFromFile(String path, {Function(double)? onProgress}) async {
    log('DEBUG: Extracting questions from file: $path');
    final bytes = await File(path).readAsBytes();
    final fileName = p.basename(path);
    return _extractQuestionsAndPrint(bytes, fileName, onProgress: onProgress);
  }

  // Changed to Future
  static Future<List<Map<String, dynamic>>> extractQuestionsFromBytes(
      Uint8List bytes, String fileName, {Function(double)? onProgress}) async {
    return _extractQuestionsAndPrint(bytes, fileName, onProgress: onProgress);
  }

  static Future<List<Map<String, dynamic>>> _extractQuestionsAndPrint(
      Uint8List bytes, String fileName, {Function(double)? onProgress}) async {

    // Await internal
    final results = await _extractQuestionsFromBytesInternal(bytes, fileName, onProgress: onProgress);

    final String jsonOutput = const JsonEncoder.withIndent('  ').convert(results);

    log("---------------- EXTRACTED JSON QUESTIONS START ----------------");
    final pattern = RegExp('.{1,800}');
    pattern.allMatches(jsonOutput).forEach((match) => print(match.group(0)));
    log("---------------- EXTRACTED JSON QUESTIONS END ------------------");

    return results;
  }

  static Future<List<Map<String, dynamic>>> _extractQuestionsFromBytesInternal(
      Uint8List bytes, String fileName, {Function(double)? onProgress}) async {

    final PdfDocument document = PdfDocument(inputBytes: bytes);
    List<_StyledLine> allLines = [];
    int totalPages = document.pages.count;

    // --- STEP 1: Extract Lines & Detect Styles ---
    for (int i = 0; i < totalPages; i++) {

      // --- CRITICAL FIX: YIELD TO UI THREAD ---
      await Future.delayed(Duration.zero);

      if (onProgress != null) {
        onProgress((i + 1) / totalPages);
      }

      final page = document.pages[i];
      List<TextLine> textLines = PdfTextExtractor(document)
          .extractTextLines(startPageIndex: i, endPageIndex: i);

      for (var line in textLines) {
        bool isMarkedAnswer = false;
        String text = line.text;
        for (var word in line.wordCollection) {
          if (word.fontStyle.contains(PdfFontStyle.bold)) {
            isMarkedAnswer = true;
            break;
          }
        }
        allLines.add(_StyledLine(
          text: text,
          isAnswerMarked: isMarkedAnswer,
          pageIndex: i + 1,
          bounds: line.bounds,
        ));
      }
    }
    document.dispose();

    // --- STEP 2: Group into Blocks ---
    List<List<_StyledLine>> blocks = _splitIntoBlocks(allLines);

    // --- STEP 3: Parse Blocks ---
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

  // --- Parsing Helpers ---

  static final RegExp _numberingRegex = RegExp(r"^\s*\d+(?:\.\d+)*\.\s*");
  static final RegExp _tfItemPattern = RegExp(r"^\d+(?:\.\d+)*\.\s*(.+?)\s+(V|F)$");
  static final RegExp _optionPattern = RegExp(r"^[A-Ea-e][\.\)]\s*(.+)$");

  static String _stripNumbering(String text) {
    return text.replaceFirst(_numberingRegex, "").trim();
  }

  static Map<String, dynamic>? _parseTrueFalseGroup(
      List<_StyledLine> block, String fileName) {

    List<String> questionHeader = [];
    List<Map<String, dynamic>> items = [];
    bool foundFirstItem = false;

    for (var line in block) {
      final match = _tfItemPattern.firstMatch(line.text);

      if (match != null) {
        foundFirstItem = true;
        String statement = match.group(1)!;
        String vf = match.group(2)!;

        items.add({
          "statement": statement.trim(),
          "answer": vf == "V",
          "original_text": line.text
        });
      } else {
        if (!foundFirstItem) {
          questionHeader.add(line.text);
        }
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