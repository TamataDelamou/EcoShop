import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/sync/drift_sync_repository.dart';
import '../../../core/sync/sync_engine.dart';
import '../domain/pointage.dart';

/// Pointage au portail (REG-09), d'abord hors connexion.
///
/// Un scan part tout de suite au serveur (5 s au plus) ; sans réseau, il est
/// gardé sur le téléphone (clé générée ici, heure du scan conservée) et
/// envoyé au retour du réseau — le serveur reconnaît la clé, jamais de
/// doublon. Le nom de l'élève s'affiche quand même : la liste des cartes
/// valides est gardée sur le téléphone. Les écrans de consultation
/// resservent leur dernière réponse sans réseau.
class SupabasePointageRepository implements PointageRepository {
  SupabasePointageRepository(this._client, this._file, this._store, [this._lecture]);

  final SupabaseClient _client;
  final DriftSyncRepository _file;
  final CacheDocumentStore _store;
  final LectureHorsLigne? _lecture;
  final Uuid _uuid = const Uuid();

  static const entiteScan = 'pointages_portail';
  static const delaiScan = Duration(seconds: 5);

  /// Derniers passages vus sur ce téléphone : une carte présentée deux fois
  /// de suite n'est comptée qu'une fois.
  final Map<String, DateTime> _derniersPassages = {};

  Future<T> _lire<T>(String type, String cle, Future<Object?> Function() source, T Function(Object?) decoder) {
    final lecture = _lecture;
    if (lecture == null) return _executer(() async => decoder(await source()));
    return _executer(() => lecture.lire(type: type, cle: cle, source: source, decoder: decoder));
  }

  // -------------------------------------------------------------------------
  // Portail
  // -------------------------------------------------------------------------
  @override
  Future<DonneesPortail> donneesPortail(String etablissementId) async {
    try {
      final json = await _executer(() =>
          _client.rpc<dynamic>('cartes_portail', params: {'p_etablissement': etablissementId}).timeout(const Duration(seconds: 20)));
      await _store.ecrireDocument('cartes_portail', etablissementId, {'json': json});
      return DonneesPortail.depuisJson(json as Map<String, dynamic>);
    } on ErreurPointage catch (e) {
      if (e.code != 'HORS_CONNEXION') rethrow;
      final garde = await _store.lireDocument('cartes_portail', etablissementId);
      if (garde == null) throw const ErreurPointage('AUCUN_PORTAIL_DONNEES');
      return DonneesPortail.depuisJson(garde['json'] as Map<String, dynamic>);
    }
  }

  @override
  Future<ResultatScan> scanner({
    required String etablissementId,
    required String lecture,
    required SensPointage sens,
    required String appareilId,
  }) async {
    final jeton = jetonDepuisLecture(lecture);
    final maintenant = DateTime.now();
    final cle = '$jeton/${sens.code}';
    final precedent = _derniersPassages[cle];
    final garde = await _store.lireDocument('cartes_portail', etablissementId);
    final cartes = garde == null ? null : DonneesPortail.depuisJson(garde['json'] as Map<String, dynamic>);
    final carte = cartes?.carte(jeton);

    if (precedent != null && maintenant.difference(precedent) < const Duration(minutes: 2)) {
      return ResultatScan(statut: StatutScan.doublon, sens: sens, heure: maintenant, carte: carte);
    }
    if (cartes != null && carte == null) {
      // Carte inconnue de la liste du téléphone : refusée tout de suite (la
      // liste est rechargée à chaque ouverture du portail avec réseau).
      return ResultatScan(statut: StatutScan.carteInconnue, sens: sens, heure: maintenant);
    }

    final params = {
      'p_id': _uuid.v4(),
      'p_etablissement': etablissementId,
      'p_jeton': jeton,
      'p_sens': sens.code,
      'p_scanne_le': maintenant.toUtc().toIso8601String(),
      'p_appareil': appareilId,
    };
    try {
      final json = await _executer(() => _client.rpc<dynamic>('enregistrer_pointage', params: params).timeout(delaiScan));
      final r = json as Map<String, dynamic>;
      final statut = switch (r['statut'] as String?) {
        'carte_inconnue' => StatutScan.carteInconnue,
        'doublon' => StatutScan.doublon,
        _ => StatutScan.enregistre,
      };
      if (statut == StatutScan.enregistre) _derniersPassages[cle] = maintenant;
      return ResultatScan(
        statut: statut,
        sens: sens,
        heure: maintenant,
        carte: carte,
        nom: r['nom'] as String?,
        prenom: r['prenom'] as String?,
        classe: r['classe'] as String?,
        enRetard: r['en_retard'] as bool? ?? false,
      );
    } on ErreurPointage catch (e) {
      if (e.code != 'HORS_CONNEXION') rethrow;
    }
    await _file.enfiler(SyncEntree(
      id: params['p_id']!,
      entite: entiteScan,
      operation: 'insert',
      payload: jsonEncode(params),
    ));
    _derniersPassages[cle] = maintenant;
    final limite = cartes?.parametres.heureLimiteArrivee;
    final retard = sens == SensPointage.arrivee &&
        limite != null &&
        '${maintenant.hour.toString().padLeft(2, '0')}:${maintenant.minute.toString().padLeft(2, '0')}'.compareTo(limite) > 0;
    return ResultatScan(statut: StatutScan.enAttenteEnvoi, sens: sens, heure: maintenant, carte: carte, enRetard: retard);
  }

