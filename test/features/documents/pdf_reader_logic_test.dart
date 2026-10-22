import 'package:docuscan/features/documents/domain/pdf_reader_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('validates page jumps against one-based page count', () {
    expect(parsePdfPageNumber('5', 42), 5);
    expect(parsePdfPageNumber('1', 42), 1);
    expect(parsePdfPageNumber('42', 42), 42);
    expect(parsePdfPageNumber('0', 42), isNull);
    expect(parsePdfPageNumber('43', 42), isNull);
    expect(parsePdfPageNumber('five', 42), isNull);
    expect(parsePdfPageNumber('1', 0), isNull);
  });

  test('formats match count and current match as one-based', () {
    expect(
      const PdfSearchSummary(matchCount: 0, currentMatchIndex: 0).label,
      '0 matches',
    );
    expect(
      const PdfSearchSummary(matchCount: 8, currentMatchIndex: 0).label,
      '1 of 8',
    );
    expect(
      const PdfSearchSummary(matchCount: 8, currentMatchIndex: 7).label,
      '8 of 8',
    );
  });
}
