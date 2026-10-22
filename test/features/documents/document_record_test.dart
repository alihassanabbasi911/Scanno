import 'package:docuscan/features/documents/domain/document_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final documents = [
    _document('1', 'zeta.pdf', DateTime(2026, 1, 1), 400),
    _document('2', 'Alpha.txt', DateTime(2026, 1, 3), 120),
    _document('3', 'beta.pdf', DateTime(2026, 1, 2), 900),
  ];

  test('filters by name or extension without case sensitivity', () {
    expect(filterAndSortDocuments(documents, query: 'ALPHA').single.id, '2');
    expect(
      filterAndSortDocuments(documents, query: 'pdf').map((item) => item.id),
      ['3', '1'],
    );
  });

  test('supports each library sort order', () {
    expect(filterAndSortDocuments(documents).map((item) => item.id), [
      '2',
      '3',
      '1',
    ]);
    expect(
      filterAndSortDocuments(
        documents,
        sortOrder: DocumentSortOrder.oldest,
      ).map((item) => item.id),
      ['1', '3', '2'],
    );
    expect(
      filterAndSortDocuments(
        documents,
        sortOrder: DocumentSortOrder.name,
      ).map((item) => item.id),
      ['2', '3', '1'],
    );
    expect(
      filterAndSortDocuments(
        documents,
        sortOrder: DocumentSortOrder.largest,
      ).map((item) => item.id),
      ['3', '1', '2'],
    );
  });

  test('formats sizes with readable units', () {
    expect(formatFileSize(512), '512 B');
    expect(formatFileSize(1536), '1.5 KB');
    expect(formatFileSize(2 * 1024 * 1024), '2.0 MB');
  });
}

DocumentRecord _document(
  String id,
  String name,
  DateTime importedAt,
  int sizeBytes,
) {
  return DocumentRecord(
    id: id,
    name: name,
    extension: name.split('.').last,
    mimeType: 'application/octet-stream',
    storagePath: '/private/$name',
    sizeBytes: sizeBytes,
    importedAt: importedAt,
    updatedAt: importedAt,
  );
}
