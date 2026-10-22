import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/document_format.dart';
import '../domain/incoming_document.dart';

abstract interface class IncomingDocumentBridge {
  Stream<Object?> get intents;
  Future<Map<String, Object?>> copy({
    required String uri,
    required String name,
    required String mimeType,
  });
}

class NativeIncomingDocumentBridge implements IncomingDocumentBridge {
  NativeIncomingDocumentBridge({
    EventChannel eventChannel = const EventChannel('scanno/incoming_documents'),
    MethodChannel methodChannel = const MethodChannel(
      'scanno/incoming_documents/methods',
    ),
  }) : _eventChannel = eventChannel,
       _methodChannel = methodChannel;

  final EventChannel _eventChannel;
  final MethodChannel _methodChannel;

  @override
  Stream<Object?> get intents => _eventChannel.receiveBroadcastStream();

  @override
  Future<Map<String, Object?>> copy({
    required String uri,
    required String name,
    required String mimeType,
  }) async {
    final result = await _methodChannel.invokeMapMethod<String, Object?>(
      'copyIncomingUri',
      {'uri': uri, 'name': name, 'mimeType': mimeType},
    );
    if (result == null || result['success'] != true) {
      throw FileSystemException(
        result?['error'] as String? ??
            'Scanno could not copy the shared document.',
      );
    }
    return result;
  }
}

class IncomingDocumentService {
  IncomingDocumentService(this._bridge);

  final IncomingDocumentBridge _bridge;

  Stream<IncomingDocumentResult> get events =>
      _bridge.intents.asyncMap(_handleIntent);

  Future<IncomingDocumentResult> _handleIntent(Object? value) async {
    try {
      final intent = _asStringMap(value);
      final reportedError = intent['error'] as String?;
      if (reportedError != null) {
        return IncomingDocumentResult.failure(reportedError);
      }
      final uri = intent['uri'] as String?;
      if (uri == null || uri.isEmpty) {
        return const IncomingDocumentResult.failure(
          'The sending app did not provide a readable document.',
        );
      }
      final name = intent['name'] as String? ?? '';
      final mimeType = intent['mimeType'] as String? ?? '';
      final copied = await _bridge.copy(
        uri: uri,
        name: name,
        mimeType: mimeType,
      );
      final path = copied['path'] as String?;
      final copiedName = copied['name'] as String? ?? name;
      final copiedMimeType = copied['mimeType'] as String? ?? mimeType;
      if (path == null || path.isEmpty || copiedName.isEmpty) {
        return const IncomingDocumentResult.failure(
          'Scanno received an incomplete file from the sending app.',
        );
      }
      final file = File(path);
      final size = await file.length();
      if (size == 0) {
        return const IncomingDocumentResult.failure(
          'The selected document is empty.',
        );
      }
      final signature = await file
          .openRead(0, 16)
          .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
      final format = detectIncomingDocumentFormat(
        fileName: copiedName,
        mimeType: copiedMimeType,
        signature: signature,
      );
      final displayName = _withDetectedExtension(copiedName, format);
      return IncomingDocumentResult.success(
        IncomingDocument(
          path: path,
          name: displayName,
          mimeType: format.mimeType,
          sizeBytes: size,
          format: format,
        ),
      );
    } on FileSystemException catch (error) {
      return IncomingDocumentResult.failure(
        error.message.isEmpty
            ? 'Scanno could not read the shared document.'
            : error.message,
      );
    } on FormatException catch (error) {
      return IncomingDocumentResult.failure(error.message);
    } on PlatformException catch (error) {
      return IncomingDocumentResult.failure(
        error.message ?? 'Scanno could not access the shared document.',
      );
    }
  }

  Map<String, Object?> _asStringMap(Object? value) {
    if (value is! Map) {
      throw const FormatException(
        'The sending app provided an invalid document request.',
      );
    }
    return value.map<String, Object?>((key, value) {
      if (key is! String) {
        throw const FormatException(
          'The sending app provided an invalid document request.',
        );
      }
      return MapEntry(key, value);
    });
  }

  String _withDetectedExtension(String name, DocumentFormat format) {
    final extension = name.contains('.')
        ? name.substring(name.lastIndexOf('.') + 1).toLowerCase()
        : '';
    if (DocumentFormat.fromExtension(extension) == format) return name;
    final stem = extension.isEmpty
        ? name
        : name.substring(0, name.lastIndexOf('.'));
    return '$stem.${format.extension}';
  }
}
