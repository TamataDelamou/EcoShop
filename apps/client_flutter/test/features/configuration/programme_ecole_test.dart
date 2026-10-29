import 'package:ecoshop_client/core/format/coefficient.dart';
import 'package:ecoshop_client/features/configuration/domain/configuration.dart';
import 'package:ecoshop_client/features/referentiel/domain/filiere_educative.dart';
import 'package:ecoshop_client/features/referentiel/domain/programme_matiere.dart';
import 'package:flutter_test/flutter_test.dart';

/// REG-33 : séries, programmes de l'école, coefficients décimaux.
void main() {
  test('coefficients : lus en nombre ou en texte, affichés à la française', () {
    expect(lireCoefficient(5), 5.0);
    expect(lireCoefficient(2.5), 2.5);
    expect(lireCoefficient('2.50'), 2.5);
    expect(lireCoefficient('1,5'), 1.5);
    expect(lireCoefficient(null), isNull);
    expect(formaterCoefficient(5), '5');
    expect(formaterCoefficient(2.5), '2,5');
    expect(formaterCoefficient(0.25), '0,25');
  });

  test('matière : coefficient décimal et nature, aller-retour', () {
    final m = ProgrammeMatiere.depuisJson({
      'id': 'm1',
      'programme_id': 'p1',
      'code': 'maths',
      'nom': 'Mathématiques',
      'ordre': 1,
      'coefficient': 5.0,
      'volume_horaire_annuel': 216,
      'nature': 'specialite',
    });
    expect(m.coefficient, 5.0);
    expect(m.nature, 'specialite');
    final relue = ProgrammeMatiere.depuisJson(m.versJson());
    expect(relue.coefficient, 5.0);
    expect(relue.nature, 'specialite');
    expect(ProgrammeMatiere.depuisJson({'id': 'm', 'programme_id': 'p', 'code': 'c', 'nom': 'n'}).nature, 'tronc_commun');
  });

  test('programme de l’école : matières triées, total des coefficients (sans coefficient = 1)', () {
    final p = ProgrammeEcole.depuisJson({
      'id': 'p1',
      'niveau_id': 'n11',
      'filiere_id': 'sm',
      'nom': '11e SM',
      'programmes_matieres': [
        {'id': 'b', 'programme_id': 'p1', 'code': 'fr', 'nom': 'Français', 'ordre': 2, 'coefficient': 2.5},
        {'id': 'a', 'programme_id': 'p1', 'code': 'ma', 'nom': 'Mathématiques', 'ordre': 1, 'coefficient': 5},
        {'id': 'c', 'programme_id': 'p1', 'code': 'eps', 'nom': 'EPS', 'ordre': 3},
      ],
    });
    expect([for (final m in p.matieres) m.id], ['a', 'b', 'c']);
    expect(p.totalCoefficients, 8.5);
    expect(ProgrammeEcole.depuisJson(p.versJson()).matieres.length, 3, reason: 'copie hors connexion');
  });

  test('programme d’une classe : celui de sa série, sinon celui du niveau', () {
    const serie = ProgrammeEcole(id: 'sm', niveauId: 'n11', filiereId: 'SM', nom: '11e SM');
    const niveau = ProgrammeEcole(id: 'tc', niveauId: 'n11', nom: '11e');
    const autre = ProgrammeEcole(id: 'x', niveauId: 'n12', filiereId: 'SM', nom: '12e SM');
    final liste = [niveau, serie, autre];
    expect(programmeEcolePour(liste, 'n11', 'SM')?.id, 'sm');
    expect(programmeEcolePour(liste, 'n11', 'SS')?.id, 'tc', reason: 'pas de programme SS : tronc commun du niveau');
    expect(programmeEcolePour(liste, 'n11', null)?.id, 'tc');
    expect(programmeEcolePour(liste, 'n10', null), isNull);
    expect(programmeEcolePour(liste, null, null), isNull);
  });

  test('série : ordre gardé dans la copie locale', () {
    final f = FiliereEducative.depuisJson(
        {'id': 'f', 'pays_code': 'GN', 'code': 'SM', 'nom': 'Sciences mathématiques', 'ordre': 1});
    expect(FiliereEducative.depuisJson(f.versJson()).ordre, 1);
  });

  test('état de la mise en route : niveaux sans matières', () {
    final e = EtatConfiguration.depuisJson({'niveaux_classes': 4, 'niveaux_sans_matieres': 1});
    expect(e.niveauxClasses, 4);
    expect(e.niveauxSansMatieres, 1);
  });
}
