import 'dart:convert';

import '../../../core/db/cache_document_store.dart';
import '../../../core/sync/drift_sync_repository.dart';
import '../../../core/sync/sync_engine.dart';
import '../domain/comm_repository.dart';
import '../domain/log_envoi.dart';
import '../domain/notif.dart';
import '../domain/preference_canal.dart';
import '../domain/taux_lecture_canal.dart';
import '../domain/template_notification.dart';

/// Décore un [CommRepository] réseau avec un repli SQLite/Drift, et rend
/// [marquerLue]/[definirPreference] utilisables hors connexion via la même
/// file `sync_queue` que les autres modules (M6-M8) — panne réseau ⇒ mise en
/// file ; rejet métier authentique ⇒ remonté tel quel.
class CachedCommRepository implements CommRepository {
  const CachedCommRepository(this._distant, this._cache, this._syncRepo);

  final CommRepository _distant;
  final CacheDocumentStore _cache;
  final DriftSyncRepository _syncRepo;

  static const _typeMesNotifications = 'mes_notifications';
  static const _typeNotificationsEtablissement = 'notifications_etablissement';
  static const _typeMesPreferences = 'mes_preferences';
  static const _typeLogs = 'logs_etablissement';
  static const _typeTemplates = 'templates_etablissement';
  static const _typeAnalyseEnvois = 'analyser_envois';

  /// Codes métier authentiques des triggers M9 — jamais mis en file.
  static const _codesMetierBloquants = {
    'NOTIFICATION_AUTRE_ETABLISSEMENT',
    'LECTURE_DESTINATAIRE',
    'MODIFICATION_NON_AUTORISEE',
  };

  @override
  Future<List<Notif>> mesNotifications(String profileId) async {
    final base = await _listeAvecCache(
      type: _typeMesNotifications,
      cle: profileId,
      lire: () => _distant.mesNotifications(profileId),
      versJson: (n) => n.versJsonCache(),
      depuisJson: Notif.depuisJsonCache,
    );
    return _fusionnerLecturesEnAttente(base);
  }

  @override
  Future<List<Notif>> notificationsEtablissement(String etablissementId) {
    return _listeAvecCache(
      type: _typeNotificationsEtablissement,
      cle: etablissementId,
      lire: () => _distant.notificationsEtablissement(etablissementId),
      versJson: (n) => n.versJsonCache(),
      depuisJson: Notif.depuisJsonCache,
    );
  }

  @override
  Future<bool> marquerLue(String notificationId, {required String destinataire}) async {
    try {
      return await _distant.marquerLue(notificationId, destinataire: destinataire);
    } catch (e) {
      if (e is ErreurComm && _codesMetierBloquants.contains(e.code)) rethrow;
      await _syncRepo.enfiler(
        SyncEntree(
          id: notificationId,
          entite: 'notifications_lecture',
          operation: 'update',
          payload: jsonEncode({'id': notificationId, 'destinataire': destinataire}),
        ),
      );
      return false;
    }
  }

  @override
  Future<Notif> creerNotification(Notif notification) => _distant.creerNotification(notification);

  @override
  Future<List<PreferenceCanal>> mesPreferences(String profileId) {
    return _listeAvecCache(
      type: _typeMesPreferences,
      cle: profileId,
      lire: () => _distant.mesPreferences(profileId),
      versJson: (p) => p.versJsonCache(),
      depuisJson: PreferenceCanal.depuisJsonCache,
    );
  }

  @override
  Future<bool> definirPreference(PreferenceCanal preference) async {
    try {
      return await _distant.definirPreference(preference);
    } catch (e) {
      if (e is ErreurComm && _codesMetierBloquants.contains(e.code)) rethrow;
      await _syncRepo.enfiler(
        SyncEntree(
          id: preference.id,
          entite: 'preferences_canaux',
          operation: 'upsert',
          payload: jsonEncode(preference.versJsonEcriture()),
        ),
      );
      return false;
    }
  }

