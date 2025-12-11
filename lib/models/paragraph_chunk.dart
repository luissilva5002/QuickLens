class ParagraphChunk {
  final int page;
  final String text;
  final List<double>? vector; // New field to hold the 384-dim vector

  ParagraphChunk({
    required this.page,
    required this.text,
    this.vector,
  });
}