  @override
  Future<int> scansEnAttente() async =>
      (await _file.entreesEnAttente()).where((e) => e.entite == entiteScan).length;

  @override
  Future<void> signalerPortail(String etablissementId, String appareilId) => _executer(() async {
        await _client.rpc<dynamic>('signaler_portail', params: {
          'p_etablissement': etablissementId,
          'p_appareil': appareilId,
          'p_en_attente': await scansEnAttente(),
        });
      });

  // -------------------------------------------------------------------------
  // Direction
  // -------------------------------------------------------------------------
  @override
  Future<ParametresPointage> parametres(String etablissementId) => _lire(
        'parametres',
        etablissementId,
        () => _client.from('parametres_pointage').select().eq('etablissement_id', etablissementId).maybeSingle(),
        (json) => ParametresPointage.depuisJson(json as Map<String, dynamic>?),
      );

  @override
  Future<void> enregistrerParametres(String etablissementId, ParametresPointage parametres) =>
      _executer(() => _client.rpc<dynamic>('enregistrer_parametres_pointage', params: parametres.versParams(etablissementId)));

  @override
  Future<List<CartePortail>> cartesClasse(String classeId, {bool regenerer = false}) => _executer(() async {
        final json = await _client.rpc<dynamic>('cartes_classe', params: {'p_classe': classeId, 'p_regenerer': regenerer});
        return [for (final c in (json as List?) ?? const []) CartePortail.depuisJson(c as Map<String, dynamic>)];
      });

  @override
  Future<void> remplacerCarte(String ficheEleveId) =>
      _executer(() => _client.rpc<dynamic>('remplacer_carte', params: {'p_fiche': ficheEleveId}));

  @override
  Future<PresenceDuJour> presenceDuJour(String etablissementId) => _lire(
        'presence_du_jour',
        etablissementId,
        () => _client.rpc<dynamic>('presence_du_jour', params: {'p_etablissement': etablissementId}),
        (json) => PresenceDuJour.depuisJson(json as Map<String, dynamic>),
      );

  @override
  Future<void> autoriserSortie(String ficheEleveId, DateTime jour, String motif) => _executer(() => _client.rpc<dynamic>(
        'autoriser_sortie',
        params: {'p_fiche': ficheEleveId, 'p_jour': _iso(jour), 'p_motif': motif},
      ));

  @override
  Future<CreditsSms> creditsSms(String etablissementId) => _lire(
        'credits_sms',
        etablissementId,
        () async => {
          'solde': await _client.from('credits_sms').select('solde').eq('etablissement_id', etablissementId).maybeSingle(),
          'mouvements': await _client
              .from('mouvements_credits_sms')
              .select('quantite, motif, reference, created_at')
              .eq('etablissement_id', etablissementId)
              .order('created_at', ascending: false)
              .limit(100),
          'packs': await _client.from('packs_sms').select().eq('actif', true).order('quantite'),
        },
        (json) {
          final j = json! as Map<String, dynamic>;
          return CreditsSms(
            solde: ((j['solde'] as Map<String, dynamic>?)?['solde'] as num?)?.toInt() ?? 0,
            mouvements: [for (final m in (j['mouvements'] as List?) ?? const []) MouvementSms.depuisJson(m as Map<String, dynamic>)],
            packs: [for (final p in (j['packs'] as List?) ?? const []) PackSms.depuisJson(p as Map<String, dynamic>)],
          );
        },
      );

  @override
  Future<Uri> acheterPack(String etablissementId, String pack) => _executer(() async {
        try {
          final reponse = await _client.functions.invoke('initier_paiement_cinetpay', body: {
            'typeObjetPaye': 'pack_sms_etablissement',
            'etablissementId': etablissementId,
            'pack': pack,
          });
          final url = Uri.tryParse((reponse.data as Map<String, dynamic>)['urlPaiement'] as String? ?? '');
          if (url == null || !url.hasScheme) throw const ErreurPointage('URL_PAIEMENT_INDISPONIBLE');
          return url;
        } on FunctionException catch (e) {
          final detail = e.details;
          final code = detail is Map ? (detail['error'] as String? ?? '') : '';
          throw ErreurPointage(code.isEmpty ? 'ERREUR_SERVEUR' : code);
        }
      });

