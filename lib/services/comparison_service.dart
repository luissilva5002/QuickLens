import 'dart:developer';
import 'dart:convert'; // Added for JSON pretty-printing
import '../models/paragraph_chunk.dart';
import '../models/scored_chunk.dart';

class ComparisonService {
  // ==============================================================================
  // SHARED: TOKENIZATION
  // ==============================================================================

  List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9áàãâéêíóôõúç\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .split(" ")
        .where((w) => w.trim().isNotEmpty)
        .toList();
  }

  // Expanded stop words list
  final Set<String> _stopwords = {
    'a', 'o', 'e', 'de', 'do', 'da', 'em', 'um', 'uma', 'no', 'na',
    'os', 'as', 'dos', 'das', 'nos', 'nas', 'por', 'para', 'com', 'se', 'que',
    'em', 'na', 'no', 'pela', 'pelo'
  };

  List<String> filterMeaningful(List<String> words) {
    return words
        .where((w) =>
    w.length > 2 &&
        !_stopwords.contains(w) &&
        !RegExp(r'^\d+$').hasMatch(w))
        .toList();
  }

  Set<String> _createBagOfWords(String text) {
    return filterMeaningful(_tokenize(text)).toSet();
  }

  // ==============================================================================
  // METHOD A: Standard Paragraph Comparison (F1 Score)
  // Used when "Infer to JSON" is UNCHECKED
  // ==============================================================================

  Map<String, int> _wordCounts(List<String> words) {
    final map = <String, int>{};
    for (var w in words) {
      map[w] = (map[w] ?? 0) + 1;
    }
    return map;
  }

  double _scoreChunkF1(List<String> ocrWordsRaw, List<String> chunkWordsRaw) {
    final ocrMeaningful = filterMeaningful(ocrWordsRaw);
    final chunkMeaningful = filterMeaningful(chunkWordsRaw);

    final ocrMap = _wordCounts(ocrMeaningful);
    final chunkMap = _wordCounts(chunkMeaningful);

    int mMatch = 0;
    ocrMap.forEach((word, count) {
      if (chunkMap.containsKey(word)) {
        mMatch += (count < chunkMap[word]! ? count : chunkMap[word]!);
      }
    });

    int mOcr = ocrMap.values.fold(0, (sum, count) => sum + count);
    int mChunk = chunkMap.values.fold(0, (sum, count) => sum + count);

    if (mOcr == 0 || mChunk == 0) return 0.0;

    final double R = mMatch / mOcr;
    final double P = mMatch / mChunk;

    if (P + R == 0) return 0.0;

    return 2 * (P * R) / (P + R);
  }

  Future<List<ScoredChunk>> compareChunks(String extractedText, List<ParagraphChunk> chunks) async {
    log('DEBUG: Running Standard F1 Comparison...');
    List<String> ocrWordsRaw = _tokenize(extractedText);
    List<ScoredChunk> scoredList = [];

    for (int i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      double score = _scoreChunkF1(ocrWordsRaw, _tokenize(chunk.text));
      if (score > 0.01) {
        scoredList.add(ScoredChunk(chunk: chunk, score: score));
      }
    }
    scoredList.sort((a, b) => b.score.compareTo(a.score));
    return scoredList;
  }

  // ==============================================================================
  // METHOD B: JSON Question Comparison (Jaccard Similarity)
  // Used when "Infer to JSON" is CHECKED
  // ==============================================================================

  Map<String, dynamic>? findBestMatchingQuestion(
      String ocrText,
      List<Map<String, dynamic>> questions
      ) {
    log('\n############################################');
    log('DEBUG: Running Jaccard JSON Comparison (All Types)...');

    final Set<String> ocrBag = _createBagOfWords(ocrText);
    if (ocrBag.isEmpty) return null;

    List<Map<String, dynamic>> rankedResults = [];

    for (var question in questions) {
      String qType = question['type'] ?? 'unknown';

      // 1. Construct the "Document" text based on Type
      String docText = question['question'] ?? "";

      if (qType == 'multiple_choice') {
        // Options are a List<String>
        if (question['options'] != null) {
          final List<dynamic> opts = question['options'];
          docText += " " + opts.join(" ");
        }
      } else if (qType == 'true_false_group') {
        // Options are a List<Map>
        if (question['options'] != null) {
          final List<dynamic> items = question['options'];
          for (var item in items) {
            docText += " " + (item['statement'] ?? "");
          }
        }
      }

      // 2. Jaccard Calculation
      final Set<String> docBag = _createBagOfWords(docText);

      double score = 0.0;
      if (ocrBag.isNotEmpty && docBag.isNotEmpty) {
        final intersection = ocrBag.intersection(docBag).length;
        final union = ocrBag.union(docBag).length;
        score = union == 0 ? 0.0 : intersection / union;
      }

      rankedResults.add({
        'score': score,
        'data': question,
      });
    }

    // 3. Sort by Score Descending
    rankedResults.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

    if (rankedResults.isEmpty) return null;

    // 4. LOG TOP MATCH
    final bestResult = rankedResults.first;
    final bestScore = bestResult['score'] as double;
    final bestData = bestResult['data'] as Map<String, dynamic>;

    log('DEBUG: --- TOP MATCH DETAILS ---');
    log('DEBUG: Best Score: ${bestScore.toStringAsFixed(4)}');

    // Pretty print
    JsonEncoder encoder = const JsonEncoder.withIndent('  ');
    log('DEBUG: Full JSON Question:\n${encoder.convert(bestData)}');
    log('DEBUG: -----------------------------');

    // Threshold
    if (bestScore > 0.05) {
      return bestData;
    }
    return null;
  }
}