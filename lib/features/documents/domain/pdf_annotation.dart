enum PdfAnnotationKind { comment }

class PdfAnnotationRecord {
  const PdfAnnotationRecord({
    required this.id,
    required this.documentId,
    required this.pageNumber,
    required this.kind,
    required this.payload,
    required this.colorValue,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String documentId;
  final int pageNumber;
  final PdfAnnotationKind kind;
  final String payload;
  final int colorValue;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get comment => payload;
}
