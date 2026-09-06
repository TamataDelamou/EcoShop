import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Table de la file de synchronisation hors-ligne (outbox, ch. 34-35).
class SyncQueueEntries extends Table {
  TextColumn get id => text()();
  TextColumn get entite => text()();
  TextColumn get operation => text()();
  TextColumn get payload => text()();
  IntColumn get tentatives => integer().withDefault(const Constant(0))();
  TextColumn get statut => text().withDefault(const Constant('en_attente'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Base locale Drift du client.
@DriftDatabase(tables: [SyncQueueEntries])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_ouvrirConnexion());

  /// Constructeur de test : injecte un exécuteur (ex. `NativeDatabase.memory()`).
  AppDatabase.pourTests(super.e);

  @override
  int get schemaVersion => 1;
}

LazyDatabase _ouvrirConnexion() {
  return LazyDatabase(() async {
    final repertoire = await getApplicationDocumentsDirectory();
    final fichier = File(p.join(repertoire.path, 'ecoshop.sqlite'));
    return NativeDatabase.createInBackground(fichier);
  });
}
