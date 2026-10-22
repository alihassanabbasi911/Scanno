import 'dart:typed_data';

import 'dart:convert';
import 'dart:io';

import 'package:docuscan/features/documents/data/managed_file_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;
  late LocalManagedFileStore fileStore;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('scanno-test-');
    fileStore = LocalManagedFileStore(
      supportDirectoryProvider: () async => temporaryDirectory,
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'copies an import stream into managed storage without byte buffering',
    () async {
      final stored = await fileStore.importStream(
        'document-1',
        'txt',
        Stream.fromIterable([
          utf8.encode('First part '),
          utf8.encode('second part'),
        ]),
      );

      expect(await File(stored.path).readAsString(), 'First part second part');
      expect(stored.sizeBytes, utf8.encode('First part second part').length);
    },
  );

  test('copies Uint8List chunks emitted by the native file picker', () async {
    final stored = await fileStore.importStream(
      'picked-document',
      'pdf',
      Stream<Uint8List>.fromIterable([
        Uint8List.fromList([37, 80, 68, 70]),
        Uint8List.fromList([45, 49, 46, 55]),
      ]),
    );

    expect(await File(stored.path).readAsBytes(), [
      37,
      80,
      68,
      70,
      45,
      49,
      46,
      55,
    ]);
    expect(stored.sizeBytes, 8);
  });

  test('removes a partial file if a source stream fails', () async {
    await expectLater(
      fileStore.importStream(
        'broken-document',
        'txt',
        Stream<List<int>>.error(
          const FileSystemException('Source unavailable'),
        ),
      ),
      throwsA(isA<FileSystemException>()),
    );

    final managedDirectory = Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}documents',
    );
    expect(await managedDirectory.list().toList(), isEmpty);
  });

  test(
    'renames and deletes only the managed copy, not its source file',
    () async {
      final originalSource = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}source.txt',
      );
      await originalSource.writeAsString('original');
      final managed = await fileStore.importStream(
        'managed-document',
        'txt',
        Stream<List<int>>.value(utf8.encode('managed copy')),
      );

      final renamedPath = await fileStore.renameManaged(
        managed.path,
        'Updated.txt',
      );
      expect(await File(renamedPath).readAsString(), 'managed copy');

      final stagedPath = await fileStore.stageDelete(renamedPath);
      await fileStore.deleteStaged(stagedPath);

      expect(await originalSource.readAsString(), 'original');
      expect(await File(renamedPath).exists(), isFalse);
    },
  );
}
