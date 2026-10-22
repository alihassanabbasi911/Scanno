import 'dart:convert';
import 'dart:typed_data';

enum DocumentFormat {
  pdf('pdf', 'application/pdf'),
  doc('doc', 'application/msword'),
  docx(
    'docx',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  ),
  xls('xls', 'application/vnd.ms-excel'),
  xlsx(
    'xlsx',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  ),
  ppt('ppt', 'application/vnd.ms-powerpoint'),
  pptx(
    'pptx',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  ),
  txt('txt', 'text/plain'),
  csv('csv', 'text/csv'),
  markdown('md', 'text/markdown'),
  imageJpeg('jpg', 'image/jpeg'),
  imagePng('png', 'image/png'),
  imageWebp('webp', 'image/webp'),
  imageBmp('bmp', 'image/bmp'),
  imageGif('gif', 'image/gif'),
  imageTiff('tif', 'image/tiff'),
  rtf('rtf', 'application/rtf');

  const DocumentFormat(this.extension, this.mimeType);

  final String extension;
  final String mimeType;

  static const Map<String, DocumentFormat> _byExtension = {
    'pdf': pdf,
    'doc': doc,
    'docx': docx,
    'xls': xls,
    'xlsx': xlsx,
    'ppt': ppt,
    'pptx': pptx,
    'txt': txt,
    'csv': csv,
    'md': markdown,
    'markdown': markdown,
    'jpg': imageJpeg,
    'jpeg': imageJpeg,
    'png': imagePng,
    'webp': imageWebp,
    'bmp': imageBmp,
    'gif': imageGif,
    'tif': imageTiff,
    'tiff': imageTiff,
    'rtf': rtf,
  };

  static const Map<String, DocumentFormat> _byMimeType = {
    'application/pdf': pdf,
    'application/msword': doc,
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
        docx,
    'application/vnd.ms-excel': xls,
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': xlsx,
    'application/vnd.ms-powerpoint': ppt,
    'application/vnd.openxmlformats-officedocument.presentationml.presentation':
        pptx,
    'text/plain': txt,
    'text/csv': csv,
    'application/csv': csv,
    'text/markdown': markdown,
    'text/x-markdown': markdown,
    'application/rtf': rtf,
    'text/rtf': rtf,
    'image/jpeg': imageJpeg,
    'image/jpg': imageJpeg,
    'image/png': imagePng,
    'image/webp': imageWebp,
    'image/bmp': imageBmp,
    'image/gif': imageGif,
    'image/tiff': imageTiff,
  };

  static DocumentFormat? fromExtension(String? extension) {
    if (extension == null || extension.isEmpty) return null;
    return _byExtension[extension.replaceFirst('.', '').toLowerCase()];
  }

  static DocumentFormat? fromMimeType(String? mimeType) {
    if (mimeType == null || mimeType.isEmpty) return null;
    final normalized = mimeType.split(';').first.trim().toLowerCase();
    return _byMimeType[normalized];
  }

  static DocumentFormat? fromOoxmlEntries(Set<String> entryNames) {
    if (entryNames.contains('word/document.xml')) return docx;
    if (entryNames.contains('xl/workbook.xml')) return xlsx;
    if (entryNames.contains('ppt/presentation.xml')) return pptx;
    return null;
  }
}

enum DocumentPreviewKind { pdf, text, markdown, office, image, unsupported }

DocumentPreviewKind documentPreviewKindForExtension(String extension) =>
    switch (extension.toLowerCase()) {
      'pdf' => DocumentPreviewKind.pdf,
      'txt' => DocumentPreviewKind.text,
      'md' || 'markdown' => DocumentPreviewKind.markdown,
      'csv' ||
      'doc' ||
      'docx' ||
      'ppt' ||
      'pptx' ||
      'rtf' ||
      'xls' ||
      'xlsx' => DocumentPreviewKind.office,
      'bmp' ||
      'gif' ||
      'jpg' ||
      'jpeg' ||
      'png' ||
      'tif' ||
      'tiff' ||
      'webp' => DocumentPreviewKind.image,
      _ => DocumentPreviewKind.unsupported,
    };

