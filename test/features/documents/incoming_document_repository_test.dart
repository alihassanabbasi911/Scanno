import 'dart:io';

import 'package:docuscan/features/documents/data/document_database.dart';
import 'package:docuscan/features/documents/data/document_repository.dart';
import 'package:docuscan/features/documents/data/managed_file_store.dart';
import 'package:docuscan/features/documents/domain/document_format.dart';
import 'package:docuscan/features/documents/domain/incoming_document.dart';
import 'package:docuscan/features/documents/domain/document_record.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;
  late DocumentDatabase database;
  late LocalDocumentRepository repository;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'scanno-incoming-repository-test-',
    );
    database = DocumentDatabase.forTesting(NativeDatabase.memory());
    repository = LocalDocumentRepository(
      database,
      LocalManagedFileStore(
        supportDirectoryProvider: () async => temporaryDirectory,
      ),
    );
  });

  tearDown(() async {
    await database.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'imports shared bytes to managed storage once and preserves source',
    () async {
      final originalBytes = '%PDF-1.7 test document'.codeUnits;
      final source = File('${temporaryDirectory.path}\\incoming.pdf');
      await source.writeAsBytes(originalBytes);
      final incoming = IncomingDocument(
        path: source.path,
        name: 'source-name.pdf',
        mimeType: 'application/pdf',
        sizeBytes: originalBytes.length,
        format: DocumentFormat.pdf,
      );

      final firstImport = await repository.importIncomingDocument(incoming);
      final repeatedImport = await repository.importIncomingDocument(
        IncomingDocument(
          path: source.path,
          name: 'a-different-display-name.pdf',
          mimeType: 'application/pdf',
          sizeBytes: originalBytes.length,
          format: DocumentFormat.pdf,
        ),
      );
      final records = await repository.listDocuments();

      expect(firstImport.alreadyInLibrary, isFalse);
      expect(repeatedImport.alreadyInLibrary, isTrue);
      expect(repeatedImport.document.id, firstImport.document.id);
      expect(records, hasLength(1));
      expect(records.single.storagePath, isNot(source.path));
      expect(
        await File(records.single.storagePath).readAsBytes(),
        originalBytes,
      );
      expect(await source.readAsBytes(), originalBytes);
    },
  );

  test(
    'rejects imported metadata that does not match a supported format',
    () async {
      final source = File('${temporaryDirectory.path}\\unsupported.zip');
      await source.writeAsBytes([1, 2, 3]);

      await expectLater(
        repository.importIncomingDocument(
          IncomingDocument(
            path: source.path,
            name: 'unsupported.zip',
            mimeType: 'application/zip',
            sizeBytes: 3,
            format: DocumentFormat.pdf,
          ),
        ),
        throwsA(isA<UnsupportedDocumentFormat>()),
      );
      expect(await repository.listDocuments(), isEmpty);
    },
  );
}
