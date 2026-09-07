import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/features/referentiel/domain/arborescence_niveau.dart';
import 'package:ecoshop_client/features/referentiel/domain/arborescence_pays.dart';
import 'package:ecoshop_client/features/referentiel/domain/cycle_educatif.dart';
import 'package:ecoshop_client/features/referentiel/domain/niveau_educatif.dart';
import 'package:ecoshop_client/features/referentiel/domain/programme_matiere.dart';
import 'package:ecoshop_client/features/referentiel/domain/programme_officiel.dart';

void main() {
  group('NiveauEducatif', () {
    test('depuisJson/versJson font un aller-retour fidèle', () {
      const niveau = NiveauEducatif(
        id: 'n1',
        cycleId: 'c1',
        paysCode: 'GN',
        code: 'CP1',
        nom: 'CP1',
        gradeLevelNormalise: 1,
        isced: 1,
        ordre: 1,
      );

      final relu = NiveauEducatif.depuisJson(niveau.versJson());

      expect(relu.id, niveau.id);
      expect(relu.gradeLevelNormalise, 1);
    });
  });

  group('ArborescencePays', () {
    test('niveauxDuCycle filtre et trie par ordre', () {
      const arbo = ArborescencePays(
        cycles: [
          CycleEducatif(
            id: 'c1',
            paysCode: 'GN',
            code: 'primaire',
            nom: 'Primaire',
            ordre: 1,
            iscedMin: 1,
            iscedMax: 1,
          ),
        ],
        niveaux: [
          NiveauEducatif(
            id: 'n2',
            cycleId: 'c1',
            paysCode: 'GN',
            code: 'CP2',
            nom: 'CP2',
            gradeLevelNormalise: 2,
            isced: 1,
            ordre: 2,
          ),
          NiveauEducatif(
            id: 'n1',
            cycleId: 'c1',
            paysCode: 'GN',
            code: 'CP1',
            nom: 'CP1',
            gradeLevelNormalise: 1,
            isced: 1,
            ordre: 1,
          ),
          NiveauEducatif(
            id: 'n3',
            cycleId: 'autre-cycle',
            paysCode: 'GN',
            code: 'X',
            nom: 'X',
            gradeLevelNormalise: 3,
            isced: 1,
            ordre: 3,
          ),
        ],
        examens: [],
      );

      final niveaux = arbo.niveauxDuCycle('c1');

      expect(niveaux.map((n) => n.id), ['n1', 'n2']);
    });

    test('survit à un aller-retour JSON complet', () {
      const arbo = ArborescencePays(
        cycles: [
          CycleEducatif(
            id: 'c1',
            paysCode: 'GN',
            code: 'primaire',
            nom: 'Primaire',
            ordre: 1,
            iscedMin: 1,
            iscedMax: 1,
          ),
        ],
        niveaux: [],
        examens: [],
      );

      final relue = ArborescencePays.depuisJson(arbo.versJson());
      expect(relue.cycles.single.nom, 'Primaire');
    });
  });

  group('ArborescenceNiveau', () {
    test('programmePrincipal choisit la version la plus récente', () {
      const arbo = ArborescenceNiveau(
        filieres: [],
        programmes: [
          ProgrammeOfficiel(
            id: 'p1',
            paysCode: 'GN',
            niveauId: 'n1',
            code: 'PROG',
            nom: 'Programme v1',
            version: 1,
          ),
          ProgrammeOfficiel(
            id: 'p2',
            paysCode: 'GN',
            niveauId: 'n1',
            code: 'PROG',
            nom: 'Programme v2',
            version: 2,
          ),
        ],
        matieres: [],
      );

      expect(arbo.programmePrincipal()!.id, 'p2');
    });

    test('matieresDuProgramme trie par ordre', () {
      const arbo = ArborescenceNiveau(
        filieres: [],
        programmes: [],
        matieres: [
          ProgrammeMatiere(id: 'm2', programmeId: 'p1', code: 'B', nom: 'B', ordre: 2),
          ProgrammeMatiere(id: 'm1', programmeId: 'p1', code: 'A', nom: 'A', ordre: 1),
        ],
      );

      expect(arbo.matieresDuProgramme('p1').map((m) => m.id), ['m1', 'm2']);
    });
  });
}
