import 'package:docuscan/features/documents/domain/document_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detects common formats from extensions and MIME aliases', () {
    expect(DocumentFormat.fromExtension('JPEG'), DocumentFormat.imageJpeg);
    expect(DocumentFormat.fromExtension('.markdown'), DocumentFormat.markdown);
    expect(
      DocumentFormat.fromMimeType('application/vnd.ms-excel; charset=binary'),
      DocumentFormat.xls,
    );
    expect(
      detectIncomingDocumentFormat(
        fileName: 'document',
        mimeType: 'application/pdf',
        signature: '%PDF-'.codeUnits,
      ),
      DocumentFormat.pdf,
    );
  });

  test('uses binary signatures and rejects conflicting file metadata', () {
    expect(
      detectIncomingDocumentFormat(
        fileName: 'wrong-name.bin',
        mimeType: 'image/jpeg',
        signature: [0xff, 0xd8, 0xff, 0xe0],
      ),
      DocumentFormat.imageJpeg,
    );
    expect(
      () => detectIncomingDocumentFormat(
        fileName: 'document.pdf',
        mimeType: 'application/pdf',
        signature: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
      ),
      throwsFormatException,
    );
  });

  test(
    'identifies Office Open XML containers independently of MIME metadata',
    () {
      final format = DocumentFormat.fromOoxmlEntries({'word/document.xml'});
      expect(format, DocumentFormat.docx);
      expect(
        detectIncomingDocumentFormat(
          fileName: 'shared-file',
          mimeType: 'application/octet-stream',
          signature: [0x50, 0x4b, 0x03, 0x04],
          zipFormat: format,
        ),
        DocumentFormat.docx,
      );
      expect(
        () => detectIncomingDocumentFormat(
          fileName: 'wrong.xlsx',
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          signature: [0x50, 0x4b, 0x03, 0x04],
          zipFormat: DocumentFormat.docx,
        ),
        throwsFormatException,
      );
    },
  );

  test('rejects unknown formats instead of guessing from broad MIME types', () {
    expect(
      () => detectIncomingDocumentFormat(
        fileName: 'archive.zip',
        mimeType: 'application/zip',
        signature: [0x50, 0x4b, 0x03, 0x04],
      ),
      throwsFormatException,
    );
  });
}
