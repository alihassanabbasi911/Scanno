import 'dart:async';
import 'dart:io';

import 'package:docuscan/app/scanno_app.dart';
import 'package:docuscan/features/documents/application/document_providers.dart';
import 'package:docuscan/features/documents/data/document_repository.dart';
import 'package:docuscan/features/documents/domain/document_format.dart';
import 'package:docuscan/features/documents/domain/document_record.dart';
import 'package:docuscan/features/documents/domain/incoming_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('routes each supported format to its intended reader', () {
    expect(documentPreviewKindForExtension('docx'), DocumentPreviewKind.office);
    expect(documentPreviewKindForExtension('xlsx'), DocumentPreviewKind.office);
    expect(documentPreviewKindForExtension('pptx'), DocumentPreviewKind.office);
    expect(documentPreviewKindForExtension('md'), DocumentPreviewKind.markdown);
    expect(
      documentPreviewKindForExtension('unknown'),
      DocumentPreviewKind.unsupported,
    );
  });

  testWidgets('shows an actionable empty library', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentRepositoryProvider.overrideWithValue(
            _FakeDocumentRepository(),
          ),
        ],
        child: const ScannoApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Scanno'), findsOneWidget);
    expect(find.text('Your library is empty'), findsOneWidget);
    expect(find.text('Import a document'), findsOneWidget);
  });

  testWidgets('shows document metadata and filters search results', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentRepositoryProvider.overrideWithValue(
            _FakeDocumentRepository(
              documents: [
                _document('a', 'Invoice.pdf', 'pdf'),
                _document('b', 'Notes.txt', 'txt'),
              ],
            ),
          ),
        ],
        child: const ScannoApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Invoice.pdf'), findsOneWidget);
    expect(find.text('PDF  ·  12.0 KB'), findsOneWidget);
    expect(find.text('Notes.txt'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'invoice');
    await tester.pumpAndSettle();

    expect(find.text('Invoice.pdf'), findsOneWidget);
    expect(find.text('Notes.txt'), findsNothing);
  });

  testWidgets('renaming closes the dialog without reusing its controller', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentRepositoryProvider.overrideWithValue(
            _FakeDocumentRepository(
              documents: [_document('a', 'Invoice.pdf', 'pdf')],
            ),
          ),
        ],
        child: const ScannoApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Document actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'each delete attempt asks for confirmation; cancel preserves it',
    (tester) async {
      final repository = _FakeDocumentRepository(
        documents: [_document('a', 'Invoice.pdf', 'pdf')],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [documentRepositoryProvider.overrideWithValue(repository)],
          child: const ScannoApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Document actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(find.text('Delete from Scanno?'), findsOneWidget);
      expect(find.textContaining('original file in Downloads'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repository.deleteCalls, 0);
      expect(find.text('Invoice.pdf'), findsOneWidget);
      await tester.tap(find.byTooltip('Document actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(find.text('Delete from Scanno?'), findsOneWidget);
      await tester.tap(find.text('Delete from Scanno'));
      await tester.pumpAndSettle();

      expect(repository.deleteCalls, 1);
      expect(find.text('Invoice.pdf'), findsNothing);
    },
  );

  testWidgets('delete confirmation reflects the current renamed name', (
    tester,
  ) async {
    final repository = _FakeDocumentRepository(
      documents: [_document('a', 'Invoice.pdf', 'pdf')],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [documentRepositoryProvider.overrideWithValue(repository)],
        child: const ScannoApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Document actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Updated');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Document actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('“Updated.pdf”'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('shows a helpful error when the managed file is missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentRepositoryProvider.overrideWithValue(
            _MissingDocumentRepository(
              documents: [_document('missing', 'Missing.txt', 'txt')],
            ),
          ),
        ],
        child: const ScannoApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Missing.txt'));
    await tester.pumpAndSettle();

    expect(
      find.text('This document is missing from Scanno’s local storage.'),
      findsOneWidget,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
  });

  testWidgets('shows a loading state before the library is available', (
    tester,
  ) async {
    final pending = Completer<List<DocumentRecord>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentRepositoryProvider.overrideWithValue(
            _PendingDocumentRepository(pending.future),
          ),
        ],
        child: const ScannoApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsWidgets);

    pending.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('Your library is empty'), findsOneWidget);
  });

  testWidgets('shows a retryable error when the library cannot load', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentRepositoryProvider.overrideWithValue(
            _FailingDocumentRepository(),
          ),
        ],
        child: const ScannoApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('The document operation failed. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });
}

DocumentRecord _document(
  String id,
  String name,
  String extension, {
  String? storagePath,
}) {
  return DocumentRecord(
    id: id,
    name: name,
    extension: extension,
    mimeType: 'application/octet-stream',
    storagePath: storagePath ?? '/private/$id.$extension',
    sizeBytes: 12 * 1024,
    importedAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

class _FakeDocumentRepository implements DocumentRepository {
  _FakeDocumentRepository({List<DocumentRecord> documents = const []})
    : documents = List.of(documents);

  final List<DocumentRecord> documents;
  int deleteCalls = 0;

  @override
  Future<List<DocumentRecord>> listDocuments() async => documents;

  @override
  Future<DocumentRecord> getDocument(String id) async =>
      documents.firstWhere((document) => document.id == id);

  @override
  Future<ImportSummary> importSelectedDocuments() async {
    return const ImportSummary(importedCount: 0, failures: []);
  }

  @override
  Future<IncomingImportResult> importIncomingDocument(
    IncomingDocument incoming,
  ) async {
    return IncomingImportResult(
      document: documents.first,
      alreadyInLibrary: true,
    );
  }

  @override
  Future<void> rename(String id, String name) async {
    final index = documents.indexWhere((document) => document.id == id);
    final document = documents[index];
    documents[index] = DocumentRecord(
      id: document.id,
      name: name,
      extension: document.extension,
      mimeType: document.mimeType,
      storagePath: document.storagePath,
      sizeBytes: document.sizeBytes,
      importedAt: document.importedAt,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> delete(String id) async {
    deleteCalls++;
    documents.removeWhere((document) => document.id == id);
  }

  @override
  Future<String> getStoragePath(String id) async => '/private/$id';

  @override
  Future<bool> export(String id) async => true;

  @override
  Future<void> saveAnnotatedPdf(String id, List<int> bytes) async {}
}

class _FailingDocumentRepository extends _FakeDocumentRepository {
  @override
  Future<List<DocumentRecord>> listDocuments() async {
    throw Exception('database unavailable');
  }
}

class _MissingDocumentRepository extends _FakeDocumentRepository {
  _MissingDocumentRepository({required super.documents});

  @override
  Future<DocumentRecord> getDocument(String id) async {
    throw const FileSystemException('Missing managed document');
  }
}

class _PendingDocumentRepository extends _FakeDocumentRepository {
  _PendingDocumentRepository(this.result);

  final Future<List<DocumentRecord>> result;

  @override
  Future<List<DocumentRecord>> listDocuments() => result;
}
