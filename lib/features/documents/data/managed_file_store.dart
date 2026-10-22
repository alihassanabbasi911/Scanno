import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path_provider/path_provider.dart';

class StoredDocumentFile {
  const StoredDocumentFile({required this.path, required this.sizeBytes});

  final String path;
  final int sizeBytes;
}

abstract interface class ManagedFileStore {
  Future<StoredDocumentFile> importStream(
    String id,
    String extension,
    Stream<List<int>> bytes,
  );
  Future<String> renameManaged(String path, String newFileName);
  Future<String> stageDelete(String path);
  Future<void> restore(String stagedPath, String originalPath);
  Future<void> deleteStaged(String path);
  Future<bool> export(String path, String fileName, String mimeType);
  Future<String> requireExisting(String path);
  Future<int> fileSize(String path);
}

class LocalManagedFileStore implements ManagedFileStore {
  LocalManagedFileStore({
    Future<Directory> Function()? supportDirectoryProvider,
  }) : _supportDirectoryProvider = supportDirectoryProvider;

  final Future<Directory> Function()? _supportDirectoryProvider;

  Future<Directory> _documentsDirectory() async {
    final supportDirectory =
        await (_supportDirectoryProvider?.call() ??
            getApplicationSupportDirectory());
    final directory = Directory(
      '${supportDirectory.path}${Platform.pathSeparator}documents',
    );
    await directory.create(recursive: true);
    return directory;
  }

  @override
  Future<StoredDocumentFile> importStream(
    String id,
    String extension,
    Stream<List<int>> bytes,
  ) async {
    final directory = await _documentsDirectory();
    final destination = File(
      '${directory.path}${Platform.pathSeparator}$id.$extension',
    );
    final sink = destination.openWrite();
    var closeAttempted = false;
    try {
      await for (final chunk in bytes) {
        sink.add(chunk);
      }
      await sink.flush();
      closeAttempted = true;
      await sink.close();
      return StoredDocumentFile(
        path: destination.path,
        sizeBytes: await destination.length(),
      );
    } on Exception catch (error, stackTrace) {
      Object? closeError;
      if (!closeAttempted) {
        closeAttempted = true;
        try {
          await sink.close();
        } on Exception catch (error) {
          closeError = error;
        }
      }
      if (await destination.exists()) {
        try {
          await destination.delete();
        } on Exception catch (cleanupError) {
          final closeDetail = closeError == null
              ? ''
              : ' Closing the partial file also failed.';
          throw FileSystemException(
            'Import failed and the partial file could not be removed.'
            '$closeDetail ${cleanupError.toString()}',
            destination.path,
          );
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<String> stageDelete(String path) async {
    final source = File(path);
    if (!await source.exists()) {
      throw FileSystemException('The managed document is missing.', path);
    }
    final token = Random.secure().nextInt(1 << 32).toRadixString(16);
    return (await source.rename('$path.$token.deleting')).path;
  }

  @override
  Future<String> renameManaged(String path, String newFileName) async {
    final source = File(path);
    if (!await source.exists()) {
      throw FileSystemException('The managed document is missing.', path);
    }
    final destination = File(
      '${source.parent.path}${Platform.pathSeparator}$newFileName',
    );
    if (destination.path == source.path) return source.path;
    if (await destination.exists()) {
      throw FileSystemException(
        'A managed document with that filename already exists.',
        destination.path,
      );
    }
    return (await source.rename(destination.path)).path;
  }

  @override
  Future<void> restore(String stagedPath, String originalPath) async {
    await File(stagedPath).rename(originalPath);
  }

  @override
  Future<void> deleteStaged(String path) async {
    await File(path).delete();
  }

  @override
  Future<bool> export(String path, String fileName, String mimeType) async {
    final result = await FlutterFileDialog.saveFile(
      params: SaveFileDialogParams(
        sourceFilePath: await requireExisting(path),
        fileName: fileName,
        mimeTypesFilter: [mimeType],
      ),
    );
    return result != null;
  }

  @override
  Future<String> requireExisting(String path) async {
    if (!await File(path).exists()) {
      throw FileSystemException('The managed document is missing.', path);
    }
    return path;
  }

  @override
  Future<int> fileSize(String path) async {
    await requireExisting(path);
    return File(path).length();
  }
}
