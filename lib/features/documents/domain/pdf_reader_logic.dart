class PdfSearchSummary {
  const PdfSearchSummary({
    required this.matchCount,
    required this.currentMatchIndex,
  });

  final int matchCount;
  final int currentMatchIndex;

  String get label =>
      matchCount == 0 ? '0 matches' : '${currentMatchIndex + 1} of $matchCount';
}

int? parsePdfPageNumber(String input, int totalPages) {
  final page = int.tryParse(input.trim());
  if (page == null || page < 1 || page > totalPages) return null;
  return page;
}
