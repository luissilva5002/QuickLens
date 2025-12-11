abstract class BaseVectorService {
  static const int vectorDimension = 384; // The embedding size of MiniLM-L6-v2
  static const int maxSequenceLength = 128; // Standard BERT sequence length

  bool get isLoaded;
  Future<void> loadModel();
  Future<List<double>> vectorizeText(String text);
  void dispose();
}