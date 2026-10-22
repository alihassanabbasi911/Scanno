import 'dart:async';
import 'dart:io';

import 'package:docuscan/features/documents/data/document_database.dart';
import 'package:docuscan/features/documents/data/document_repository.dart';
import 'package:docuscan/features/documents/data/managed_file_store.dart';
import 'package:docuscan/features/documents/data/pdf_annotation_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DocumentDatabase database;
  late _FakeFileStore fileStore;
  late LocalDocumentRepository repository;

  setUp(() {
    database = DocumentDatabase.forTesting(NativeDatabase.memory());
    fileStore = _FakeFileStore();
    repository = LocalDocumentRepository(database, fileStore);
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'renames metadata and the managed filename while retaining its extension',
    () async {
      await _insertDocument(database);

      await repository.rename('doc-1', 'Renamed');

      final document = (await repository.listDocuments()).single;
      expect(document.name, 'Renamed.pdf');
      expect(document.storagePath, '/private/Renamed.pdf');
      expect(document.extension, 'pdf');
      expect(fileStore.renamedPaths, [('/private/doc-1.pdf', 'Renamed.pdf')]);
    },
  );

  test('rejects invalid extensions and duplicate document names', () async {
    await _insertDocument(database);
    await database
        .into(database.documents)
        .insert(
          DocumentsCompanion.insert(
            id: 'doc-2',
            name: 'Existing.pdf',
            extension: 'pdf',
            mimeType: 'application/pdf',
            storagePath: '/private/doc-2.pdf',
            sizeBytes: 100,
            importedAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
        );

    await expectLater(
      repository.rename('doc-1', 'Changed.docx'),
      throwsA(isA<DocumentConsistencyException>()),
    );
    await expectLater(
      repository.rename('doc-1', 'Existing.pdf'),
      throwsA(isA<DocumentConsistencyException>()),
    );
    await expectLater(
      repository.rename('doc-1', 'bad/name'),
      throwsA(isA<DocumentConsistencyException>()),
    );
    expect((await repository.listDocuments()).first.name, 'Document.pdf');
    expect(fileStore.renamedPaths, isEmpty);
  });

  test('preserves metadata and file path when managed rename fails', () async {
    await _insertDocument(database);
    fileStore.failRename = true;

    await expectLater(
      repository.rename('doc-1', 'Renamed'),
      throwsA(isA<FileSystemException>()),
    );

    final document = (await repository.listDocuments()).single;
    expect(document.name, 'Document.pdf');
    expect(document.storagePath, '/private/doc-1.pdf');
  });

  test('rolls the managed file back when metadata update fails', () async {
    await _insertDocument(database);
    await database.customStatement('''
      CREATE TRIGGER reject_document_rename
      BEFORE UPDATE ON documents
      BEGIN
        SELECT RAISE(ABORT, 'rename rejected');
      END
    ''');

    await expectLater(
      repository.rename('doc-1', 'Renamed'),
      throwsA(isA<DocumentConsistencyException>()),
    );

    final document = (await repository.listDocuments()).single;
    expect(document.name, 'Document.pdf');
    expect(document.storagePath, '/private/doc-1.pdf');
    expect(fileStore.renamedPaths, [
      ('/private/doc-1.pdf', 'Renamed.pdf'),
      ('/private/Renamed.pdf', 'doc-1.pdf'),
    ]);
  });

  test('deletes file and metadata as one recoverable operation', () async {
    await _insertDocument(database);

    await repository.delete('doc-1');

    expect(await repository.listDocuments(), isEmpty);
    expect(fileStore.deletedPaths, ['/private/doc-1.pdf.deleting']);
  });

  test(
    'saves modified PDF bytes to a managed replacement and updates metadata',
    () async {
      await _insertDocument(database);

      await repository.saveAnnotatedPdf('doc-1', [37, 80, 68, 70, 45, 49]);

      final document = (await repository.listDocuments()).single;
      expect(document.storagePath, startsWith('/private/doc-1-saved-'));
      expect(document.sizeBytes, 6);
      expect(fileStore.deletedPaths, ['/private/doc-1.pdf.deleting']);
    },
  );

  test(
    'restores the file and metadata when staged-file cleanup fails',
    () async {
      await _insertDocument(database);
      final annotationRepository = PdfAnnotationRepository(database);
      await annotationRepository.addComment(
        documentId: 'doc-1',
        pageNumber: 3,
        text: 'Do not lose this note',
      );
      fileStore.failDelete = true;

      await expectLater(
        repository.delete('doc-1'),
        throwsA(isA<DocumentConsistencyException>()),
      );

      expect((await repository.listDocuments()).single.name, 'Document.pdf');
      expect(fileStore.restoredPaths, ['/private/doc-1.pdf']);
      expect(
        (await annotationRepository.listForDocument('doc-1')).single.comment,
        'Do not lose this note',
      );
    },
  );

  test('rejects an empty rename', () async {
    await _insertDocument(database);

    await expectLater(
      repository.rename('doc-1', '  '),
      throwsA(isA<DocumentConsistencyException>()),
    );
    expect((await repository.listDocuments()).single.name, 'Document.pdf');
  });

  test('resolves a document by id using its persisted managed path', () async {
    await _insertDocument(database);

    final document = await repository.getDocument('doc-1');

    expect(document.storagePath, '/private/doc-1.pdf');
    expect(fileStore.checkedPaths, ['/private/doc-1.pdf']);
  });

  test('reports a missing managed file when resolving a document', () async {
    await _insertDocument(database);
    fileStore.missingPaths.add('/private/doc-1.pdf');

    await expectLater(
      repository.getDocument('doc-1'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('rejects an empty file when resolving a document', () async {
    await _insertDocument(database);
    fileStore.emptyPaths.add('/private/doc-1.pdf');

    await expectLater(
      repository.getDocument('doc-1'),
      throwsA(
        isA<DocumentConsistencyException>().having(
          (error) => error.message,
          'message',
          'This document is empty and cannot be opened.',
        ),
      ),
    );
  });
}

Future<void> _insertDocument(DocumentDatabase database) async {
  final now = DateTime(2026, 1, 1);
  await database
      .into(database.documents)
      .insert(
        DocumentsCompanion.insert(
          id: 'doc-1',
          name: 'Document.pdf',
          extension: 'pdf',
          mimeType: 'application/pdf',
          storagePath: '/private/doc-1.pdf',
          sizeBytes: 4096,
          importedAt: now,
          updatedAt: now,
        ),
      );
}

class _FakeFileStore implements ManagedFileStore {
  bool failDelete = false;
  bool failRename = false;
  final deletedPaths = <String>[];
  final restoredPaths = <String>[];
  final checkedPaths = <String>[];
  final renamedPaths = <(String, String)>[];
  final missingPaths = <String>{};
  final emptyPaths = <String>{};

  @override
  Future<String> stageDelete(String path) async => '$path.deleting';

  @override
  Future<void> restore(String stagedPath, String originalPath) async {
    restoredPaths.add(originalPath);
  }

  @override
  Future<void> deleteStaged(String path) async {
    if (failDelete) throw const FileSystemException('Disk failure');
    deletedPaths.add(path);
  }

  @override
  Future<StoredDocumentFile> importStream(
    String id,
    String extension,
    Stream<List<int>> bytes,
  ) async => StoredDocumentFile(
    path: '/private/$id.$extension',
    sizeBytes: await bytes.fold<int>(0, (total, chunk) => total + chunk.length),
  );

  @override
  Future<String> renameManaged(String path, String newFileName) async {
    if (failRename) throw const FileSystemException('Rename failure');
    renamedPaths.add((path, newFileName));
    return path.replaceFirst(RegExp(r'[^\\/]+$'), newFileName);
  }

  @override
  Future<bool> export(String path, String fileName, String mimeType) async {
    return true;
  }

  @override
  Future<String> requireExisting(String path) async {
    checkedPaths.add(path);
    if (missingPaths.contains(path)) {
      throw FileSystemException('Missing managed file', path);
    }
    return path;
  }

  @override
  Future<int> fileSize(String path) async {
    await requireExisting(path);
    return emptyPaths.contains(path) ? 0 : 4096;
  }
}
