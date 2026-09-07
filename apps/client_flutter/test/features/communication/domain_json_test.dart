import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/features/communication/domain/enums_comm.dart';
import 'package:ecoshop_client/features/communication/domain/log_envoi.dart';
import 'package:ecoshop_client/features/communication/domain/notif.dart';
import 'package:ecoshop_client/features/communication/domain/preference_canal.dart';
import 'package:ecoshop_client/features/communication/domain/taux_lecture_canal.dart';
import 'package:ecoshop_client/features/communication/domain/template_notification.dart';
import 'package:ecoshop_client/features/communication/prototype/domain/entree_communication_locale.dart';
import 'package:ecoshop_client/features/communication/prototype/domain/moderation_locale.dart';

void main() {
  group('Notif', () {
    test('versJsonCache/depuisJsonCache font un aller-retour fidèle', () {
      final notif = Notif(
        id: 'n1',
        etablissementId: 'et1',
        destinataire: 'p1',
        type: 'absence_parent',
        canal: CanalNotification.whatsapp,
        contenu: 'Votre enfant est absent aujourd\'hui.',
        statut: StatutNotification.envoyee,
        dateLecture: DateTime(2026, 3, 1, 9),
      );

      final relu = Notif.depuisJsonCache(notif.versJsonCache());

      expect(relu.canal, CanalNotification.whatsapp);
      expect(relu.estLue, isTrue);
      expect(relu.contenu, 'Votre enfant est absent aujourd\'hui.');
    });

    test('estLue est faux sans date de lecture', () {
      final notif = Notif(id: 'n1', etablissementId: 'et1', destinataire: 'p1', type: 'absence_parent');
      expect(notif.estLue, isFalse);
    });

    test('versJsonEcriture n\'expose pas les dates d\'envoi/lecture', () {
      final notif = Notif(
        id: 'n1',
        etablissementId: 'et1',
        destinataire: 'p1',
        type: 'absence_parent',
        dateLecture: DateTime(2026, 3, 1),
      );

      final json = notif.versJsonEcriture();
      expect(json.containsKey('date_lecture'), isFalse);
      expect(json.containsKey('id'), isFalse);
    });
  });

  group('PreferenceCanal', () {
    test('versJsonEcriture/depuisJson font un aller-retour fidèle', () {
      final preference = PreferenceCanal(
        id: 'pref1',
        profileId: 'p1',
        canal: CanalNotification.sms,
        horaireDebut: '07:30',
        horaireFin: '20:00',
        frequence: FrequenceNotification.quotidien,
      );

      final relue = PreferenceCanal.depuisJson(preference.versJsonEcriture());

      expect(relue.horaireDebut, '07:30');
      expect(relue.frequence, FrequenceNotification.quotidien);
    });

    test('tronque un horaire au format HH:mm:ss renvoyé par PostgREST', () {
      final preference = PreferenceCanal.depuisJson({
        'id': 'pref1',
        'profile_id': 'p1',
        'canal': 'sms',
        'horaire_debut': '08:00:00',
        'horaire_fin': '19:00:00',
        'frequence': 'immediat',
      });

      expect(preference.horaireDebut, '08:00');
      expect(preference.horaireFin, '19:00');
    });
  });

  group('LogEnvoi', () {
    test('depuisJson lit les colonnes de logs_envois', () {
      final log = LogEnvoi.depuisJson({
        'id': 'l1',
        'etablissement_id': 'et1',
        'notification_id': 'n1',
        'fournisseur': 'twilio',
        'statut': 'echoue',
        'code_erreur': 'INVALID_NUMBER',
      });

      expect(log.statut, StatutEnvoi.echoue);
      expect(log.codeErreur, 'INVALID_NUMBER');
    });
  });

  group('TemplateNotification', () {
    test('versJsonEcriture omet l\'identifiant (généré côté serveur)', () {
      final template = TemplateNotification(
        id: 't1',
        etablissementId: 'et1',
        type: 'absence_parent',
        canal: CanalNotification.sms,
        contenu: 'Votre enfant {{eleve}} est absent le {{date}}.',
        variables: const ['eleve', 'date'],
      );

      expect(template.versJsonEcriture().containsKey('id'), isFalse);
    });
  });

  group('TauxLectureCanal', () {
    test('depuisJson lit les colonnes de analyser_envois', () {
      final taux = TauxLectureCanal.depuisJson({
        'canal': 'sms',
        'nb_envoyes': 100,
        'nb_lus': 80,
        'taux_lecture': 0.8,
      });

      expect(taux.nbEnvoyes, 100);
      expect(taux.tauxLecture, 0.8);
    });
  });

  group('moderation_locale', () {
    test('détecte un terme inapproprié courant', () {
      expect(contientTermeInapproprie('Tu es vraiment stupide'), isTrue);
    });

    test('ne signale pas un message neutre', () {
      expect(contientTermeInapproprie('Merci pour votre retour, tout va bien.'), isFalse);
    });
  });

  group('EntreeCommunicationLocale', () {
    test('versJson/depuisJson font un aller-retour fidèle', () {
      final entree = EntreeCommunicationLocale(
        id: 'e1',
        type: TypeEntreeLocale.motLiaison,
        auteurId: 'p1',
        auteurNom: 'Mme Diallo',
        destinataireLabel: 'fiche1',
        contenu: 'Bien travaillé cette semaine.',
        dateCreation: DateTime(2026, 3, 1),
      );

      final relue = EntreeCommunicationLocale.depuisJson(entree.versJson());

      expect(relue.type, TypeEntreeLocale.motLiaison);
      expect(relue.contenu, 'Bien travaillé cette semaine.');
    });

    test('copierAvec(lu: true) ne modifie pas les autres champs', () {
      final entree = EntreeCommunicationLocale(
        id: 'e1',
        type: TypeEntreeLocale.annonce,
        auteurId: 'p1',
        auteurNom: 'Direction',
        destinataireLabel: 'Tout établissement',
        contenu: 'Réunion parents-professeurs vendredi.',
        dateCreation: DateTime(2026, 3, 1),
        important: true,
      );

      final lue = entree.copierAvec(lu: true);

      expect(lue.lu, isTrue);
      expect(lue.important, isTrue);
      expect(lue.contenu, entree.contenu);
    });
  });
}