  @override
  Future<List<LogEnvoi>> logsEtablissement(String etablissementId) {
    // Journal technique de bureau : pas de superposition de file d'attente
    // pertinente, un simple repli cache suffit.
    return _listeAvecCache(
      type: _typeLogs,
      cle: etablissementId,
      lire: () => _distant.logsEtablissement(etablissementId),
      versJson: (l) => {
        'id': l.id,
        'etablissement_id': l.etablissementId,
        'notification_id': l.notificationId,
        'fournisseur': l.fournisseur,
        'statut': l.statut.code,
        'code_erreur': l.codeErreur,
        'date_retry': l.dateRetry?.toIso8601String(),
        'message_id_fournisseur': l.messageIdFournisseur,
      },
      depuisJson: LogEnvoi.depuisJson,
    );
  }

  @override
  Future<List<TemplateNotification>> templatesEtablissement(String etablissementId) {
    return _listeAvecCache(
      type: _typeTemplates,
      cle: etablissementId,
      lire: () => _distant.templatesEtablissement(etablissementId),
      versJson: (t) => t.versJsonEcriture()..['id'] = t.id,
      depuisJson: TemplateNotification.depuisJson,
    );
  }

  @override
  Future<void> creerOuModifierTemplate(TemplateNotification template) =>
      _distant.creerOuModifierTemplate(template);

  @override
  Future<List<TauxLectureCanal>> analyserEnvois(String etablissementId, DateTime debut, DateTime fin) {
    final cle = '$etablissementId::${debut.toIso8601String()}::${fin.toIso8601String()}';
    return _listeAvecCache(
      type: _typeAnalyseEnvois,
      cle: cle,
      lire: () => _distant.analyserEnvois(etablissementId, debut, fin),
      versJson: (t) => {
        'canal': t.canal,
        'nb_envoyes': t.nbEnvoyes,
        'nb_lus': t.nbLus,
        'taux_lecture': t.tauxLecture,
      },
      depuisJson: TauxLectureCanal.depuisJson,
    );
  }

  @override
  Future<String> suggereHeureEnvoi(String profileId) => _distant.suggereHeureEnvoi(profileId);

  @override
  Future<String> choisirCanal(String profileId, String type) => _distant.choisirCanal(profileId, type);

  @override
  Future<String> selectionnerVariante(String profileId, String type) =>
      _distant.selectionnerVariante(profileId, type);

  @override
  Future<String> analyserFeedback(String texte) => _distant.analyserFeedback(texte);

  /// Superpose à [base] les marquages « lue » encore en attente, pour un
  /// affichage immédiat après une lecture hors-ligne.
  Future<List<Notif>> _fusionnerLecturesEnAttente(List<Notif> base) async {
    final enAttente = await _syncRepo.entreesEnAttente();
    final parId = {for (final n in base) n.id: n};

    for (final entree in enAttente) {
      if (entree.entite != 'notifications_lecture') continue;
      final json = jsonDecode(entree.payload) as Map<String, dynamic>;
      final id = json['id'] as String;
      final existante = parId[id];
      if (existante == null || existante.estLue) continue;
      parId[id] = Notif(
        id: existante.id,
        etablissementId: existante.etablissementId,
        destinataire: existante.destinataire,
        type: existante.type,
        canal: existante.canal,
        contenu: existante.contenu,
        variante: existante.variante,
        variables: existante.variables,
        statut: existante.statut,
        dateEnvoiPlanifie: existante.dateEnvoiPlanifie,
        dateEnvoi: existante.dateEnvoi,
        dateLecture: DateTime.now(),
      );
    }

    return parId.values.toList(growable: false);
  }

  Future<List<T>> _listeAvecCache<T>({
    required String type,
    required String cle,
    required Future<List<T>> Function() lire,
    required Map<String, dynamic> Function(T) versJson,
    required T Function(Map<String, dynamic>) depuisJson,
  }) async {
    try {
      final liste = await lire();
      await _cache.ecrireDocument(type, cle, {
        'lignes': liste.map(versJson).toList(growable: false),
      });
      return liste;
    } on ErreurComm {
      final document = await _cache.lireDocument(type, cle);
      if (document == null) rethrow;
      return (document['lignes'] as List<dynamic>)
          .map((l) => depuisJson(l as Map<String, dynamic>))
          .toList(growable: false);
    }
  }
}
