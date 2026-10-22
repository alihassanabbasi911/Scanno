import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:offline_document_viewer/offline_document_viewer.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../application/document_providers.dart';
import '../data/document_repository.dart';
import '../domain/document_format.dart';
import '../domain/document_record.dart';
import '../domain/incoming_document.dart';
import '../domain/pdf_reader_logic.dart';

const _maxTextPreviewBytes = 1024 * 1024;

class DocumentReaderPage extends ConsumerWidget {
  const DocumentReaderPage({this.documentId, this.incoming, super.key})
    : assert((documentId == null) != (incoming == null));

  final String? documentId;
  final IncomingDocument? incoming;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final document = incoming == null
        ? ref.watch(documentByIdProvider(documentId!))
        : AsyncValue.data(_recordForIncoming(incoming!));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          document.hasValue ? document.requireValue.name : 'Document',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: incoming == null
            ? null
            : [_IncomingImportAction(incoming: incoming!)],
      ),
      body: document.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            _ReaderMessage(message: _documentLoadError(error)),
        data: (record) => incoming == null
            ? _DocumentPreview(record: record, allowPdfAnnotations: true)
            : Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    child: const Text(
                      'Opened from another app. This temporary copy is not yet in your Scanno library.',
                    ),
                  ),
                  Expanded(
                    child: _DocumentPreview(
                      record: record,
                      allowPdfAnnotations: false,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _DocumentPreview extends StatelessWidget {
  const _DocumentPreview({
    required this.record,
    required this.allowPdfAnnotations,
  });

  final DocumentRecord record;
  final bool allowPdfAnnotations;

  @override
  Widget build(BuildContext context) {
    return switch (documentPreviewKindForExtension(record.extension)) {
      DocumentPreviewKind.pdf => _PdfPreview(
        record: record,
        allowAnnotations: allowPdfAnnotations,
      ),
      DocumentPreviewKind.text => _TextPreview(path: record.storagePath),
      DocumentPreviewKind.markdown => _TextPreview(
        path: record.storagePath,
        markdown: true,
      ),
      DocumentPreviewKind.office => _OfficePreview(record: record),
      DocumentPreviewKind.image => _ImagePreview(path: record.storagePath),
      DocumentPreviewKind.unsupported => _ReaderMessage(
        message:
            'Preview for .${record.extension} files is not available. '
            'Open it with an app that supports this file type.',
      ),
    };
  }
}

DocumentRecord _recordForIncoming(IncomingDocument incoming) {
  final now = DateTime.now();
  return DocumentRecord(
    id: 'incoming-${incoming.path.hashCode}',
    name: incoming.name,
    extension: incoming.extension,
    mimeType: incoming.mimeType,
    storagePath: incoming.path,
    sizeBytes: incoming.sizeBytes,
    importedAt: now,
    updatedAt: now,
  );
}

class _IncomingImportAction extends ConsumerStatefulWidget {
  const _IncomingImportAction({required this.incoming});

  final IncomingDocument incoming;

  @override
  ConsumerState<_IncomingImportAction> createState() =>
      _IncomingImportActionState();
}

class _IncomingImportActionState extends ConsumerState<_IncomingImportAction> {
  bool _isImporting = false;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: TextButton.icon(
      onPressed: _isImporting ? null : _import,
      icon: _isImporting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.download_outlined),
      label: Text(_isImporting ? 'Importing' : 'Import'),
    ),
  );

  Future<void> _import() async {
    setState(() => _isImporting = true);
    try {
      final result = await ref
          .read(documentLibraryProvider.notifier)
          .importIncomingDocument(widget.incoming);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.alreadyInLibrary
                ? 'This document is already in Scanno’s library.'
                : 'Document imported into Scanno’s library.',
          ),
        ),
      );
      context.go('/documents/${result.document.id}');
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('The document could not be imported: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }
}