DocumentFormat detectIncomingDocumentFormat({
  required String fileName,
  required String? mimeType,
  required List<int> signature,
  DocumentFormat? zipFormat,
}) {
  final extension = fileName.contains('.')
      ? fileName.substring(fileName.lastIndexOf('.') + 1).toLowerCase()
      : '';
  final byExtension = DocumentFormat.fromExtension(extension);
  final byMime = DocumentFormat.fromMimeType(mimeType);
  final declared = byExtension ?? byMime;
  final signatureFormat = _formatFromSignature(signature, declared, zipFormat);

  if (signatureFormat != null && declared != null) {
    final compatible = switch (signatureFormat) {
      DocumentFormat.imageJpeg => declared == DocumentFormat.imageJpeg,
      DocumentFormat.imagePng => declared == DocumentFormat.imagePng,
      DocumentFormat.imageWebp => declared == DocumentFormat.imageWebp,
      DocumentFormat.imageBmp => declared == DocumentFormat.imageBmp,
      DocumentFormat.imageGif => declared == DocumentFormat.imageGif,
      DocumentFormat.imageTiff => declared == DocumentFormat.imageTiff,
      DocumentFormat.pdf => declared == DocumentFormat.pdf,
      DocumentFormat.rtf => declared == DocumentFormat.rtf,
      DocumentFormat.doc ||
      DocumentFormat.xls ||
      DocumentFormat.ppt => declared == signatureFormat,
      DocumentFormat.docx ||
      DocumentFormat.xlsx ||
      DocumentFormat.pptx => declared == signatureFormat,
      _ => true,
    };
    if (!compatible) {
      throw FormatException(
        'The file content does not match its name or reported file type.',
      );
    }
  }

  final format = signatureFormat ?? declared;
  if (format == null) {
    throw const FormatException('This file format is not supported by Scanno.');
  }
  return format;
}

DocumentFormat? _formatFromSignature(
  List<int> bytes,
  DocumentFormat? declared,
  DocumentFormat? zipFormat,
) {
  if (bytes.length >= 4 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46) {
    return DocumentFormat.pdf;
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return DocumentFormat.imageJpeg;
  }
  if (bytes.length >= 8 &&
      const [
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ].asMap().entries.every((entry) => bytes[entry.key] == entry.value)) {
    return DocumentFormat.imagePng;
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
      String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP') {
    return DocumentFormat.imageWebp;
  }
  if (bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4d) {
    return DocumentFormat.imageBmp;
  }
  if (bytes.length >= 6) {
    final signature = String.fromCharCodes(bytes.take(6));
    if (signature == 'GIF87a' || signature == 'GIF89a') {
      return DocumentFormat.imageGif;
    }
  }
  if ((bytes.length >= 4 &&
          bytes[0] == 0x49 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x2a &&
          bytes[3] == 0x00) ||
      (bytes.length >= 4 &&
          bytes[0] == 0x4d &&
          bytes[1] == 0x4d &&
          bytes[2] == 0x00 &&
          bytes[3] == 0x2a)) {
    return DocumentFormat.imageTiff;
  }
  if (bytes.length >= 5 && String.fromCharCodes(bytes.take(5)) == r'{\rtf') {
    return DocumentFormat.rtf;
  }
  if (bytes.length >= 8 &&
      const [
        0xd0,
        0xcf,
        0x11,
        0xe0,
        0xa1,
        0xb1,
        0x1a,
        0xe1,
      ].asMap().entries.every((entry) => bytes[entry.key] == entry.value)) {
    return declared == DocumentFormat.doc ||
            declared == DocumentFormat.xls ||
            declared == DocumentFormat.ppt
        ? declared
        : null;
  }
  if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4b) {
    return zipFormat ??
        (declared == DocumentFormat.docx ||
                declared == DocumentFormat.xlsx ||
                declared == DocumentFormat.pptx
            ? declared
            : null);
  }
  return null;
}

DocumentFormat? detectOfficeOpenXmlFormatFromZipTail(List<int> tail) {
  if (tail.length < 22) return null;
  final bytes = Uint8List.fromList(tail);
  final data = ByteData.sublistView(bytes);
  final searchStart = tail.length > 65557 ? tail.length - 65557 : 0;
  var endOfCentralDirectory = -1;
  for (var offset = tail.length - 22; offset >= searchStart; offset--) {
    if (data.getUint32(offset, Endian.little) == 0x06054b50) {
      endOfCentralDirectory = offset;
      break;
    }
  }
  if (endOfCentralDirectory < 0) return null;

  final entryCount = data.getUint16(endOfCentralDirectory + 10, Endian.little);
  final directorySize = data.getUint32(
    endOfCentralDirectory + 12,
    Endian.little,
  );
  var offset = endOfCentralDirectory - directorySize;
  if (offset < 0) return null;
  final names = <String>{};
  for (var entry = 0; entry < entryCount && entry < 5000; entry++) {
    if (offset + 46 > endOfCentralDirectory ||
        data.getUint32(offset, Endian.little) != 0x02014b50) {
      return null;
    }
    final nameLength = data.getUint16(offset + 28, Endian.little);
    final extraLength = data.getUint16(offset + 30, Endian.little);
    final commentLength = data.getUint16(offset + 32, Endian.little);
    final nameEnd = offset + 46 + nameLength;
    if (nameEnd > endOfCentralDirectory) return null;
    names.add(
      utf8.decode(bytes.sublist(offset + 46, nameEnd), allowMalformed: true),
    );
    offset = nameEnd + extraLength + commentLength;
    if (offset > endOfCentralDirectory) return null;
  }
  return DocumentFormat.fromOoxmlEntries(names);
}
