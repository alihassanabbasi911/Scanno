import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../application/document_providers.dart';
import '../data/document_repository.dart';
import '../domain/document_record.dart';

class DocumentLibraryPage extends ConsumerStatefulWidget {
  const DocumentLibraryPage({super.key});

  @override
  ConsumerState<DocumentLibraryPage> createState() =>
      _DocumentLibraryPageState();
}

class _DocumentLibraryPageState extends ConsumerState<DocumentLibraryPage> {
  final _searchController = TextEditingController();
  final Set<String> _documentsWithPendingDeletion = {};
  DocumentSortOrder _sortOrder = DocumentSortOrder.newest;
  bool _isImporting = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final documents = ref.watch(documentLibraryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanno'),
        actions: [
          IconButton(
            tooltip: 'Open-source notices',
            onPressed: () => context.push('/licenses'),
            icon: const Icon(Icons.info_outline),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _isImporting ? null : _importDocuments,
              icon: _isImporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_open_outlined),
              label: Text(_isImporting ? 'Importing' : 'Import'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your documents',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Keep your important files together, on this device.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  _buildControls(),
                  const SizedBox(height: 16),
                  Expanded(
                    child: documents.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (error, stackTrace) => _ErrorState(
                        message: _errorMessage(error),
                        onRetry: () => ref
                            .read(documentLibraryProvider.notifier)
                            .refresh(),
                      ),
                      data: (items) {
                        final visible = filterAndSortDocuments(
                          items,
                          query: _searchController.text,
                          sortOrder: _sortOrder,
                        );
                        if (visible.isEmpty) {
                          return _EmptyState(
                            searching: _searchController.text.trim().isNotEmpty,
                            onImport: _importDocuments,
                          );
                        }
                        return _DocumentGrid(
                          documents: visible,
                          onRename: _renameDocument,
                          onDelete: _deleteDocument,
                          onShare: _shareDocument,
                          onExport: _exportDocument,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sortControl = DropdownButtonFormField<DocumentSortOrder>(
          key: const ValueKey('document-sort'),
          initialValue: _sortOrder,
          decoration: const InputDecoration(
            labelText: 'Sort by',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          items: const [
            DropdownMenuItem(
              value: DocumentSortOrder.newest,
              child: Text('Newest'),
            ),
            DropdownMenuItem(
              value: DocumentSortOrder.oldest,
              child: Text('Oldest'),
            ),
            DropdownMenuItem(
              value: DocumentSortOrder.name,
              child: Text('Name'),
            ),
            DropdownMenuItem(
              value: DocumentSortOrder.largest,
              child: Text('Largest'),
            ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _sortOrder = value);
          },
        );
        final search = TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Search documents',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.clear),
                  ),
            border: const OutlineInputBorder(),
          ),
        );
        if (constraints.maxWidth < 560) {
          return Column(
            children: [
              search,
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(width: 190, child: sortControl),
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: search),
            const SizedBox(width: 12),
            SizedBox(width: 190, child: sortControl),
          ],
        );
      },
    );
  }

  Future<void> _importDocuments() async {
    setState(() => _isImporting = true);
    try {
      final summary = await ref
          .read(documentLibraryProvider.notifier)
          .importSelectedDocuments();
      if (!mounted) return;
      if (summary.failures.isEmpty) {
        if (summary.importedCount > 0) {
          _showMessage(
            '${summary.importedCount} document${summary.importedCount == 1 ? '' : 's'} imported.',
          );
        }
        return;
      }
      final details = summary.failures
          .map((failure) => '${failure.fileName}: ${failure.message}')
          .join('\n');
      _showMessage(
        '${summary.importedCount} imported; ${summary.failures.length} could not be imported.\n$details',
      );
    } on Exception catch (error) {
      if (mounted) _showMessage(_errorMessage(error));
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _renameDocument(DocumentRecord document) async {
    final extension = document.extension;
    final initialName = document.name.toLowerCase().endsWith('.$extension')
        ? document.name.substring(
            0,
            document.name.length - extension.length - 1,
          )
        : document.name;
    final name = await showDialog<String>(
      context: context,
      builder: (context) =>
          _RenameDocumentDialog(initialName: initialName, extension: extension),
    );
    if (name == null || !mounted) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      _showMessage('A document name cannot be empty.');
      return;
    }
    final fullName = trimmed.toLowerCase().endsWith('.$extension')
        ? trimmed
        : '$trimmed.$extension';
    try {
      await ref
          .read(documentLibraryProvider.notifier)
          .rename(document.id, fullName);
    } on Exception catch (error) {
      if (mounted) _showMessage(_errorMessage(error));
    }
  }

  Future<void> _deleteDocument(DocumentRecord document) async {
    if (!_documentsWithPendingDeletion.add(document.id)) return;
    setState(() {});
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete from Scanno?'),
          content: Text(
            '“${document.name}” and Scanno’s managed copy will be removed. '
            'The original file in Downloads or another source location will '
            'not be deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete from Scanno'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await ref.read(documentLibraryProvider.notifier).delete(document.id);
      if (mounted) _showMessage('Document deleted from Scanno.');
    } on Exception catch (error) {
      if (mounted) _showMessage(_errorMessage(error));
    } finally {
      _documentsWithPendingDeletion.remove(document.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _shareDocument(DocumentRecord document) async {
    try {
      final path = await ref
          .read(documentLibraryProvider.notifier)
          .getStoragePath(document.id);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: document.mimeType)],
          title: document.name,
        ),
      );
    } on Exception catch (error) {
      if (mounted) _showMessage(_errorMessage(error));
    }
  }

  Future<void> _exportDocument(DocumentRecord document) async {
    try {
      final exported = await ref
          .read(documentLibraryProvider.notifier)
          .export(document.id);
      if (exported && mounted) _showMessage('Document exported.');
    } on Exception catch (error) {
      if (mounted) _showMessage(_errorMessage(error));
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _RenameDocumentDialog extends StatefulWidget {
  const _RenameDocumentDialog({
    required this.initialName,
    required this.extension,
  });

  final String initialName;
  final String extension;

  @override
  State<_RenameDocumentDialog> createState() => _RenameDocumentDialogState();
}

class _RenameDocumentDialogState extends State<_RenameDocumentDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename document'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: 'Name',
          suffixText: '.${widget.extension}',
        ),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _DocumentGrid extends StatelessWidget {
  const _DocumentGrid({
    required this.documents,
    required this.onRename,
    required this.onDelete,
    required this.onShare,
    required this.onExport,
  });

  final List<DocumentRecord> documents;
  final ValueChanged<DocumentRecord> onRename;
  final ValueChanged<DocumentRecord> onDelete;
  final ValueChanged<DocumentRecord> onShare;
  final ValueChanged<DocumentRecord> onExport;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 600
            ? 2
            : 1;
        return GridView.builder(
          itemCount: documents.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 132,
          ),
          itemBuilder: (context, index) => _DocumentCard(
            document: documents[index],
            onRename: () => onRename(documents[index]),
            onDelete: () => onDelete(documents[index]),
            onShare: () => onShare(documents[index]),
            onExport: () => onExport(documents[index]),
            onOpen: () => context.push('/documents/${documents[index].id}'),
          ),
        );
      },
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.document,
    required this.onRename,
    required this.onDelete,
    required this.onShare,
    required this.onExport,
    required this.onOpen,
  });

  final DocumentRecord document;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onShare;
  final VoidCallback onExport;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = MaterialLocalizations.of(
      context,
    ).formatMediumDate(document.importedAt);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                child: Icon(_iconFor(document.extension)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${document.extension.toUpperCase()}  ·  ${formatFileSize(document.sizeBytes)}',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 2),
                    Text('Added $date', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              PopupMenuButton<_DocumentAction>(
                tooltip: 'Document actions',
                onSelected: (action) {
                  switch (action) {
                    case _DocumentAction.rename:
                      onRename();
                    case _DocumentAction.share:
                      onShare();
                    case _DocumentAction.export:
                      onExport();
                    case _DocumentAction.delete:
                      onDelete();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _DocumentAction.rename,
                    child: Text('Rename'),
                  ),
                  PopupMenuItem(
                    value: _DocumentAction.share,
                    child: Text('Share'),
                  ),
                  PopupMenuItem(
                    value: _DocumentAction.export,
                    child: Text('Save a copy…'),
                  ),
                  PopupMenuItem(
                    value: _DocumentAction.delete,
                    child: Text('Delete'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(String extension) {
    return switch (extension) {
      'pdf' => Icons.picture_as_pdf_outlined,
      'jpg' ||
      'jpeg' ||
      'png' ||
      'webp' ||
      'bmp' ||
      'tif' ||
      'tiff' ||
      'gif' => Icons.image_outlined,
      'xls' || 'xlsx' => Icons.table_chart_outlined,
      'ppt' || 'pptx' => Icons.slideshow_outlined,
      _ => Icons.description_outlined,
    };
  }
}

enum _DocumentAction { rename, share, export, delete }

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.searching, required this.onImport});

  final bool searching;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              searching ? Icons.search_off : Icons.folder_open_outlined,
              size: 58,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              searching ? 'No matching documents' : 'Your library is empty',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              searching
                  ? 'Try another name or format.'
                  : 'Import a document to keep it available on this device.',
              textAlign: TextAlign.center,
            ),
            if (!searching) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Import a document'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

String _errorMessage(Object error) {
  if (error is DocumentConsistencyException) return error.message;
  if (error is UnsupportedDocumentFormat) {
    return 'This document format is not supported.';
  }
  if (error is FileSystemException) {
    return 'A file could not be accessed. Check available storage and try again.';
  }
  if (error is PlatformException) {
    return 'Android could not complete this file operation.';
  }
  return 'The document operation failed. Please try again.';
}
