// lib/js_interop.dart
import 'dart:typed_data';
import 'package:js/js.dart';

@JS()
external Future<bool> loadEmbeddingModel(Uint8List modelBytes);

// FIX: Remove the underscore (_) to make this function public!
// We also rename it slightly to be very clear.
@JS('vectorizeText') // This string MUST match the function name in your JS file
external Future<Float32List> vectorizeTextInterop(
    Float32List inputIds,
    Float32List attentionMask,
    Float32List tokenTypeIds,
    int maxSequenceLength,
    );