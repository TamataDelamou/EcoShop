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

/// Cache générique de lecture hors-ligne du référentiel pédagogique (M4).
///
/// Une ligne par sous-arbre mis en cache ([type] + [cle], ex. `pays`/`global`
/// ou `pays_detail`/`GN`) plutôt qu'une table par entité SQL : le référentiel
/// se consulte par sous-arbre complet (pays, puis niveau), jamais ligne à
/// ligne, ce qui correspond à l'unité naturelle de téléchargement des
/// `paquets_referentiel` (contrat M04 §5).
class ReferentielCacheEntries extends Table {
  TextColumn get type => text()();
  TextColumn get cle => text()();
  TextColumn get payload => text()();
  DateTimeColumn get misAJourLe => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {type, cle};
}

/// Cache générique de lecture hors-ligne, partagé par les modules M5 et
/// suivants (structures d'établissement, fiches liées…).
///
/// [ReferentielCacheEntries] (M4) reste dédiée à son module — déjà scellée et
/// testée telle quelle. À partir de M5, chaque module partage cette table via
/// un [domaine] distinct plutôt que de recréer une table Drift par module :
/// le schéma est déjà identique table après table, seule la donnée change.
class CacheEntries extends Table {
  TextColumn get domaine => text()();
  TextColumn get type => text()();
  TextColumn get cle => text()();
  TextColumn get payload => text()();
  DateTimeColumn get misAJourLe => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {domaine, type, cle};
}

/// Base locale Drift du client.
@DriftDatabase(tables: [SyncQueueEntries, ReferentielCacheEntries, CacheEntries])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_ouvrirConnexion());

  /// Constructeur de test : injecte un exécuteur (ex. `NativeDatabase.memory()`).
  AppDatabase.pourTests(super.e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(referentielCacheEntries);
          }
          if (from < 3) {
            await m.createTable(cacheEntries);
          }
        },
      );
}

LazyDatabase _ouvrirConnexion() {
  return LazyDatabase(() async {
    final repertoire = await getApplicationDocumentsDirectory();
    final fichier = File(p.join(repertoire.path, 'ecoshop.sqlite'));
    return NativeDatabase.createInBackground(fichier);
  });
}
