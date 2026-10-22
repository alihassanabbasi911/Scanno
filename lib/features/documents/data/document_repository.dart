import 'dart:math';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import '../domain/document_record.dart';
import '../domain/document_format.dart';
import '../domain/incoming_document.dart';
import 'document_database.dart';
import 'managed_file_store.dart';

const supportedDocumentMimeTypes = <String, String>{
  'bmp': 'image/bmp',
  'csv': 'text/csv',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'gif': 'image/gif',
  'jpeg': 'image/jpeg',
  'jpg': 'image/jpeg',
  'md': 'text/markdown',
  'markdown': 'text/markdown',
  'pdf': 'application/pdf',
  'png': 'image/png',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx':
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'rtf': 'application/rtf',
  'tif': 'image/tiff',
  'tiff': 'image/tiff',
  'txt': 'text/plain',
  'webp': 'image/webp',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
};

abstract interface class DocumentRepository {
  Future<List<DocumentRecord>> listDocuments();
  Future<DocumentRecord> getDocument(String id);
  Future<ImportSummary> importSelectedDocuments();
  Future<IncomingImportResult> importIncomingDocument(
    IncomingDocument incoming,
  );
  Future<void> rename(String id, String name);
  Future<void> delete(String id);
  Future<String> getStoragePath(String id);
  Future<bool> export(String id);
  Future<void> saveAnnotatedPdf(String id, List<int> bytes);
}

class LocalDocumentRepository implements DocumentRepository {
  LocalDocumentRepository(this._database, this._fileStore);

  final DocumentDatabase _database;
  final ManagedFileStore _fileStore;

  @override
  Future<List<DocumentRecord>> listDocuments() async {
    final rows = await _database.select(_database.documents).get();
    return rows
        .map(
          (row) => DocumentRecord(
            id: row.id,
            name: row.name,
            extension: row.extension,
            mimeType: row.mimeType,
            storagePath: row.storagePath,
            sizeBytes: row.sizeBytes,
            importedAt: row.importedAt,
            updatedAt: row.updatedAt,
          ),
        )
        .toList();
  }

  @override
  Future<DocumentRecord> getDocument(String id) async {
    final row = await (_database.select(
      _database.documents,
    )..where((document) => document.id.equals(id))).getSingleOrNull();
    if (row == null) {
      throw const DocumentConsistencyException(
        'The document no longer exists in the library.',
      );
    }
    final currentSize = await _fileStore.fileSize(row.storagePath);
    if (currentSize == 0) {
      throw const DocumentConsistencyException(
        'This document is empty and cannot be opened.',
      );
    }
    return DocumentRecord(
      id: row.id,
      name: row.name,
      extension: row.extension,
      mimeType: row.mimeType,
      storagePath: row.storagePath,
      sizeBytes: row.sizeBytes,
      importedAt: row.importedAt,
      updatedAt: row.updatedAt,
    );
  }

  @override
  Future<ImportSummary> importSelectedDocuments() async {
    final selected = await FilePicker.pickFiles(type: FileType.any);
    var importedCount = 0;
    final failures = <ImportFailure>[];

    for (final file in selected) {
      try {
        await _importFile(file);
        importedCount++;
      } on UnsupportedDocumentFormat catch (error) {
        failures.add(ImportFailure(file.name, error.toString()));
      } on Exception catch (error) {
        failures.add(ImportFailure(file.name, _userMessage(error)));
      }
    }
    return ImportSummary(importedCount: importedCount, failures: failures);
  }

