import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/core/sync/drift_sync_repository.dart';
import 'package:ecoshop_client/features/notes/data/cached_notes_repository.dart';
import 'package:ecoshop_client/features/notes/domain/appreciation.dart';
import 'package:ecoshop_client/features/notes/domain/bulletin.dart';
import 'package:ecoshop_client/features/notes/domain/evaluation.dart';
import 'package:ecoshop_client/features/notes/domain/note.dart';
import 'package:ecoshop_client/features/notes/domain/notes_repository.dart';

Evaluation _evaluation({String id = 'e1'}) => Evaluation(
      id: id,
      etablissementId: 'et1',
      anneeScolaireId: 'a1',
      classeId: 'c1',
      enseignantProfileId: 'p1',
      libelle: 'Contrôle 1',
      dateEvaluation: DateTime(2026, 9, 1),
    );

Note _note({String ficheId = 'f1', double? valeur = 15}) => Note(
      id: 'e1:$ficheId',
      etablissementId: 'et1',
      evaluationId: 'e1',
      ficheEleveId: ficheId,
      saisiPar: 'p1',
      valeur: valeur,
      nomEleve: 'Élève Test',
    );

class _FauxDistant implements NotesRepository {
  bool horsLigne = false;
  String? codeErreur;
  int appelsSaisirNote = 0;

  @override
  Future<List<Evaluation>> evaluationsDeClasse(String classeId, {String? periodeId}) async {
    if (horsLigne) throw const ErreurNotes('ERREUR_RESEAU');
    return [_evaluation()];
  }

  @override
  Future<List<Note>> notesDeEvaluation(String evaluationId) async {
    if (horsLigne) throw const ErreurNotes('ERREUR_RESEAU');
    return [_note()];
  }

  @override
  Future<List<Note>> notesDeFiche(String ficheEleveId, {String? periodeId}) async {
    if (horsLigne) throw const ErreurNotes('ERREUR_RESEAU');
    return [_note(ficheId: ficheEleveId)];
  }

  @override
  Future<double?> moyenneEleve(String ficheEleveId, {String? programmeMatiereId, String? periodeId}) async {
    if (horsLigne) throw const ErreurNotes('ERREUR_RESEAU');
    return 14.5;
  }

  @override
  Future<double?> moyenneClasse(String classeId, {String? programmeMatiereId, String? periodeId}) async {
    if (horsLigne) throw const ErreurNotes('ERREUR_RESEAU');
    return 12.0;
  }

  @override
  Future<List<Appreciation>> appreciationsDeFiche(String ficheEleveId, {String? periodeId}) async {
    if (horsLigne) throw const ErreurNotes('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<List<Bulletin>> bulletinsDeFiche(String ficheEleveId) async {
    if (horsLigne) throw const ErreurNotes('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<Evaluation> creerEvaluation(Evaluation evaluation) async => evaluation;

  @override
  Future<void> publierEvaluation(String evaluationId) async {}

  @override
  Future<bool> saisirNote(Note note) async {
    appelsSaisirNote++;
    final code = codeErreur;
    if (code != null) throw ErreurNotes(code);
    return true;
  }
}

void main() {
  late AppDatabase db;
  late _FauxDistant distant;
  late CachedNotesRepository repository;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    distant = _FauxDistant();
    repository = CachedNotesRepository(
      distant,
      CacheDocumentStore(db, 'notes'),
      DriftSyncRepository(db),
    );
  });

  tearDown(() => db.close());

  group('lecture', () {
    test('evaluationsDeClasse retombe sur le cache hors ligne', () async {
      await repository.evaluationsDeClasse('c1');
      distant.horsLigne = true;

      final liste = await repository.evaluationsDeClasse('c1');
      expect(liste.single.libelle, 'Contrôle 1');
    });

    test('moyenneEleve retombe sur le cache hors ligne', () async {
      await repository.moyenneEleve('f1');
      distant.horsLigne = true;

      expect(await repository.moyenneEleve('f1'), 14.5);
    });

    test('propage l\'erreur si le cache est vide et le réseau indisponible', () async {
      distant.horsLigne = true;
      expect(repository.evaluationsDeClasse('c1'), throwsA(isA<ErreurNotes>()));
    });
  });

  group('saisirNote', () {
    test('renvoie true et n\'enfile rien quand le réseau réussit', () async {
      final synchronisee = await repository.saisirNote(_note());

      expect(synchronisee, isTrue);
      expect(await DriftSyncRepository(db).entreesEnAttente(), isEmpty);
    });

    test('enfile la note et renvoie false sur une panne réseau non métier', () async {
      distant.codeErreur = 'ERREUR_RESEAU';

      final synchronisee = await repository.saisirNote(_note());

      expect(synchronisee, isFalse);
      final enAttente = await DriftSyncRepository(db).entreesEnAttente();
      expect(enAttente, hasLength(1));
      expect(enAttente.single.entite, 'notes');
    });

    test('remonte une erreur métier authentique sans l\'enfiler', () async {
      distant.codeErreur = 'NOTE_SUP_BAREME';

      await expectLater(
        repository.saisirNote(_note()),
        throwsA(isA<ErreurNotes>().having((e) => e.code, 'code', 'NOTE_SUP_BAREME')),
      );
      expect(await DriftSyncRepository(db).entreesEnAttente(), isEmpty);
    });
  });

  group('notesDeEvaluation — superposition de la file d\'attente', () {
    test('une note en attente masque la valeur serveur pour le même élève', () async {
      distant.codeErreur = 'ERREUR_RESEAU';
      await repository.saisirNote(_note(ficheId: 'f1', valeur: 8)); // enfilée hors ligne
      distant.codeErreur = null;

      final notes = await repository.notesDeEvaluation('e1');

      final noteF1 = notes.firstWhere((n) => n.ficheEleveId == 'f1');
      expect(noteF1.valeur, 8);
      // L'affichage (nom de l'élève), absent du payload d'écriture, est
      // récupéré depuis la dernière lecture serveur connue.
      expect(noteF1.nomEleve, 'Élève Test');
    });
  });
}
