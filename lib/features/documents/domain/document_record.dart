enum DocumentSortOrder { newest, oldest, name, largest }

class DocumentRecord {
  const DocumentRecord({
    required this.id,
    required this.name,
    required this.extension,
    required this.mimeType,
    required this.storagePath,
    required this.sizeBytes,
    required this.importedAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String extension;
  final String mimeType;
  final String storagePath;
  final int sizeBytes;
  final DateTime importedAt;
  final DateTime updatedAt;
}

class ImportFailure {
  const ImportFailure(this.fileName, this.message);

  final String fileName;
  final String message;
}

class ImportSummary {
  const ImportSummary({required this.importedCount, required this.failures});

  final int importedCount;
  final List<ImportFailure> failures;
}

class UnsupportedDocumentFormat implements Exception {
  const UnsupportedDocumentFormat(this.extension);

  final String extension;

  @override
  String toString() => 'The .$extension format is not supported.';
}

List<DocumentRecord> filterAndSortDocuments(
  Iterable<DocumentRecord> documents, {
  String query = '',
  DocumentSortOrder sortOrder = DocumentSortOrder.newest,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final filtered = documents.where((document) {
    return normalizedQuery.isEmpty ||
        document.name.toLowerCase().contains(normalizedQuery) ||
        document.extension.toLowerCase().contains(normalizedQuery);
  }).toList();

  filtered.sort((left, right) {
    return switch (sortOrder) {
      DocumentSortOrder.newest => right.importedAt.compareTo(left.importedAt),
      DocumentSortOrder.oldest => left.importedAt.compareTo(right.importedAt),
      DocumentSortOrder.name => left.name.toLowerCase().compareTo(
        right.name.toLowerCase(),
      ),
      DocumentSortOrder.largest => right.sizeBytes.compareTo(left.sizeBytes),
    };
  });
  return filtered;
}

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
