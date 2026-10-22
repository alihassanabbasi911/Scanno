import 'package:docuscan/features/documents/data/document_database.dart';
import 'package:docuscan/features/documents/data/pdf_annotation_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DocumentDatabase database;
  late PdfAnnotationRepository repository;

  setUp(() {
    database = DocumentDatabase.forTesting(NativeDatabase.memory());
    repository = PdfAnnotationRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('persists, edits, lists, and deletes stable-id page comments', () async {
    await _insertDocument(database);
    final commentId = await repository.addComment(
      documentId: 'doc-stable-id',
      pageNumber: 5,
      text: '  Review this paragraph. ',
    );

    final reopenedRepository = PdfAnnotationRepository(database);
    var annotations = await reopenedRepository.listForDocument('doc-stable-id');
    expect(annotations, hasLength(1));
    expect(annotations.single.id, commentId);
    expect(annotations.single.pageNumber, 5);
    expect(annotations.single.comment, 'Review this paragraph.');

    await repository.updateComment(commentId, 'Updated note');
    annotations = await repository.listForPage('doc-stable-id', 5);
    expect(annotations.single.comment, 'Updated note');
    expect(
      annotations.single.updatedAt.isAfter(annotations.single.createdAt),
      isTrue,
    );

    await repository.delete(commentId);
    expect(await repository.listForDocument('doc-stable-id'), isEmpty);
  });

  test('rejects empty comments and missing documents', () async {
    await _insertDocument(database);
    await expectLater(
      repository.addComment(
        documentId: 'doc-stable-id',
        pageNumber: 1,
        text: '   ',
      ),
      throwsA(isA<PdfAnnotationException>()),
    );
    await expectLater(
      repository.addComment(documentId: 'missing', pageNumber: 1, text: 'Note'),
      throwsA(isA<PdfAnnotationException>()),
    );
  });

  test('ignores legacy pen records while listing comments', () async {
    await _insertDocument(database);
    await database
        .into(database.pdfAnnotations)
        .insert(
          PdfAnnotationsCompanion.insert(
            id: 'legacy-pen',
            documentId: 'doc-stable-id',
            pageNumber: 2,
            type: 'ink',
            payload: 'legacy pen data',
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        );
    final commentId = await repository.addComment(
      documentId: 'doc-stable-id',
      pageNumber: 2,
      text: 'Kept comment',
    );

    final annotations = await repository.listForDocument('doc-stable-id');

    expect(annotations, hasLength(1));
    expect(annotations.single.id, commentId);
    expect(annotations.single.comment, 'Kept comment');
  });
}

Future<void> _insertDocument(DocumentDatabase database) async {
  final now = DateTime(2026, 1, 1);
  await database
      .into(database.documents)
      .insert(
        DocumentsCompanion.insert(
          id: 'doc-stable-id',
          name: 'Document.pdf',
          extension: 'pdf',
          mimeType: 'application/pdf',
          storagePath: '/private/doc-stable-id.pdf',
          sizeBytes: 1024,
          importedAt: now,
          updatedAt: now,
        ),
      );
}
