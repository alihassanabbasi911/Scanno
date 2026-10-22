import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/document_database.dart';
import '../data/document_repository.dart';
import '../data/incoming_document_service.dart';
import '../data/managed_file_store.dart';
import '../domain/document_record.dart';
import '../domain/incoming_document.dart';
import '../data/pdf_annotation_repository.dart';

final documentDatabaseProvider = Provider<DocumentDatabase>((ref) {
  final database = DocumentDatabase();
  ref.onDispose(database.close);
  return database;
});

final documentRepositoryProvider = Provider<DocumentRepository>((ref) {
  return LocalDocumentRepository(
    ref.watch(documentDatabaseProvider),
    LocalManagedFileStore(),
  );
});

final incomingDocumentServiceProvider = Provider<IncomingDocumentService>(
  (ref) => IncomingDocumentService(NativeIncomingDocumentBridge()),
);

final pdfAnnotationRepositoryProvider = Provider<PdfAnnotationRepository>((
  ref,
) {
  return PdfAnnotationRepository(ref.watch(documentDatabaseProvider));
});

final documentLibraryProvider =
    AsyncNotifierProvider<DocumentLibraryController, List<DocumentRecord>>(
      DocumentLibraryController.new,
    );

final documentByIdProvider = FutureProvider.family<DocumentRecord, String>((
  ref,
  id,
) {
  return ref.watch(documentRepositoryProvider).getDocument(id);
});

class DocumentLibraryController extends AsyncNotifier<List<DocumentRecord>> {
  DocumentRepository get _repository => ref.read(documentRepositoryProvider);

  @override
  Future<List<DocumentRecord>> build() => _repository.listDocuments();

  Future<void> refresh() async {
    state = const AsyncLoading<List<DocumentRecord>>();
    state = await AsyncValue.guard(_repository.listDocuments);
  }

  Future<ImportSummary> importSelectedDocuments() async {
    final summary = await _repository.importSelectedDocuments();
    await refresh();
    return summary;
  }

  Future<IncomingImportResult> importIncomingDocument(
    IncomingDocument incoming,
  ) async {
    final result = await _repository.importIncomingDocument(incoming);
    ref.invalidateSelf();
    return result;
  }

  Future<void> rename(String id, String name) async {
    await _repository.rename(id, name);
    await refresh();
  }

  Future<void> delete(String id) async {
    await _repository.delete(id);
    await refresh();
  }

  Future<String> getStoragePath(String id) => _repository.getStoragePath(id);

  Future<bool> export(String id) => _repository.export(id);
}
