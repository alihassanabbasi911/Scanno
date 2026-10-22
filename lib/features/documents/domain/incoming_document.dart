import 'document_format.dart';
import 'document_record.dart';

class IncomingDocument {
  const IncomingDocument({
    required this.path,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    required this.format,
  });

  final String path;
  final String name;
  final String mimeType;
  final int sizeBytes;
  final DocumentFormat format;

  String get extension => name.split('.').last.toLowerCase();
}

class IncomingDocumentResult {
  const IncomingDocumentResult.success(this.document) : error = null;
  const IncomingDocumentResult.failure(this.error) : document = null;

  final IncomingDocument? document;
  final String? error;
}

class IncomingImportResult {
  const IncomingImportResult({
    required this.document,
    required this.alreadyInLibrary,
  });

  final DocumentRecord document;
  final bool alreadyInLibrary;
}