  @override
  Future<IncomingImportResult> importIncomingDocument(
    IncomingDocument incoming,
  ) async {
    final extension = incoming.extension;
    if (DocumentFormat.fromExtension(extension) != incoming.format) {
      throw const UnsupportedDocumentFormat('unknown');
    }
    final source = File(incoming.path);
    if (!await source.exists()) {
      throw const DocumentConsistencyException(
        'The shared document is no longer accessible.',
      );
    }
    final size = await source.length();
    if (size == 0) {
      throw const DocumentConsistencyException('The shared document is empty.');
    }
    final contentHash = await sha256.bind(source.openRead()).first;
    final sameSizeRows = await (_database.select(
      _database.documents,
    )..where((document) => document.sizeBytes.equals(size))).get();
    for (final row in sameSizeRows) {
      final existing = File(row.storagePath);
      if (!await existing.exists()) continue;
      final existingHash = await sha256.bind(existing.openRead()).first;
      if (existingHash == contentHash) {
        return IncomingImportResult(
          document: DocumentRecord(
            id: row.id,
            name: row.name,
            extension: row.extension,
            mimeType: row.mimeType,
            storagePath: row.storagePath,
            sizeBytes: row.sizeBytes,
            importedAt: row.importedAt,
            updatedAt: row.updatedAt,
          ),
          alreadyInLibrary: true,
        );
      }
    }

    final name = incoming.name.replaceAll('\\', '/').split('/').last;
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains(RegExp(r'[/\\:*?"<>|\x00-\x1F]'))) {
      throw const DocumentConsistencyException(
        'The shared document has an invalid filename.',
      );
    }
    final mimeType =
        supportedDocumentMimeTypes[extension] ?? incoming.format.mimeType;
    final id = _newId();
    final stored = await _fileStore.importStream(
      id,
      extension,
      source.openRead(),
    );
    final now = DateTime.now();
    try {
      await _database
          .into(_database.documents)
          .insert(
            DocumentsCompanion.insert(
              id: id,
              name: name,
              extension: extension,
              mimeType: mimeType,
              storagePath: stored.path,
              sizeBytes: stored.sizeBytes,
              importedAt: now,
              updatedAt: now,
            ),
          );
    } on Exception catch (error) {
      try {
        await _fileStore.deleteStaged(stored.path);
      } on Exception catch (cleanupError) {
        throw DocumentConsistencyException(
          'The document could not be added to the library, and its copied '
          'file could not be cleaned up: ${_userMessage(cleanupError)}',
        );
      }
      throw DocumentConsistencyException(
        'The document could not be added to the library: ${_userMessage(error)}',
      );
    }
    return IncomingImportResult(
      document: DocumentRecord(
        id: id,
        name: name,
        extension: extension,
        mimeType: mimeType,
        storagePath: stored.path,
        sizeBytes: stored.sizeBytes,
        importedAt: now,
        updatedAt: now,
      ),
      alreadyInLibrary: false,
    );
  }

  Future<void> _importFile(PlatformFile file) async {
    final extension = (file.extension ?? '').toLowerCase();
    final mimeType = supportedDocumentMimeTypes[extension];
    if (mimeType == null) {
      throw UnsupportedDocumentFormat(extension.isEmpty ? '?' : extension);
    }

    final id = _newId();
    final stored = await _fileStore.importStream(
      id,
      extension,
      file.readAsByteStream(),
    );
    try {
      final now = DateTime.now();
      await _database
          .into(_database.documents)
          .insert(
            DocumentsCompanion.insert(
              id: id,
              name: file.name,
              extension: extension,
              mimeType: mimeType,
              storagePath: stored.path,
              sizeBytes: stored.sizeBytes,
              importedAt: now,
              updatedAt: now,
            ),
          );
    } on Exception catch (error) {
      try {
        await _fileStore.deleteStaged(stored.path);
      } on Exception catch (cleanupError) {
        throw DocumentConsistencyException(
          'The document could not be added to the library, and its copied '
          'file could not be cleaned up: ${_userMessage(cleanupError)}',
        );
      }
      throw DocumentConsistencyException(
        'The document could not be added to the library: ${_userMessage(error)}',
      );
    }
  }

  @override
  Future<void> rename(String id, String name) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty ||
        normalizedName == '.' ||
        normalizedName == '..') {
      throw const DocumentConsistencyException('Enter a valid document name.');
    }
    if (normalizedName.contains(RegExp(r'[/\\:*?"<>|\x00-\x1F]')) ||
        normalizedName.endsWith('.') ||
        normalizedName.endsWith(' ')) {
      throw const DocumentConsistencyException(
        'The name contains invalid filename characters.',
      );
    }
    final row = await _getDocumentRow(id);
    if (row == null) {
      throw const DocumentConsistencyException(
        'The document no longer exists.',
      );
    }
    final requestedExtension = _filenameExtension(normalizedName);
    if (requestedExtension.isNotEmpty &&
        requestedExtension.toLowerCase() != '.${row.extension}') {
      throw const DocumentConsistencyException(
        'The document filename extension cannot be changed.',
      );
    }
    final newName = requestedExtension.isEmpty
        ? '$normalizedName.${row.extension}'
        : normalizedName;
    final allRows = await _database.select(_database.documents).get();
    if (allRows.any(
      (document) =>
          document.id != id &&
          document.name.toLowerCase() == newName.toLowerCase(),
    )) {
      throw const DocumentConsistencyException(
        'Another document already uses that name.',
      );
    }
    final currentPath = row.storagePath;
    final newPath = await _fileStore.renameManaged(currentPath, newName);
    try {
      final changed =
          await (_database.update(
            _database.documents,
          )..where((document) => document.id.equals(id))).write(
            DocumentsCompanion(
              name: Value(newName),
              storagePath: Value(newPath),
              updatedAt: Value(DateTime.now()),
            ),
          );
      if (changed == 0) {
        throw const DocumentConsistencyException(
          'The document no longer exists.',
        );
      }
    } on Exception catch (error) {
      if (newPath != currentPath) {
        try {
          await _fileStore.renameManaged(
            newPath,
            currentPath.substring(_lastPathSeparator(currentPath) + 1),
          );
        } on Exception catch (rollbackError) {
          throw DocumentConsistencyException(
            'The rename failed and the original filename could not be restored: '
            '${_userMessage(rollbackError)}',
          );
        }
      }
      if (error is DocumentConsistencyException) rethrow;
      throw DocumentConsistencyException(
        'The rename failed; the previous name and file were restored: '
        '${_userMessage(error)}',
      );
    }
  }

  Future<Document?> _getDocumentRow(String id) {
    return (_database.select(
      _database.documents,
    )..where((document) => document.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<void> delete(String id) async {
    final row = await (_database.select(
      _database.documents,
    )..where((document) => document.id.equals(id))).getSingleOrNull();
    if (row == null) {
      throw const DocumentConsistencyException(
        'The document no longer exists.',
      );
    }
    final annotations = await (_database.select(
      _database.pdfAnnotations,
    )..where((annotation) => annotation.documentId.equals(id))).get();

    final stagedPath = await _fileStore.stageDelete(row.storagePath);
    try {
      await _database.transaction(() async {
        await (_database.delete(
          _database.pdfAnnotations,
        )..where((annotation) => annotation.documentId.equals(id))).go();
        await (_database.delete(
          _database.documents,
        )..where((document) => document.id.equals(id))).go();
      });
    } on Exception catch (error) {
      try {
        await _fileStore.restore(stagedPath, row.storagePath);
      } on Exception catch (restoreError) {
        throw DocumentConsistencyException(
          'The document could not be removed from the library and its file '
          'could not be restored: ${_userMessage(restoreError)}',
        );
      }
      throw DocumentConsistencyException(
        'The document could not be removed from the library: '
        '${_userMessage(error)}',
      );
    }

    try {
      await _fileStore.deleteStaged(stagedPath);
    } on Exception catch (error) {
      try {
        await _fileStore.restore(stagedPath, row.storagePath);
        await _database.transaction(() async {
          await _database.into(_database.documents).insert(row);
          for (final annotation in annotations) {
            await _database.into(_database.pdfAnnotations).insert(annotation);
          }
        });
      } on Exception catch (restoreError) {
        throw DocumentConsistencyException(
          'The document was removed from the library, but file cleanup failed '
          'and recovery was incomplete: ${_userMessage(restoreError)}',
        );
      }
      throw DocumentConsistencyException(
        'The document could not be deleted. It has been restored: '
        '${_userMessage(error)}',
      );
    }
  }

  @override
  Future<String> getStoragePath(String id) async {
    final row = await (_database.select(
      _database.documents,
    )..where((document) => document.id.equals(id))).getSingleOrNull();
    if (row == null) {
      throw const DocumentConsistencyException(
        'The document no longer exists.',
      );
    }
    return _fileStore.requireExisting(row.storagePath);
  }

  @override
  Future<bool> export(String id) async {
    final row = await (_database.select(
      _database.documents,
    )..where((document) => document.id.equals(id))).getSingleOrNull();
    if (row == null) {
      throw const DocumentConsistencyException(
        'The document no longer exists.',
      );
    }
    return _fileStore.export(row.storagePath, row.name, row.mimeType);
  }

  @override
  Future<void> saveAnnotatedPdf(String id, List<int> bytes) async {
    if (bytes.isEmpty) {
      throw const DocumentConsistencyException(
        'The annotated PDF could not be saved because it was empty.',
      );
    }
    final row = await _getDocumentRow(id);
    if (row == null) {
      throw const DocumentConsistencyException(
        'The document no longer exists.',
      );
    }
    if (row.extension != 'pdf') {
      throw const DocumentConsistencyException(
        'Only PDF documents can be saved with PDF annotations.',
      );
    }

    final replacement = await _fileStore.importStream(
      '$id-saved-${_newId()}',
      'pdf',
      Stream<List<int>>.value(bytes),
    );
    late final String stagedPath;
    try {
      stagedPath = await _fileStore.stageDelete(row.storagePath);
    } on Exception catch (error) {
      await _fileStore.deleteStaged(replacement.path);
      throw DocumentConsistencyException(
        'The existing PDF could not be safely replaced: ${_userMessage(error)}',
      );
    }

    try {
      final changed =
          await (_database.update(
            _database.documents,
          )..where((document) => document.id.equals(id))).write(
            DocumentsCompanion(
              storagePath: Value(replacement.path),
              sizeBytes: Value(replacement.sizeBytes),
              updatedAt: Value(DateTime.now()),
            ),
          );
      if (changed == 0) {
        throw const DocumentConsistencyException(
          'The document no longer exists.',
        );
      }
    } on Exception catch (error) {
      await _fileStore.restore(stagedPath, row.storagePath);
      await _fileStore.deleteStaged(replacement.path);
      if (error is DocumentConsistencyException) rethrow;
      throw DocumentConsistencyException(
        'The annotated PDF could not be saved; the previous file was restored: '
        '${_userMessage(error)}',
      );
    }

    try {
      await _fileStore.deleteStaged(stagedPath);
    } on Exception catch (error) {
      try {
        await (_database.update(
          _database.documents,
        )..where((document) => document.id.equals(id))).write(
          DocumentsCompanion(
            storagePath: Value(row.storagePath),
            sizeBytes: Value(row.sizeBytes),
            updatedAt: Value(DateTime.now()),
          ),
        );
        await _fileStore.restore(stagedPath, row.storagePath);
        await _fileStore.deleteStaged(replacement.path);
      } on Exception catch (rollbackError) {
        throw DocumentConsistencyException(
          'The PDF replacement cleanup failed and rollback was incomplete: '
          '${_userMessage(rollbackError)}',
        );
      }
      throw DocumentConsistencyException(
        'The annotated PDF could not be safely committed; the previous file '
        'was restored: ${_userMessage(error)}',
      );
    }
  }

  static String _newId() {
    final random = Random.secure().nextInt(1 << 32).toRadixString(16);
    return '${DateTime.now().microsecondsSinceEpoch}-$random';
  }
}

class DocumentConsistencyException implements Exception {
  const DocumentConsistencyException(this.message);

  final String message;

  @override
  String toString() => message;
}

String _filenameExtension(String filename) {
  final dotIndex = filename.lastIndexOf('.');
  return dotIndex <= 0 ? '' : filename.substring(dotIndex);
}

int _lastPathSeparator(String path) =>
    max(path.lastIndexOf('/'), path.lastIndexOf(r'\'));

String _userMessage(Exception error) {
  if (error is DocumentConsistencyException) return error.message;
  if (error is FileSystemException) return 'A file operation failed.';
  if (error is PlatformException) return 'The document operation failed.';
  return 'The document operation failed.';
}
