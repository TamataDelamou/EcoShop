import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/theme/app_theme_variant.dart';
import 'package:ecoshop_client/features/etablissement/domain/etablissement.dart';
import 'package:ecoshop_client/features/export_pdf/data/cartes_eleves_pdf_builder.dart';
import 'package:ecoshop_client/features/pointage/domain/pointage.dart';

void main() {
  test('lecture d\'une carte : QR code (préfixe ECO1.) ou douchette', () {
    expect(jetonDepuisLecture('ECO1.Ab3-xYz_9876543210'), 'Ab3-xYz_9876543210');
    expect(jetonDepuisLecture('  Ab3-xYz_9876543210\n'), 'Ab3-xYz_9876543210');
    const carte = CartePortail(jeton: 'J1', ficheEleveId: 'f1', nom: 'BAH', prenom: 'Aïssatou');
    expect(carte.contenuQr, 'ECO1.J1');
  });

  test('le téléphone du portail retrouve un élève sans réseau', () {
    final donnees = DonneesPortail.depuisJson({
      'parametres': {'actif': true, 'heure_limite_arrivee': '07:45:00', 'heure_fin_cours': '14:30:00', 'jours_classe': [1, 2, 3, 4, 5, 6]},
      'cartes': [
        {'jeton': 'J1', 'fiche_eleve_id': 'f1', 'nom': 'BAH', 'prenom': 'Aïssatou', 'classe': '6e A'},
      ],
    });
    expect(donnees.carte('J1')?.nomComplet, 'Aïssatou BAH');
    expect(donnees.carte('inconnu'), isNull);
    expect(donnees.parametres.heureLimiteArrivee, '07:45');
    expect(donnees.parametres.minutesFinCours, 14 * 60 + 30);
    expect(donnees.parametres.joursClasse, [1, 2, 3, 4, 5, 6]);
  });

  test('réglages : paramètres envoyés au serveur', () {
    const p = ParametresPointage(actif: true, heureLimiteArrivee: '08:00', heureFinCours: '15:30', smsAbsence: false);
    final params = p.versParams('e1');
    expect(params['p_etablissement'], 'e1');
    expect(params['p_heure_limite_arrivee'], '08:00');
    expect(params['p_sms_absence'], isFalse);
    expect(p.copier(actif: false).heureFinCours, '15:30');
  });

  test('présence du jour : absents, retards, écarts avec l\'appel', () {
    final jour = PresenceDuJour.depuisJson({
      'jour': '2026-10-21',
      'actif': true,
      'heure_limite_arrivee': '08:15:00',
      'effectif': 3,
      'arrives': 2,
      'en_retard': 1,
      'sortis': 0,
      'traite': {'traite_le': '2026-10-21T08:25:00Z', 'alertes': 1},
      'portails': [
        {'appareil_id': 'a1', 'derniere_synchro': '2026-10-21T08:20:00Z'},
      ],
      'eleves': [
        {'fiche_eleve_id': 'f1', 'nom': 'BAH', 'prenom': 'A', 'arrivee': '2026-10-21T07:40:00Z', 'ecart': true, 'absent_appel': true},
        {'fiche_eleve_id': 'f2', 'nom': 'SOW', 'prenom': 'I', 'alertes': ['absence']},
        {'fiche_eleve_id': 'f3', 'nom': 'DIALLO', 'prenom': 'M', 'arrivee': '2026-10-21T08:30:00Z', 'en_retard': true},
      ],
      'credits_sms': 42,
    });
    expect(jour.absents, 1);
    expect(jour.ecarts, 1);
    expect(jour.eleves[1].alerteAbsence, isTrue);
    expect(jour.eleves[1].absent, isTrue);
    expect(jour.alertesEnvoyees, 1);
    expect(jour.derniereSynchro, isNotNull);
    expect(jour.heureLimiteArrivee, '08:15');
    expect(jour.creditsSms, 42);
  });

  test('relances : pas deux fois dans la semaine', () {
    final recente = FamilleEnRetard.depuisJson({
      'inscription_id': 'i1',
      'nom': 'BAH',
      'prenom': 'A',
      'exigible': 500000,
      'paye': 0,
      'en_retard': 500000,
      'derniere_relance': DateTime.now().subtract(const Duration(days: 2)).toUtc().toIso8601String(),
    });
    final ancienne = FamilleEnRetard.depuisJson({
      'inscription_id': 'i2',
      'nom': 'SOW',
      'prenom': 'I',
      'exigible': 500000,
      'paye': 100000,
      'en_retard': 400000,
      'derniere_relance': DateTime.now().subtract(const Duration(days: 9)).toUtc().toIso8601String(),
    });
    expect(recente.relanceeRecemment, isTrue);
    expect(ancienne.relanceeRecemment, isFalse);
    expect(ApercuRelances(familles: [recente, ancienne]).totalEnRetard, 900000);
  });

  test('cartes d\'élève : PDF valide, 10 cartes par page', () async {
    const etablissement = Etablissement(id: 'e1', nom: 'Groupe scolaire Bambino', slug: 'bambino');
    final cartes = [
      for (var i = 0; i < 12; i++)
        CartePortail(jeton: 'jeton-$i-abcdefghij', ficheEleveId: 'f$i', nom: 'ELEVE$i', prenom: 'Prénom', classe: '6e A', matricule: 'BAMB-0000$i'),
    ];
    final octets = await construireCartesElevesPdf(
      cartes: cartes,
      etablissement: etablissement,
      annee: '2026-2027',
      variante: AppThemeVariant.values.first,
    );
    expect(String.fromCharCodes(octets.take(4)), '%PDF');
  });
}
