import 'dart:math';

import 'package:drift/drift.dart';

import '../domain/pdf_annotation.dart';
import 'document_database.dart';

class PdfAnnotationRepository {
  PdfAnnotationRepository(this._database);

  final DocumentDatabase _database;

  Future<List<PdfAnnotationRecord>> listForDocument(String documentId) async {
    final rows =
        await (_database.select(_database.pdfAnnotations)
              ..where((annotation) => annotation.documentId.equals(documentId))
              ..where((annotation) => annotation.type.equals('comment'))
              ..orderBy([
                (annotation) => OrderingTerm.asc(annotation.pageNumber),
                (annotation) => OrderingTerm.asc(annotation.createdAt),
              ]))
            .get();
    return rows.map(_recordFromRow).toList(growable: false);
  }

  Future<List<PdfAnnotationRecord>> listForPage(
    String documentId,
    int pageNumber,
  ) async {
    final rows =
        await (_database.select(_database.pdfAnnotations)..where(
              (annotation) =>
                  annotation.documentId.equals(documentId) &
                  annotation.pageNumber.equals(pageNumber) &
                  annotation.type.equals('comment'),
            ))
            .get();
    return rows.map(_recordFromRow).toList(growable: false);
  }

  Future<String> addComment({
    required String documentId,
    required int pageNumber,
    required String text,
  }) async {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      throw const PdfAnnotationException('A comment cannot be empty.');
    }
    await _validateDocumentAndPage(documentId, pageNumber);
    final now = DateTime.now();
    final id = _newId();
    await _database
        .into(_database.pdfAnnotations)
        .insert(
          PdfAnnotationsCompanion.insert(
            id: id,
            documentId: documentId,
            pageNumber: pageNumber,
            type: PdfAnnotationKind.comment.name,
            payload: normalizedText,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<void> updateComment(String id, String text) async {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      throw const PdfAnnotationException('A comment cannot be empty.');
    }
    final row = await _getRow(id);
    if (row == null || row.type != PdfAnnotationKind.comment.name) {
      throw const PdfAnnotationException('The comment no longer exists.');
    }
    final now = DateTime.now();
    await (_database.update(
      _database.pdfAnnotations,
    )..where((annotation) => annotation.id.equals(id))).write(
      PdfAnnotationsCompanion(
        payload: Value(normalizedText),
        updatedAt: Value(
          now.isAfter(row.updatedAt.add(const Duration(seconds: 1)))
              ? now
              : row.updatedAt.add(const Duration(seconds: 1)),
        ),
      ),
    );
  }

  Future<void> delete(String id) async {
    final deleted = await (_database.delete(
      _database.pdfAnnotations,
    )..where((annotation) => annotation.id.equals(id))).go();
    if (deleted == 0) {
      throw const PdfAnnotationException('The annotation no longer exists.');
    }
  }

  Future<void> _validateDocumentAndPage(
    String documentId,
    int pageNumber,
  ) async {
    if (pageNumber < 1) {
      throw const PdfAnnotationException('The page number is invalid.');
    }
    final document = await (_database.select(
      _database.documents,
    )..where((row) => row.id.equals(documentId))).getSingleOrNull();
    if (document == null) {
      throw const PdfAnnotationException(
        'The document no longer exists in Scanno.',
      );
    }
  }

  Future<PdfAnnotation?> _getRow(String id) {
    return (_database.select(
      _database.pdfAnnotations,
    )..where((annotation) => annotation.id.equals(id))).getSingleOrNull();
  }

  PdfAnnotationRecord _recordFromRow(PdfAnnotation row) {
    return PdfAnnotationRecord(
      id: row.id,
      documentId: row.documentId,
      pageNumber: row.pageNumber,
      kind: PdfAnnotationKind.comment,
      payload: row.payload,
      colorValue: row.colorValue,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  static String _newId() {
    final random = Random.secure().nextInt(1 << 32).toRadixString(16);
    return '${DateTime.now().microsecondsSinceEpoch}-$random';
  }
}

class PdfAnnotationException implements Exception {
  const PdfAnnotationException(this.message);

  final String message;

  @override
  String toString() => message;
}