  @override
  Future<ApercuRelances> apercuRelances(String etablissementId) => _lire(
        'apercu_relances',
        etablissementId,
        () => _client.rpc<dynamic>('apercu_relances_impayes', params: {'p_etablissement': etablissementId}),
        (json) => ApercuRelances.depuisJson(json as Map<String, dynamic>),
      );

  @override
  Future<BilanRelance> relancer(String etablissementId, {required bool sms, List<String>? inscriptions}) =>
      _executer(() async {
        final json = await _client.rpc<dynamic>('relancer_impayes', params: {
          'p_etablissement': etablissementId,
          'p_sms': sms,
          'p_inscriptions': inscriptions,
        });
        return BilanRelance.depuisJson(json as Map<String, dynamic>);
      });

  // -------------------------------------------------------------------------
  // Familles
  // -------------------------------------------------------------------------
  @override
  Future<bool> avisArriveeSortie() => _executer(() async {
        final moi = _client.auth.currentUser?.id;
        if (moi == null) return true;
        final ligne = await _client.from('preferences_pointage').select('arrivee_sortie').eq('profile_id', moi).maybeSingle();
        return ligne?['arrivee_sortie'] as bool? ?? true;
      });

  @override
  Future<void> definirAvisArriveeSortie(bool actif) => _executer(() async {
        final moi = _client.auth.currentUser?.id;
        if (moi == null) return;
        await _client.from('preferences_pointage').upsert({'profile_id': moi, 'arrivee_sortie': actif});
      });

  // -------------------------------------------------------------------------
  // GSG
  // -------------------------------------------------------------------------
  @override
  Future<List<PackSms>> tousLesPacks() => _executer(() async {
        final lignes = await _client.from('packs_sms').select().order('quantite');
        return [for (final p in lignes) PackSms.depuisJson(p)];
      });

  @override
  Future<void> definirPack(PackSms pack) => _executer(() => _client.rpc<dynamic>('definir_pack_sms', params: {
        'p_code': pack.code,
        'p_libelle': pack.libelle,
        'p_quantite': pack.quantite,
        'p_prix': pack.prix,
        'p_actif': pack.actif,
      }));

  @override
  Future<List<({String id, String nom, String? ville, int solde})>> soldesEtablissements() => _executer(() async {
        final lignes = await _client
            .from('etablissements')
            .select('id, nom, ville, credits_sms(solde)')
            .isFilter('deleted_at', null)
            .order('nom');
        return [
          for (final l in lignes)
            (
              id: l['id'] as String,
              nom: l['nom'] as String? ?? '',
              ville: l['ville'] as String?,
              solde: _solde(l['credits_sms']),
            ),
        ];
      });

  static int _solde(Object? v) {
    if (v is Map) return (v['solde'] as num?)?.toInt() ?? 0;
    if (v is List && v.isNotEmpty) return ((v.first as Map)['solde'] as num?)?.toInt() ?? 0;
    return 0;
  }

  @override
  Future<int> crediter(String etablissementId, int quantite, String reference) => _executer(() async {
        final solde = await _client.rpc<dynamic>('crediter_sms', params: {
          'p_etablissement': etablissementId,
          'p_quantite': quantite,
          'p_reference': reference,
        });
        return (solde as num).toInt();
      });

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Future<T> _executer<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ErreurPointage {
      rethrow;
    } on PostgrestException catch (e) {
      throw ErreurPointage(codeMetier(e.message) ?? (e.code == '42501' ? 'ACCES_REFUSE' : 'ERREUR_SERVEUR'));
    } catch (e) {
      if (estErreurReseau(e)) throw const ErreurPointage('HORS_CONNEXION');
      rethrow;
    }
  }

  static String? codeMetier(String message) {
    final premier = message.trim().split(RegExp(r'\s+')).first;
    return RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier) ? premier : null;
  }

  /// Rejoue un scan gardé sur le téléphone.
  static Future<void> rejouer(SupabaseClient client, SyncEntree entree) async {
    final params = jsonDecode(entree.payload) as Map<String, dynamic>;
    try {
      // « carte inconnue » ou « doublon » sont des réponses, pas des erreurs :
      // le scan est traité.
      await client.rpc<dynamic>('enregistrer_pointage', params: params);
    } on PostgrestException catch (e) {
      final code = codeMetier(e.message);
      if (code != null || e.code == '42501') {
        final c = code ?? 'ACCES_REFUSE';
        throw RejetDefinitif(c, ErreurPointage(c).messageUtilisateur);
      }
      rethrow;
    }
  }
}
