import 'package:flutter_test/flutter_test.dart' hide Evaluation;

import 'package:ecoshop_client/features/notes/domain/evaluation.dart';
import 'package:ecoshop_client/features/notes/domain/note.dart';

Evaluation _evaluation() => Evaluation(
      id: 'e1',
      etablissementId: 'et1',
      anneeScolaireId: 'a1',
      classeId: 'c1',
      enseignantProfileId: 'p1',
      libelle: 'Composition',
      dateEvaluation: DateTime(2026, 12, 5),
      coefficient: 2,
      bareme: 20,
      nomMatiere: 'Histoire-Géo',
    );

void main() {
  group('Evaluation', () {
    test('versJsonCache/depuisJsonCache font un aller-retour fidèle', () {
      final relue = Evaluation.depuisJsonCache(_evaluation().versJsonCache());

      expect(relue.libelle, 'Composition');
      expect(relue.coefficient, 2);
      expect(relue.nomMatiere, 'Histoire-Géo');
      expect(relue.dateEvaluation, DateTime(2026, 12, 5));
    });
  });

  group('Note', () {
    test('versJson/depuisJsonCache conservent évaluation embarquée', () {
      final note = Note(
        id: 'e1:f1',
        etablissementId: 'et1',
        evaluationId: 'e1',
        ficheEleveId: 'f1',
        saisiPar: 'p1',
        valeur: 17,
        nomEleve: 'Kadiatou Bah',
        evaluation: _evaluation(),
      );

      final relue = Note.depuisJsonCache(note.versJson());

      expect(relue.valeur, 17);
      expect(relue.nomEleve, 'Kadiatou Bah');
      expect(relue.evaluation?.libelle, 'Composition');
    });

    test('versJsonEcriture n\'expose que les colonnes réelles de `notes`', () {
      final note = Note(
        id: 'e1:f1',
        etablissementId: 'et1',
        evaluationId: 'e1',
        ficheEleveId: 'f1',
        saisiPar: 'p1',
        valeur: 12,
        nomEleve: 'Kadiatou Bah',
        evaluation: _evaluation(),
      );

      final payload = note.versJsonEcriture();

      expect(payload.containsKey('nom_eleve'), isFalse);
      expect(payload.containsKey('evaluation'), isFalse);
      expect(payload['valeur'], 12);
    });

    test('avecAffichage complète les champs manquants sans écraser les existants', () {
      final source = Note(
        id: 'e1:f1',
        etablissementId: 'et1',
        evaluationId: 'e1',
        ficheEleveId: 'f1',
        saisiPar: 'p1',
        nomEleve: 'Kadiatou Bah',
        evaluation: _evaluation(),
      );
      final entrant = Note.depuisJsonEcriture(source.versJsonEcriture()..['valeur'] = 9);

      final fusionnee = entrant.avecAffichage(source);

      expect(fusionnee.valeur, 9);
      expect(fusionnee.nomEleve, 'Kadiatou Bah');
      expect(fusionnee.evaluation?.libelle, 'Composition');
    });

    test('la note absente n\'a jamais de valeur', () {
      const note = Note(
        id: 'e1:f1',
        etablissementId: 'et1',
        evaluationId: 'e1',
        ficheEleveId: 'f1',
        saisiPar: 'p1',
        absent: true,
      );

      expect(note.valeur, isNull);
    });
  });
}
