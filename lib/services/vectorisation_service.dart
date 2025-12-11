import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'base_vector_service.dart';
import '../js_interop.dart'; // Adjust path if js_interop.dart is elsewhere

const String _modelAssetPath = 'assets/all-MiniLM-L6-v2-quant.tflite'; // Must match pubspec
const String _vocabAssetPath = 'assets/vocab.txt';
const int _vectorDimension = BaseVectorService.vectorDimension;
const int _maxSequenceLength = BaseVectorService.maxSequenceLength;

// Constants
const String _clsToken = '[CLS]';
const String _sepToken = '[SEP]';
const String _unkToken = '[UNK]';
const String _padToken = '[PAD]';
const String _subwordPrefix = '##';

typedef TokenizerOutput = Map<String, List<double>>;

class WebVectorService implements BaseVectorService {
  late Map<String, int> _vocabMap;
  late int _clsId, _sepId, _unkId, _padId;
  bool _isLoaded = false;

  @override
  bool get isLoaded => _isLoaded;

  @override
  Future<void> loadModel() async {
    if (_isLoaded) return;
    try {
      // 1. Load Vocab
      final String vocabString = await rootBundle.loadString(_vocabAssetPath);
      final List<String> vocabList = vocabString.split('\n');
      _vocabMap = {};
      for (int i = 0; i < vocabList.length; i++) {
        final token = vocabList[i].trim();
        if (token.isNotEmpty) _vocabMap[token] = i;
      }
      _clsId = _vocabMap[_clsToken] ?? 1;
      _sepId = _vocabMap[_sepToken] ?? 2;
      _unkId = _vocabMap[_unkToken] ?? 100;
      _padId = _vocabMap[_padToken] ?? 0;

      // 2. Initialize JS Bridge
      // We pass a dummy byte array because the JS side now loads via URL,
      // but the function signature requires an argument.
      final bool success = await loadEmbeddingModel(Uint8List(0));

      if (!success) throw Exception("JS Bridge reported failure loading model.");

      _isLoaded = true;
      print("Web Vector Service Loaded.");
    } catch (e) {
      print("Error loading web model: $e");
      rethrow;
    }
  }

  @override
  Future<List<double>> vectorizeText(String text) async {
    // FIX: Auto-load if not ready, instead of crashing
    if (!_isLoaded) {
      print("⚠️ Model not loaded yet. Attempting to load now...");
      await loadModel();
    }

    // Guard clause for empty text which causes RangeErrors
    if (text.trim().isEmpty) {
      return List<double>.filled(_vectorDimension, 0.0);
    }

    final TokenizerOutput tokens = _wordPieceTokenize(text);

    final Float32List inputIds = Float32List.fromList(tokens['input_ids']!);
    final Float32List attentionMask = Float32List.fromList(tokens['attention_mask']!);
    final Float32List tokenTypeIds = Float32List.fromList(tokens['token_type_ids']!);

    try {
      // FIX: Call the new PUBLIC name 'vectorizeTextInterop'
      final outputData = await vectorizeTextInterop(
        inputIds,
        attentionMask,
        tokenTypeIds,
        _maxSequenceLength,
      );

      // 4. Mean Pooling
      final List<List<double>> tokenEmbeddings = [];
      for (int i = 0; i < _maxSequenceLength; i++) {
        final start = i * _vectorDimension;
        final end = start + _vectorDimension;
        if (end <= outputData.length) {
          tokenEmbeddings.add(outputData.sublist(start, end).toList());
        }
      }

      final maskAsInts = tokens['attention_mask']!.map((e) => e.toInt()).toList();
      return _meanPooling(tokenEmbeddings, maskAsInts);

    } catch (e) {
      print("Inference Error: $e");
      rethrow;
    }
  }

  // --- Helpers ---
  TokenizerOutput _wordPieceTokenize(String text) {
    String normalizedText = text.toLowerCase();
    List<String> words = normalizedText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    List<double> tokenIds = [_clsId.toDouble()];
    List<double> attentionMask = [1.0];

    for (String word in words) {
      if (word.length > 100) {
        tokenIds.add(_unkId.toDouble());
        attentionMask.add(1.0);
        continue;
      }
      int start = 0;
      bool isUnknown = false;
      while (start < word.length && !isUnknown) {
        int end = word.length;
        String subToken = '';
        bool found = false;
        while (start < end) {
          String sub = word.substring(start, end);
          if (start > 0) sub = _subwordPrefix + sub;
          if (_vocabMap.containsKey(sub)) {
            subToken = sub;
            found = true;
            break;
          }
          end--;
        }
        if (found) {
          tokenIds.add(_vocabMap[subToken]!.toDouble());
          attentionMask.add(1.0);
          start = end;
        } else {
          tokenIds.add(_unkId.toDouble());
          attentionMask.add(1.0);
          isUnknown = true;
          break;
        }
      }
    }
    tokenIds.add(_sepId.toDouble());
    attentionMask.add(1.0);

    if (tokenIds.length > _maxSequenceLength) {
      tokenIds = tokenIds.sublist(0, _maxSequenceLength);
      attentionMask = attentionMask.sublist(0, _maxSequenceLength);
      tokenIds[_maxSequenceLength - 1] = _sepId.toDouble();
      attentionMask[_maxSequenceLength - 1] = 1.0;
    }
    while (tokenIds.length < _maxSequenceLength) {
      tokenIds.add(_padId.toDouble());
      attentionMask.add(0.0);
    }
    return {
      'input_ids': tokenIds,
      'attention_mask': attentionMask,
      'token_type_ids': List<double>.filled(_maxSequenceLength, 0.0),
    };
  }

  List<double> _meanPooling(List<List<double>> tokenEmbeddings, List<int> attentionMask) {
    List<double> sumVector = List<double>.filled(_vectorDimension, 0.0);
    double validTokensCount = 0;
    for (int i = 0; i < _maxSequenceLength; i++) {
      if (attentionMask.length > i && attentionMask[i] == 1) {
        for (int j = 0; j < _vectorDimension; j++) {
          sumVector[j] += tokenEmbeddings[i][j];
        }
        validTokensCount++;
      }
    }
    return validTokensCount > 0
        ? sumVector.map((sum) => sum / validTokensCount).toList()
        : List<double>.filled(_vectorDimension, 0.0);
  }

  @override
  void dispose() {}
}