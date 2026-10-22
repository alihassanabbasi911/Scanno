import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'document_database.g.dart';

class Documents extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get extension => text()();
  TextColumn get mimeType => text()();
  TextColumn get storagePath => text()();
  IntColumn get sizeBytes => integer()();
  DateTimeColumn get importedAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class PdfAnnotations extends Table {
  TextColumn get id => text()();
  TextColumn get documentId =>
      text().references(Documents, #id, onDelete: KeyAction.cascade)();
  IntColumn get pageNumber => integer()();
  TextColumn get type => text()();
  TextColumn get payload => text()();
  IntColumn get colorValue =>
      integer().withDefault(const Constant(0xFFFFD54F))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [Documents, PdfAnnotations])
class DocumentDatabase extends _$DocumentDatabase {
  DocumentDatabase() : super(driftDatabase(name: 'scanno_documents'));

  DocumentDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      if (from < 2) await migrator.createTable(pdfAnnotations);
    },
  );
}