class IncomingDocumentErrorPage extends StatelessWidget {
  const IncomingDocumentErrorPage({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Unable to open document')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file_outlined, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go('/'),
              child: const Text('Go to Scanno library'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _OfficePreview extends StatefulWidget {
  const _OfficePreview({required this.record});

  final DocumentRecord record;

  @override
  State<_OfficePreview> createState() => _OfficePreviewState();
}

class _OfficePreviewState extends State<_OfficePreview> {
  late Future<int> _fileSize;

  @override
  void initState() {
    super.initState();
    _fileSize = File(widget.record.storagePath).length();
  }

  @override
  void didUpdateWidget(covariant _OfficePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.record.storagePath != widget.record.storagePath) {
      _fileSize = File(widget.record.storagePath).length();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<int>(
    future: _fileSize,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const _ReaderMessage(
          message:
              'This document is no longer accessible from Scanno’s local storage.',
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.data! > DocumentPreflight.maxBytes) {
        return const _ReaderMessage(
          message:
              'This file is larger than Scanno can safely preview on this device. '
              'Open it with another document app.',
        );
      }
      final fidelityNote = switch (widget.record.extension.toLowerCase()) {
        'doc' || 'ppt' =>
          'Text-only preview. Original page layout, images, and formatting are not rendered.',
        'xls' => 'Legacy spreadsheet values are shown without cell styling.',
        _ => null,
      };
      return Column(
        children: [
          if (fidelityNote != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Text(fidelityNote),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Read-only preview. Editing is not supported.'),
            ),
          ),
          Expanded(
            child: DocumentView(
              source: DocumentSource.file(
                widget.record.storagePath,
                name: widget.record.name,
              ),
              placeholderBuilder: (_) =>
                  const Center(child: CircularProgressIndicator()),
              errorBuilder: (context, failure) =>
                  _ReaderMessage(message: _officeFailureMessage(failure)),
            ),
          ),
        ],
      );
    },
  );
}

String _officeFailureMessage(DocumentFailure failure) => switch (failure) {
  CorruptDocumentFailure() =>
    'This Office document is damaged or incomplete and could not be previewed.',
  EncryptedDocumentFailure() =>
    'This document is password-protected or uses an unsupported legacy format.',
  TooLargeFailure() =>
    'This document is too large to preview safely on this device.',
  SuspiciousArchiveFailure() =>
    'Scanno rejected this document because its archive structure is unsafe.',
  RendererFailure() =>
    'The document renderer could not finish. Try opening the file in another app.',
  NotFoundFailure() =>
    'This document is no longer accessible from Scanno’s local storage.',
  UnsupportedFormatFailure() =>
    'This file format cannot be previewed in Scanno.',
  UnexpectedFailure() => 'This document could not be previewed.',
};

class _PdfPreview extends ConsumerStatefulWidget {
  const _PdfPreview({required this.record, required this.allowAnnotations});

  final DocumentRecord record;
  final bool allowAnnotations;

  @override
  ConsumerState<_PdfPreview> createState() => _PdfPreviewState();
}

class _PdfPreviewState extends ConsumerState<_PdfPreview> {
  final _pageInputController = TextEditingController();
  final _searchController = TextEditingController();
  late final PdfViewerController _controller;
  Timer? _searchDebounce;
  PdfTextSearchResult? _searchResult;
  int _currentPage = 1;
  int _totalPages = 0;
  int _highlightColor = 0xFFFFEB3B;
  bool _showSearch = false;
  bool _isSaving = false;
  bool _hasUnsavedPdfAnnotations = false;
  String? _pdfError;

  @override
  void initState() {
    super.initState();
    _controller = PdfViewerController();
    _controller.annotationSettings.author = 'Scanno';
    _applyMarkupColor(Color(_highlightColor));
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchResult?.dispose();
    _searchController.dispose();
    _pageInputController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: !_hasUnsavedPdfAnnotations,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _hasUnsavedPdfAnnotations) {
          unawaited(_confirmLeavingWithUnsavedChanges());
        }
      },
      child: Column(
        children: [
          _buildPageControls(),
          if (_showSearch) _buildSearchControls(),
          if (_pdfError != null)
            _ReaderMessage(message: _pdfError!)
          else
            Expanded(
              child: Stack(
                children: [
                  SfPdfViewer.file(
                    File(widget.record.storagePath),
                    key: ValueKey(widget.record.storagePath),
                    controller: _controller,
                    enableTextSelection: true,
                    canShowPaginationDialog: false,
                    onDocumentLoaded: _onDocumentLoaded,
                    onDocumentLoadFailed: _onDocumentLoadFailed,
                    onPageChanged: (details) {
                      setState(() => _currentPage = details.newPageNumber);
                    },
                    onAnnotationAdded: _onPdfAnnotationChanged,
                    onAnnotationEdited: _onPdfAnnotationChanged,
                    onAnnotationRemoved: _onPdfAnnotationChanged,
                    currentSearchTextHighlightColor: const Color(0x6600AEEF),
                    otherSearchTextHighlightColor: const Color(0x44FFEB3B),
                  ),
                  if (_isSaving)
                    const Align(
                      alignment: Alignment.topCenter,
                      child: LinearProgressIndicator(),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPageControls() {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Previous page',
                onPressed: _totalPages > 0 && _currentPage > 1
                    ? () => _navigatePage(_currentPage - 1)
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              TextButton(
                onPressed: _totalPages > 0 ? _showPageJumpDialog : null,
                child: Text(
                  _totalPages == 0 ? '-- / --' : '$_currentPage / $_totalPages',
                  key: const ValueKey('pdf-page-indicator'),
                ),
              ),
              IconButton(
                tooltip: 'Next page',
                onPressed: _totalPages > 0 && _currentPage < _totalPages
                    ? () => _navigatePage(_currentPage + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: _showSearch ? 'Close PDF search' : 'Search PDF text',
                onPressed: () {
                  setState(() => _showSearch = !_showSearch);
                  if (!_showSearch) _clearSearch();
                },
                icon: Icon(_showSearch ? Icons.search_off : Icons.search),
              ),
              PopupMenuButton<String>(
                tooltip: 'PDF tools',
                enabled:
                    _totalPages > 0 && !_isSaving && widget.allowAnnotations,
                onSelected: _onPdfToolSelected,
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'highlight',
                    child: Text('Highlight text'),
                  ),
                  const PopupMenuItem(
                    value: 'underline',
                    child: Text('Underline text'),
                  ),
                  const PopupMenuItem(
                    value: 'strikethrough',
                    child: Text('Strikethrough text'),
                  ),
                  const PopupMenuItem(
                    value: 'comment',
                    child: Text('Add page comment'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'yellow',
                    child: Text('Markup color: yellow'),
                  ),
                  const PopupMenuItem(
                    value: 'teal',
                    child: Text('Markup color: teal'),
                  ),
                  const PopupMenuItem(
                    value: 'blue',
                    child: Text('Markup color: blue'),
                  ),
                  const PopupMenuItem(
                    value: 'pink',
                    child: Text('Markup color: pink'),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'save',
                    enabled: _hasUnsavedPdfAnnotations,
                    child: Text('Save annotations to Scanno'),
                  ),
                ],
                icon: const Icon(Icons.more_vert),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchControls() {
    final summary = PdfSearchSummary(
      matchCount: _searchResult?.totalInstanceCount ?? 0,
      currentMatchIndex: math.max(
        0,
        (_searchResult?.currentInstanceIndex ?? 1) - 1,
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('pdf-search-input'),
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: 'Search text in this PDF',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: _clearSearch,
                            icon: const Icon(Icons.clear),
                          ),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(summary.label, key: const ValueKey('pdf-search-count')),
              IconButton(
                tooltip: 'Previous match',
                onPressed: summary.matchCount > 0
                    ? _searchResult?.previousInstance
                    : null,
                icon: const Icon(Icons.keyboard_arrow_up),
              ),
              IconButton(
                tooltip: 'Next match',
                onPressed: summary.matchCount > 0
                    ? _searchResult?.nextInstance
                    : null,
                icon: const Icon(Icons.keyboard_arrow_down),
              ),
            ],
          ),
          const Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                'Search finds embedded PDF text; image-only scans require OCR, which Scanno does not provide.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onPdfToolSelected(String action) {
    switch (action) {
      case 'highlight':
        _setAnnotationMode(PdfAnnotationMode.highlight);
      case 'underline':
        _setAnnotationMode(PdfAnnotationMode.underline);
      case 'strikethrough':
        _setAnnotationMode(PdfAnnotationMode.strikethrough);
      case 'comment':
        _setAnnotationMode(
          _controller.annotationMode == PdfAnnotationMode.stickyNote
              ? PdfAnnotationMode.none
              : PdfAnnotationMode.stickyNote,
        );
        if (_controller.annotationMode == PdfAnnotationMode.stickyNote) {
          _showMessage('Tap a location on the PDF page to add a comment.');
        }
      case 'yellow':
        _setMarkupColor(0xFFFFEB3B);
      case 'teal':
        _setMarkupColor(0xFF80CBC4);
      case 'blue':
        _setMarkupColor(0xFF90CAF9);
      case 'pink':
        _setMarkupColor(0xFFF48FB1);
      case 'save':
        unawaited(_savePdfAnnotations());
    }
  }

  void _setAnnotationMode(PdfAnnotationMode mode) {
    _controller.annotationMode = mode;
  }

  void _setMarkupColor(int value) {
    setState(() {
      _highlightColor = value;
      _applyMarkupColor(Color(value));
    });
  }

  void _applyMarkupColor(Color color) {
    _controller.annotationSettings.highlight.color = color;
    _controller.annotationSettings.underline.color = color;
    _controller.annotationSettings.strikethrough.color = color;
    _controller.annotationSettings.squiggly.color = color;
  }

  void _navigatePage(int pageNumber) {
    if (pageNumber < 1 || pageNumber > _totalPages) return;
    _controller.jumpToPage(pageNumber);
  }

  void _onDocumentLoaded(PdfDocumentLoadedDetails details) {
    final count = _controller.pageCount;
    setState(() {
      _totalPages = count;
      _currentPage = _controller.pageNumber;
      _pdfError = count == 0 ? 'This PDF contains no pages.' : null;
    });
  }

  void _onDocumentLoadFailed(PdfDocumentLoadFailedDetails details) {
    setState(() {
      _pdfError = 'This PDF could not be opened: ${details.description}';
      _totalPages = 0;
    });
  }

  void _onPdfAnnotationChanged(Annotation annotation) {
    setState(() => _hasUnsavedPdfAnnotations = true);
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().isEmpty) {
      _clearSearch();
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _searchResult?.removeListener(_refreshSearch);
      _searchResult?.clear();
      final result = _controller.searchText(query.trim());
      result.addListener(_refreshSearch);
      setState(() => _searchResult = result);
    });
  }

  void _refreshSearch() {
    if (mounted) setState(() {});
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    _searchResult?.removeListener(_refreshSearch);
    _searchResult?.clear();
    setState(() => _searchResult = null);
  }

  Future<void> _showPageJumpDialog() async {
    final page = await showDialog<int>(
      context: context,
      builder: (context) =>
          _PageJumpDialog(initialPage: _currentPage, totalPages: _totalPages),
    );
    if (page != null && mounted) _navigatePage(page);
  }

  Future<bool> _savePdfAnnotations() async {
    if (_isSaving) return false;
    setState(() => _isSaving = true);
    try {
      final bytes = await _controller.saveDocument();
      if (bytes.length < 5 || String.fromCharCodes(bytes.take(5)) != '%PDF-') {
        throw const FormatException(
          'The PDF viewer returned invalid document data.',
        );
      }
      await ref
          .read(documentRepositoryProvider)
          .saveAnnotatedPdf(widget.record.id, bytes);
      if (!mounted) return false;
      ref.invalidate(documentByIdProvider(widget.record.id));
      setState(() {
        _hasUnsavedPdfAnnotations = false;
      });
      _showMessage('PDF annotations saved to Scanno’s managed copy.');
      return true;
    } on Exception catch (error) {
      if (mounted) _showMessage('The PDF could not be saved: $error');
      return false;
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmLeavingWithUnsavedChanges() async {
    final action = await showDialog<_LeaveAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved PDF annotations'),
        content: const Text(
          'Save the text markup to Scanno’s managed PDF before closing?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _LeaveAction.cancel),
            child: const Text('Keep reading'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _LeaveAction.discard),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _LeaveAction.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == _LeaveAction.discard) {
      Navigator.of(context).pop();
    } else if (action == _LeaveAction.save &&
        await _savePdfAnnotations() &&
        mounted) {
      Navigator.of(context).pop();
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

enum _LeaveAction { cancel, discard, save }

class _PageJumpDialog extends StatefulWidget {
  const _PageJumpDialog({required this.initialPage, required this.totalPages});

  final int initialPage;
  final int totalPages;

  @override
  State<_PageJumpDialog> createState() => _PageJumpDialogState();
}

class _PageJumpDialogState extends State<_PageJumpDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialPage.toString(),
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Go to page'),
    content: TextField(
      key: const ValueKey('pdf-page-input'),
      controller: _controller,
      autofocus: true,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: 'Page (1–${widget.totalPages})',
        errorText: _error,
      ),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Go')),
    ],
  );

  void _submit() {
    final page = parsePdfPageNumber(_controller.text, widget.totalPages);
    if (page == null) {
      setState(() => _error = 'Enter a page from 1 to ${widget.totalPages}.');
      return;
    }
    Navigator.pop(context, page);
  }
}

class _TextPreview extends StatefulWidget {
  const _TextPreview({required this.path, this.markdown = false});

  final String path;
  final bool markdown;

  @override
  State<_TextPreview> createState() => _TextPreviewState();
}

class _TextPreviewState extends State<_TextPreview> {
  late final Future<_TextContent> _content;

  @override
  void initState() {
    super.initState();
    _content = _readTextPreview(widget.path);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_TextContent>(
      future: _content,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _ReaderMessage(
            message:
                'This text file could not be read. It may be corrupted or use an unsupported encoding.',
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final content = snapshot.data!;
        return Column(
          children: [
            if (widget.markdown)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: const Text(
                  'Markdown is shown as readable plain text; formatting is not rendered.',
                ),
              ),
            if (content.truncated)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: const Text(
                  'Showing the first 1 MB to keep large files responsive.',
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: SelectableText(
                  content.text,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

Future<_TextContent> _readTextPreview(String path) async {
  final file = File(path);
  final builder = BytesBuilder(copy: false);
  await for (final chunk in file.openRead(0, _maxTextPreviewBytes + 1)) {
    final remaining = _maxTextPreviewBytes + 1 - builder.length;
    builder.add(chunk.length > remaining ? chunk.sublist(0, remaining) : chunk);
  }
  final bytes = builder.takeBytes();
  final truncated = bytes.length > _maxTextPreviewBytes;
  final previewBytes = truncated
      ? bytes.sublist(0, _maxTextPreviewBytes)
      : bytes;
  return _TextContent(
    text: _decodeText(previewBytes, truncated: truncated),
    truncated: truncated,
  );
}

String _decodeText(List<int> bytes, {required bool truncated}) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    if (!truncated) rethrow;
    for (var trim = 1; trim <= 3 && trim < bytes.length; trim++) {
      try {
        return utf8.decode(bytes.sublist(0, bytes.length - trim));
      } on FormatException {
        continue;
      }
    }
    rethrow;
  }
}

class _TextContent {
  const _TextContent({required this.text, required this.truncated});

  final String text;
  final bool truncated;
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 5,
        child: Image.file(
          File(path),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const _ReaderMessage(
            message:
                'This image could not be rendered. It may be corrupted or use an unsupported encoding.',
          ),
        ),
      ),
    );
  }
}

class _ReaderMessage extends StatelessWidget {
  const _ReaderMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file_outlined, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

String _documentLoadError(Object error) {
  if (error is DocumentConsistencyException) return error.message;
  if (error is FileSystemException) {
    return 'This document is missing from Scanno’s local storage.';
  }
  return 'The document could not be opened. Please try again.';
}
