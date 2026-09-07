import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/features/vie_scolaire/domain/enums_vie_scolaire.dart';
import 'package:ecoshop_client/features/vie_scolaire/domain/presence.dart';
import 'package:ecoshop_client/features/vie_scolaire/domain/retard.dart';
import 'package:ecoshop_client/features/vie_scolaire/domain/sanction.dart';

void main() {
  group('Presence', () {
    test('versJson/depuisJsonCache font un aller-retour fidèle', () {
      final presence = Presence(
        id: 'f1:2026-09-07:demi_journee',
        etablissementId: 'et1',
        anneeScolaireId: 'a1',
        classeId: 'c1',
        ficheEleveId: 'f1',
        datePresence: DateTime(2026, 9, 7),
        saisiPar: 'p1',
        statut: StatutPresence.absent,
        justifie: true,
        motif: 'Certificat médical',
        nomEleve: 'Aïcha Diallo',
      );

      final relue = Presence.depuisJsonCache(presence.versJson());

      expect(relue.statut, StatutPresence.absent);
      expect(relue.justifie, isTrue);
      expect(relue.nomEleve, 'Aïcha Diallo');
    });

    test('versJsonEcriture n\'expose pas le nom de l\'élève', () {
      final presence = Presence(
        id: 'f1:2026-09-07:demi_journee',
        etablissementId: 'et1',
        anneeScolaireId: 'a1',
        classeId: 'c1',
        ficheEleveId: 'f1',
        datePresence: DateTime(2026, 9, 7),
        saisiPar: 'p1',
        nomEleve: 'Aïcha Diallo',
      );

      expect(presence.versJsonEcriture().containsKey('nom_eleve'), isFalse);
    });

    test('avecAffichage complète le nom manquant sans écraser un statut existant', () {
      final source = Presence(
        id: 'f1:2026-09-07:demi_journee',
        etablissementId: 'et1',
        anneeScolaireId: 'a1',
        classeId: 'c1',
        ficheEleveId: 'f1',
        datePresence: DateTime(2026, 9, 7),
        saisiPar: 'p1',
        nomEleve: 'Aïcha Diallo',
      );
      final entrant = Presence.depuisJsonEcriture(source.versJsonEcriture())
          .avecAffichage(source);

      expect(entrant.nomEleve, 'Aïcha Diallo');
      expect(entrant.statut, StatutPresence.present);
    });
  });

  group('Retard', () {
    test('versJsonCache/depuisJsonCache font un aller-retour fidèle', () {
      final retard = Retard(
        id: 'f1:2026-09-07',
        etablissementId: 'et1',
        ficheEleveId: 'f1',
        anneeScolaireId: 'a1',
        dateRetard: DateTime(2026, 9, 7),
        minutesRetard: 15,
        saisiPar: 'p1',
        justifie: false,
      );

      final relu = Retard.depuisJsonCache(retard.versJsonCache());

      expect(relu.minutesRetard, 15);
      expect(relu.justifie, isFalse);
    });
  });

  group('Sanction', () {
    test('estPropositionIaNonValidee est vrai pour une origine IA sans validateur', () {
      final sanction = Sanction(
        id: 's1',
        etablissementId: 'et1',
        ficheEleveId: 'f1',
        anneeScolaireId: 'a1',
        typeSanction: TypeSanction.entretienFamilleEtTutorat,
        motif: 'Absences répétées',
        dateDebut: DateTime(2026, 9, 7),
        decisionnaireId: 'p1',
        origine: OrigineSanction.ia,
      );

      expect(sanction.estPropositionIaNonValidee, isTrue);
    });

    test('estPropositionIaNonValidee est faux une fois validée', () {
      final sanction = Sanction(
        id: 's1',
        etablissementId: 'et1',
        ficheEleveId: 'f1',
        anneeScolaireId: 'a1',
        typeSanction: TypeSanction.entretienFamilleEtTutorat,
        motif: 'Absences répétées',
        dateDebut: DateTime(2026, 9, 7),
        decisionnaireId: 'p1',
        origine: OrigineSanction.ia,
        valideePar: 'direction1',
      );

      expect(sanction.estPropositionIaNonValidee, isFalse);
    });

    test('une origine humaine n\'est jamais une proposition IA à valider', () {
      final sanction = Sanction(
        id: 's1',
        etablissementId: 'et1',
        ficheEleveId: 'f1',
        anneeScolaireId: 'a1',
        typeSanction: TypeSanction.avertissement,
        motif: 'Retard répété',
        dateDebut: DateTime(2026, 9, 7),
        decisionnaireId: 'p1',
      );

      expect(sanction.estPropositionIaNonValidee, isFalse);
    });
  });
}
