import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/document_providers.dart';
import '../domain/pdf_annotation.dart';

class PdfCommentsDialog extends ConsumerStatefulWidget {
  const PdfCommentsDialog({
    required this.documentId,
    required this.currentPage,
    super.key,
  });

  final String documentId;
  final int currentPage;

  @override
  ConsumerState<PdfCommentsDialog> createState() => _PdfCommentsDialogState();
}

class _PdfCommentsDialogState extends ConsumerState<PdfCommentsDialog> {
  late Future<List<PdfAnnotationRecord>> _comments;

  @override
  void initState() {
    super.initState();
    _comments = _loadComments();
  }

  Future<List<PdfAnnotationRecord>> _loadComments() => ref
      .read(pdfAnnotationRepositoryProvider)
      .listForDocument(widget.documentId);

  Future<void> _refresh() async {
    setState(() => _comments = _loadComments());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Page comments'),
      content: SizedBox(
        width: 520,
        child: FutureBuilder<List<PdfAnnotationRecord>>(
          future: _comments,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Text('Comments could not be loaded.');
            }
            if (!snapshot.hasData) {
              return const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final comments = snapshot.data!
                .where((comment) => comment.kind == PdfAnnotationKind.comment)
                .toList();
            if (comments.isEmpty) {
              return const SizedBox(
                height: 90,
                child: Center(child: Text('No comments saved yet.')),
              );
            }
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: comments.length,
                itemBuilder: (context, index) {
                  final comment = comments[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(comment.comment),
                    subtitle: Text('Page ${comment.pageNumber}'),
                    trailing: Wrap(
                      children: [
                        IconButton(
                          tooltip: 'Edit comment',
                          onPressed: () => _editComment(comment),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Delete comment',
                          onPressed: () => _deleteComment(comment),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: _addComment,
          icon: const Icon(Icons.add_comment_outlined),
          label: Text('Add to page ${widget.currentPage}'),
        ),
      ],
    );
  }

  Future<void> _addComment() async {
    final text = await _showCommentEditor(title: 'Add page comment');
    if (text == null) return;
    try {
      await ref
          .read(pdfAnnotationRepositoryProvider)
          .addComment(
            documentId: widget.documentId,
            pageNumber: widget.currentPage,
            text: text,
          );
      await _refresh();
    } on Exception catch (error) {
      if (mounted) _showError('The comment could not be saved: $error');
    }
  }

  Future<void> _editComment(PdfAnnotationRecord comment) async {
    final text = await _showCommentEditor(
      title: 'Edit page comment',
      initialText: comment.comment,
    );
    if (text == null) return;
    try {
      await ref
          .read(pdfAnnotationRepositoryProvider)
          .updateComment(comment.id, text);
      await _refresh();
    } on Exception catch (error) {
      if (mounted) _showError('The comment could not be updated: $error');
    }
  }

  Future<void> _deleteComment(PdfAnnotationRecord comment) async {
    try {
      await ref.read(pdfAnnotationRepositoryProvider).delete(comment.id);
      await _refresh();
    } on Exception catch (error) {
      if (mounted) _showError('The comment could not be deleted: $error');
    }
  }

  Future<String?> _showCommentEditor({
    required String title,
    String initialText = '',
  }) => showDialog<String>(
    context: context,
    builder: (context) =>
        _CommentEditorDialog(title: title, initialText: initialText),
  );

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _CommentEditorDialog extends StatefulWidget {
  const _CommentEditorDialog({required this.title, required this.initialText});

  final String title;
  final String initialText;

  @override
  State<_CommentEditorDialog> createState() => _CommentEditorDialogState();
}

class _CommentEditorDialogState extends State<_CommentEditorDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      key: const ValueKey('pdf-comment-input'),
      controller: _controller,
      autofocus: true,
      minLines: 2,
      maxLines: 5,
      decoration: const InputDecoration(
        labelText: 'Comment',
        border: OutlineInputBorder(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final value = _controller.text.trim();
          if (value.isNotEmpty) Navigator.pop(context, value);
        },
        child: const Text('Save'),
      ),
    ],
  );
}
