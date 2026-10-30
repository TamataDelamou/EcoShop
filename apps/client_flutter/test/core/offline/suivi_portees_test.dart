import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/offline/suivi_portees.dart';

/// REG-35 lot 3 — date de lecture de chaque portée, à l'heure du serveur.
void main() {
  final lundi = DateTime.utc(2026, 10, 26, 8);
  final vendredi = DateTime.utc(2026, 10, 30, 8);

  test('ne soumet que les portées lues il y a moins de 7 jours', () {
    final suivi = SuiviPortees({
      'classe:c1': lundi,
      'fiche:f1': DateTime.utc(2026, 10, 1),
    });
    final demandes = suivi.demandes(vendredi);
    expect(demandes, [
      {'portee': 'classe', 'id': 'c1', 'depuis': lundi.toIso8601String()},
    ]);
  });

  test('inchangées : soumises et non signalées modifiées', () {
    final suivi = SuiviPortees({'classe:c1': lundi, 'classe:c2': lundi, 'fiche:f1': lundi});
    expect(suivi.inchangees(modifiees: {'classe:c2'}, maintenant: vendredi), {'classe:c1', 'fiche:f1'});
  });

  test('après un amorçage : relues datées du serveur, vues gardées, disparues oubliées', () {
    final suivi = SuiviPortees({'classe:c1': lundi, 'classe:c2': lundi, 'classe:fermee': lundi});
    final apres = suivi.apres(relues: {'classe:c2', 'fiche:nouvelle'}, vues: {'classe:c1', 'classe:c2', 'fiche:nouvelle'}, luLe: vendredi);
    expect(apres.lues, {'classe:c1': lundi, 'classe:c2': vendredi, 'fiche:nouvelle': vendredi});
  });

  test('aller-retour JSON', () {
    final suivi = SuiviPortees({'etablissement:e': lundi});
    expect(SuiviPortees.depuisJson(suivi.versJson()).lues, suivi.lues);
    expect(SuiviPortees.depuisJson(null).lues, isEmpty);
    expect(SuiviPortees.depuisJson({'lues': 'abîmé'}).lues, isEmpty);
  });

  test('lit la réponse du serveur', () {
    final r = lireReponsePortees({
      'maintenant': '2026-10-30T08:00:00+00:00',
      'modifiees': [
        {'portee': 'classe', 'id': 'c2'},
      ],
    });
    expect(r.maintenant, vendredi);
    expect(r.modifiees, {'classe:c2'});
    expect(lireReponsePortees(null).maintenant, isNull);
  });
}
