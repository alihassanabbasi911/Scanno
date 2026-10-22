import 'dart:io';

import 'package:docuscan/features/documents/data/incoming_document_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'scanno-incoming-test-',
    );
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'copies and routes a shared PDF without trusting its extension',
    () async {
      final copiedFile = File('${temporaryDirectory.path}\\cached-file');
      await copiedFile.writeAsBytes('%PDF-1.7'.codeUnits);
      final service = IncomingDocumentService(
        _FakeIncomingDocumentBridge(
          intents: Stream<Object?>.value({
            'uri': 'content://sender/document/1',
            'name': 'scan.unknown',
            'mimeType': 'application/pdf',
          }),
          copied: {
            'path': copiedFile.path,
            'name': 'scan.unknown',
            'mimeType': 'application/pdf',
          },
        ),
      );

      final result = await service.events.single;

      expect(result.error, isNull);
      expect(result.document?.name, 'scan.pdf');
      expect(result.document?.extension, 'pdf');
      expect(result.document?.sizeBytes, greaterThan(0));
    },
  );

  test('returns a visible failure for unsupported shared formats', () async {
    final copiedFile = File('${temporaryDirectory.path}\\unknown-file');
    await copiedFile.writeAsBytes([0x50, 0x4b, 0x03, 0x04]);
    final service = IncomingDocumentService(
      _FakeIncomingDocumentBridge(
        intents: Stream<Object?>.value({
          'uri': 'content://sender/document/2',
          'name': 'archive.zip',
          'mimeType': 'application/zip',
        }),
        copied: {
          'path': copiedFile.path,
          'name': 'archive.zip',
          'mimeType': 'application/zip',
        },
      ),
    );

    final result = await service.events.single;

    expect(result.document, isNull);
    expect(result.error, contains('not supported'));
  });

  test(
    'reports inaccessible sender content instead of a false success',
    () async {
      final service = IncomingDocumentService(
        _FakeIncomingDocumentBridge(
          intents: Stream<Object?>.value({
            'uri': 'content://sender/revoked',
            'name': 'scan.pdf',
            'mimeType': 'application/pdf',
          }),
          error: const FileSystemException('Permission was revoked'),
        ),
      );

      final result = await service.events.single;

      expect(result.document, isNull);
      expect(result.error, 'Permission was revoked');
    },
  );
}

class _FakeIncomingDocumentBridge implements IncomingDocumentBridge {
  _FakeIncomingDocumentBridge({required this.intents, this.copied, this.error});

  @override
  final Stream<Object?> intents;
  final Map<String, Object?>? copied;
  final Exception? error;

  @override
  Future<Map<String, Object?>> copy({
    required String uri,
    required String name,
    required String mimeType,
  }) async {
    if (error != null) throw error!;
    return copied!;
  }
}
