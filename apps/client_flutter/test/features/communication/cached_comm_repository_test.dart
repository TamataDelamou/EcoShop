import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/core/sync/drift_sync_repository.dart';
import 'package:ecoshop_client/features/communication/data/cached_comm_repository.dart';
import 'package:ecoshop_client/features/communication/domain/comm_repository.dart';
import 'package:ecoshop_client/features/communication/domain/enums_comm.dart';
import 'package:ecoshop_client/features/communication/domain/log_envoi.dart';
import 'package:ecoshop_client/features/communication/domain/notif.dart';
import 'package:ecoshop_client/features/communication/domain/preference_canal.dart';
import 'package:ecoshop_client/features/communication/domain/taux_lecture_canal.dart';
import 'package:ecoshop_client/features/communication/domain/template_notification.dart';

Notif _notif({String id = 'n1', String destinataire = 'p1'}) => Notif(
      id: id,
      etablissementId: 'et1',
      destinataire: destinataire,
      type: 'absence_parent',
      canal: CanalNotification.sms,
      contenu: 'Test',
    );

class _FauxDistant implements CommRepository {
  bool horsLigne = false;
  String? codeErreur;

  @override
  Future<List<Notif>> mesNotifications(String profileId) async {
    if (horsLigne) throw const ErreurComm('ERREUR_RESEAU');
    return [_notif(destinataire: profileId)];
  }

  @override
  Future<List<Notif>> notificationsEtablissement(String etablissementId) async {
    if (horsLigne) throw const ErreurComm('ERREUR_RESEAU');
    return [_notif()];
  }

  @override
  Future<bool> marquerLue(String notificationId, {required String destinataire}) async {
    final code = codeErreur;
    if (code != null) throw ErreurComm(code);
    return true;
  }

  @override
  Future<Notif> creerNotification(Notif notification) async => notification;

  @override
  Future<List<PreferenceCanal>> mesPreferences(String profileId) async {
    if (horsLigne) throw const ErreurComm('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<bool> definirPreference(PreferenceCanal preference) async {
    final code = codeErreur;
    if (code != null) throw ErreurComm(code);
    return true;
  }

  @override
  Future<List<LogEnvoi>> logsEtablissement(String etablissementId) async {
    if (horsLigne) throw const ErreurComm('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<List<TemplateNotification>> templatesEtablissement(String etablissementId) async {
    if (horsLigne) throw const ErreurComm('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<void> creerOuModifierTemplate(TemplateNotification template) async {}

  @override
  Future<List<TauxLectureCanal>> analyserEnvois(String etablissementId, DateTime debut, DateTime fin) async {
    if (horsLigne) throw const ErreurComm('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<String> suggereHeureEnvoi(String profileId) async => '09:00';

  @override
  Future<String> choisirCanal(String profileId, String type) async => 'whatsapp';

  @override
  Future<String> selectionnerVariante(String profileId, String type) async => 'A';

  @override
  Future<String> analyserFeedback(String texte) async => 'positif';
}

void main() {
  late AppDatabase db;
  late _FauxDistant distant;
  late CachedCommRepository repository;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    distant = _FauxDistant();
    repository = CachedCommRepository(distant, CacheDocumentStore(db, 'communication'), DriftSyncRepository(db));
  });

  tearDown(() => db.close());

  group('lecture', () {
    test('mesNotifications retombe sur le cache hors ligne', () async {
      await repository.mesNotifications('p1');
      distant.horsLigne = true;

      final liste = await repository.mesNotifications('p1');
      expect(liste.single.destinataire, 'p1');
    });
  });

  group('marquerLue', () {
    test('renvoie true sans rien enfiler quand le réseau réussit', () async {
      final synchronisee = await repository.marquerLue('n1', destinataire: 'p1');

      expect(synchronisee, isTrue);
      expect(await DriftSyncRepository(db).entreesEnAttente(), isEmpty);
    });

    test('enfile le marquage et renvoie false sur une panne réseau non métier', () async {
      distant.codeErreur = 'ERREUR_RESEAU';

      final synchronisee = await repository.marquerLue('n1', destinataire: 'p1');

      expect(synchronisee, isFalse);
      final enAttente = await DriftSyncRepository(db).entreesEnAttente();
      expect(enAttente, hasLength(1));
      expect(enAttente.single.entite, 'notifications_lecture');
    });

    test('remonte une erreur métier authentique sans l\'enfiler', () async {
      distant.codeErreur = 'LECTURE_DESTINATAIRE';

      await expectLater(
        repository.marquerLue('n1', destinataire: 'p1'),
        throwsA(isA<ErreurComm>().having((e) => e.code, 'code', 'LECTURE_DESTINATAIRE')),
      );
      expect(await DriftSyncRepository(db).entreesEnAttente(), isEmpty);
    });
  });

  group('mesNotifications — superposition de la file d\'attente', () {
    test('un marquage en attente affiche la notification comme lue', () async {
      distant.codeErreur = 'ERREUR_RESEAU';
      await repository.marquerLue('n1', destinataire: 'p1');
      distant.codeErreur = null;

      final liste = await repository.mesNotifications('p1');
      expect(liste.single.estLue, isTrue);
    });
  });

  group('definirPreference', () {
    test('enfile la préférence et renvoie false sur une panne réseau non métier', () async {
      distant.codeErreur = 'ERREUR_RESEAU';

      final synchronisee = await repository.definirPreference(
        const PreferenceCanal(id: 'pref1', profileId: 'p1', canal: CanalNotification.sms),
      );

      expect(synchronisee, isFalse);
      final enAttente = await DriftSyncRepository(db).entreesEnAttente();
      expect(enAttente, hasLength(1));
      expect(enAttente.single.entite, 'preferences_canaux');
    });
  });
}
