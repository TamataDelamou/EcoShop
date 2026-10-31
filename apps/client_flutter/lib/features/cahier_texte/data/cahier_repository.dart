import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/providers.dart';
import '../../../core/sync/drift_sync_repository.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_providers.dart';
import '../../revision/domain/concours.dart';
import '../domain/cahier.dart';

/// Bucket privé des pièces jointes (migration 20260906001596).
const bucketCahierTexte = 'cahier-texte';

class ErreurCahier implements Exception {
  const ErreurCahier(this.code);

  final String code;

  String get message => switch (code) {
        'HORS_LIGNE' => 'Pas de réseau pour le moment. Réessayez une fois connecté.',
        'PERMISSION_REFUSEE' => 'Action réservée aux enseignants de la classe et à la direction.',
        'QUESTION_NON_PUBLIEE' => 'Une question choisie n’est plus publiée.',
        'DEVOIR_DEJA_COMMENCE' => 'Des élèves ont commencé ce devoir : ses questions ne changent plus.',
        'DEJA_REMIS' => 'Ce devoir a déjà été remis.',
        'DEVOIR_A_REMETTRE' => 'Un devoir numérique se fait dans EcoShop, puis se remet.',
        'FICHIER_TROP_LOURD' => 'Fichier trop lourd (5 Mo au plus).',
        _ => 'Action impossible pour le moment. Réessayez.',
      };

  @override
  String toString() => code;
}

/// Cahier de texte, travail à faire, devoirs numériques (REG-40).
///
/// Hors connexion d'abord : les listes sont gardées sur le téléphone ; une
/// séance, un travail, un « fait » ou une copie de devoir écrits sans réseau
/// partent au retour du réseau (file d'envoi, écran Synchronisation).
class CahierRepository {
  CahierRepository(this._client, this._lecture, this._file);

  final SupabaseClient _client;
  final LectureHorsLigne _lecture;
  final DriftSyncRepository _file;

  static const entiteSeance = 'cahier_seance';
  static const entiteTravail = 'cahier_travail';
  static const entiteFait = 'travail_fait';
  static const entiteRemise = 'devoir_remise';
  static const entites = [entiteSeance, entiteTravail, entiteFait, entiteRemise];

  static ErreurCahier traduire(Object e) {
    if (e is ErreurCahier) return e;
    if (estErreurReseau(e)) return const ErreurCahier('HORS_LIGNE');
    if (e is PostgrestException) {
      final premier = e.message.trim().split(RegExp(r'\s+')).first;
      if (RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier)) return ErreurCahier(premier);
      if (e.code == '42501') return const ErreurCahier('PERMISSION_REFUSEE');
    }
    return const ErreurCahier('ERREUR_SERVEUR');
  }

  Future<T> _f<T>(Future<T> Function() a) async {
    try {
      return await a();
    } catch (e) {
      throw traduire(e);
    }
  }

  /// Opérations encore dans la file pour une entité (écrites sans réseau).
  Future<List<Map<String, dynamic>>> _enAttente(String entite) async {
    try {
      return [
        for (final e in await _file.entreesEnAttente())
          if (e.entite == entite) (jsonDecode(e.payload) as Map).cast<String, dynamic>(),
      ];
    } catch (_) {
      return const [];
    }
  }

  // ------------------------------------------------------------ enseignant

  Future<List<Seance>> seancesClasse(String classeId) async {
    final lues = await _f(() => _lecture.lire(
          type: 'cahier_seances',
          cle: classeId,
          source: () async => await _client
              .from('cahier_texte')
              .select('*, programmes_matieres(nom), chapitres_matiere(titre)')
              .eq('classe_id', classeId)
              .isFilter('deleted_at', null)
              .order('date_seance', ascending: false)
              .limit(150),
          decoder: (j) => [for (final x in (j as List? ?? const [])) Seance.depuisJson((x as Map).cast<String, dynamic>())],
        ));
    final attente = [
      for (final p in await _enAttente(entiteSeance))
        if (p['classe_id'] == classeId) Seance.depuisJson({...p, '_en_attente': true}),
    ];
    final ids = {for (final s in attente) s.id};
    return [...attente, for (final s in lues) if (!ids.contains(s.id)) s]..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<List<Travail>> travauxClasse(String classeId) async {
    final depuis = jourIso(DateTime.now().subtract(const Duration(days: 60)));
    final lus = await _f(() => _lecture.lire(
          type: 'cahier_travaux',
          cle: classeId,
          source: () async => await _client
              .from('travaux')
              .select('*, programmes_matieres(nom)')
              .eq('classe_id', classeId)
              .isFilter('deleted_at', null)
              .gte('pour_le', depuis)
              .order('pour_le', ascending: false),
          decoder: (j) => [for (final x in (j as List? ?? const [])) Travail.depuisJson((x as Map).cast<String, dynamic>())],
        ));
    final attente = [
      for (final p in await _enAttente(entiteTravail))
        if (p['classe_id'] == classeId) Travail.depuisJson({...p, '_en_attente': true}),
    ];
    final ids = {for (final t in attente) t.id};
    return [...attente, for (final t in lus) if (!ids.contains(t.id)) t]..sort((a, b) => b.pourLe.compareTo(a.pourLe));
  }

  /// Enregistre (crée ou modifie) une séance ; sans réseau, elle part au
  /// retour. Renvoie vrai si elle est déjà sur le serveur.
  Future<bool> enregistrerSeance(Seance s) => _ecrire(entiteSeance, 'cahier_texte', s.versLigne());

  Future<bool> enregistrerTravail(Travail t) => _ecrire(entiteTravail, 'travaux', t.versLigne());

  Future<bool> _ecrire(String entite, String table, Map<String, dynamic> ligne) async {
    try {
      await _client.from(table).upsert(ligne);
      return true;
    } catch (e) {
      if (!estErreurReseau(e)) throw traduire(e);
    }
    await _file.enfiler(SyncEntree(id: '$entite:${ligne['id']}', entite: entite, operation: 'upsert', payload: jsonEncode(ligne)));
    return false;
  }

  Future<void> retirerSeance(String id) => _f(() => _client
      .from('cahier_texte')
      .update({'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id));

  Future<void> retirerTravail(String id) => _f(() => _client
      .from('travaux')
      .update({'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id));

  Future<SuiviTravail> suivi(String travailId) => _f(() async =>
      SuiviTravail.depuisJson(((await _client.rpc<dynamic>('suivi_travail', params: {'p_travail': travailId})) as Map)
          .cast<String, dynamic>()));

  Future<int> relancer(String travailId) =>
      _f(() async => ((await _client.rpc<dynamic>('relancer_travail', params: {'p_travail': travailId})) as num).toInt());

  Future<List<QuestionProposeeDevoir>> questionsPourDevoir(String matiereId, {String? chapitreId}) => _f(() async {
        final r = await _client.rpc<dynamic>('questions_pour_devoir', params: {'p_matiere': matiereId, 'p_chapitre': chapitreId});
        return [for (final x in (r as List? ?? const [])) QuestionProposeeDevoir.depuisJson((x as Map).cast<String, dynamic>())];
      });

  Future<List<AvancementCahier>> avancement(String etablissementId) => _f(() => _lecture.lire(
        type: 'cahier_avancement',
        cle: etablissementId,
        source: () => _client.rpc<dynamic>('avancement_cahier', params: {'p_etablissement': etablissementId}),
        decoder: (j) =>
            [for (final x in (j as List? ?? const [])) AvancementCahier.depuisJson((x as Map).cast<String, dynamic>())],
      ));

  /// Choisit un fichier (PDF, image, document) et le dépose dans le dossier
  /// de la classe ; null si l'utilisateur annule.
  Future<PieceJointe?> ajouterPieceJointe({required String etablissementId, required String classeId}) async {
    final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'doc', 'docx', 'mp3', 'm4a'],
    );
    if (f == null) return null;
    final Uint8List octets = await f.readAsBytes();
    if (octets.length > 5 * 1024 * 1024) throw const ErreurCahier('FICHIER_TROP_LOURD');
    final ext = (f.extension ?? 'pdf').toLowerCase();
    final chemin = '$etablissementId/$classeId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _f(() => _client.storage.from(bucketCahierTexte).uploadBinary(
          chemin,
          octets,
          fileOptions: FileOptions(
            contentType: switch (ext) {
              'png' => 'image/png',
              'webp' => 'image/webp',
              'jpg' || 'jpeg' => 'image/jpeg',
              'mp3' => 'audio/mpeg',
              'm4a' => 'audio/mp4',
              'doc' => 'application/msword',
              'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
              _ => 'application/pdf',
            },
          ),
        ));
    return PieceJointe(chemin: chemin, nom: f.name);
  }

  /// Lien temporaire (1 h) pour ouvrir une pièce jointe.
  Future<String> lienPieceJointe(String chemin) =>
      _f(() => _client.storage.from(bucketCahierTexte).createSignedUrl(chemin, 3600));

  // ------------------------------------------------------------ famille

  Future<List<TravailEleve>> travauxFiche(String ficheId) async {
    final depuis = jourIso(DateTime.now().subtract(const Duration(days: 30)));
    final lus = await _f(() => _lecture.lire(
          type: 'travaux_fiche',
          cle: ficheId,
          source: () => _client.rpc<dynamic>('travaux_fiche', params: {'p_fiche': ficheId, 'p_depuis': depuis}),
          decoder: TravailEleve.liste,
        ));
    // « Fait » cochés sans réseau : déjà montrés comme tels.
    final faits = {
      for (final p in await _enAttente(entiteFait))
        if (p['p_fiche'] == ficheId) '${p['p_travail']}': p,
    };
    final remis = {
      for (final p in await _enAttente(entiteRemise))
        if (p['p_fiche'] == ficheId) '${p['p_travail']}',
    };
    return [
      for (final t in lus)
        if (faits[t.id] case final p?)
          t.avecFait(p['p_fait'] == true ? DateTime.tryParse('${p['p_quand']}') ?? DateTime.now() : null)
        else if (remis.contains(t.id))
          TravailEleve.depuisJson({
            'id': t.id, 'type': t.type.code, 'titre': t.titre, 'pour_le': jourIso(t.pourLe), 'matiere': t.matiere,
            'nb_questions': t.nbQuestions, 'remis_le': DateTime.now().toIso8601String(),
          })
        else
          t,
    ];
  }

  Future<List<Seance>> cahierFiche(String ficheId) => _f(() => _lecture.lire(
        type: 'cahier_fiche',
        cle: ficheId,
        source: () => _client.rpc<dynamic>('cahier_fiche', params: {'p_fiche': ficheId}),
        decoder: (j) => [for (final x in (j as List? ?? const [])) Seance.depuisJson((x as Map).cast<String, dynamic>())],
      ));

  /// « Fait » coché ou décoché par l'élève ou le parent ; part au retour du
  /// réseau s'il manque.
  Future<void> marquerFait(String travailId, String ficheId, bool fait) async {
    final params = {
      'p_travail': travailId,
      'p_fiche': ficheId,
      'p_fait': fait,
      'p_quand': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      await _client.rpc<dynamic>('marquer_travail_fait', params: params);
      return;
    } catch (e) {
      if (!estErreurReseau(e)) throw traduire(e);
    }
    await _file.enfiler(SyncEntree(
      id: '$entiteFait:$travailId:$ficheId',
      entite: entiteFait,
      operation: 'rpc',
      payload: jsonEncode(params),
    ));
  }

  /// Sujet d'un devoir. Sans durée : gardé sur le téléphone, faisable sans
  /// réseau. Avec une durée : le chronomètre part à l'ouverture (réseau requis).
  Future<SujetManche> sujetDevoir(String travailId, String ficheId, {required bool chronometre}) => _f(() async {
        if (chronometre) {
          final r = await _client.rpc<dynamic>('sujet_devoir',
              params: {'p_travail': travailId, 'p_fiche': ficheId, 'p_commencer': true});
          return _sujet(r);
        }
        return _lecture.lire(
          type: 'sujet_devoir',
          cle: '$travailId.$ficheId',
          source: () => _client.rpc<dynamic>('sujet_devoir',
              params: {'p_travail': travailId, 'p_fiche': ficheId, 'p_commencer': false}),
          decoder: _sujet,
        );
      });

  static SujetManche _sujet(Object? r) {
    final j = ((r as Map?) ?? const {}).cast<String, dynamic>();
    final limite = j['limite'];
    return SujetManche.depuisJson({
      ...j,
      // Sans durée : pas de limite (affichage sans chronomètre).
      'limite': limite ?? DateTime.now().add(const Duration(days: 3650)).toIso8601String(),
      'commence_le': j['commence_le'] ?? DateTime.now().toIso8601String(),
    });
  }

  /// Remet la copie ; sans réseau, elle est gardée et envoyée au retour.
  Future<ResultatManche> remettreDevoir(
    String travailId,
    String ficheId,
    Map<String, Object?> reponses,
    int nbQuestions,
    int dureeS,
  ) async {
    final params = {
      'p_travail': travailId,
      'p_fiche': ficheId,
      'p_reponses': _json(reponses),
      'p_duree_s': dureeS,
      'p_remis_le': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      final r = await _client.rpc<dynamic>('remettre_devoir', params: params);
      return ResultatManche.depuisJson((r as Map).cast<String, dynamic>());
    } catch (e) {
      if (!estErreurReseau(e)) throw traduire(e);
    }
    await _file.enfiler(SyncEntree(
      id: '$entiteRemise:$travailId:$ficheId',
      entite: entiteRemise,
      operation: 'rpc',
      payload: jsonEncode(params),
    ));
    return ResultatManche(score: 0, questions: nbQuestions, enAttente: true);
  }

  /// Correction d'un devoir déjà remis.
  Future<ResultatManche> correction(String travailId, String ficheId) => _f(() async {
        final r = await _client.rpc<dynamic>('correction_devoir', params: {'p_travail': travailId, 'p_fiche': ficheId});
        return ResultatManche.depuisJson((r as Map).cast<String, dynamic>());
      });

  Future<void> purger() => _lecture.purger();

  static Object? _json(Object? d) {
    if (d is Set) return d.toList();
    if (d is Map) return d.map((k, v) => MapEntry('$k', _json(v)));
    if (d is List) return [for (final x in d) _json(x)];
    return d;
  }

  // ------------------------------------------------------------ file d'envoi

  static Future<void> rejouer(SupabaseClient client, SyncEntree entree) async {
    final p = (jsonDecode(entree.payload) as Map).cast<String, dynamic>();
    try {
      switch (entree.entite) {
        case entiteSeance:
          await client.from('cahier_texte').upsert(p);
        case entiteTravail:
          await client.from('travaux').upsert(p);
        case entiteFait:
          await client.rpc<dynamic>('marquer_travail_fait', params: p);
        case entiteRemise:
          await client.rpc<dynamic>('remettre_devoir', params: p);
      }
    } catch (e) {
      if (estErreurReseau(e)) rethrow;
      final err = traduire(e);
      throw RejetDefinitif(err.code, err.message);
    }
  }

  static String libelle(SyncEntree entree) => switch (entree.entite) {
        entiteSeance => 'Séance du cahier de texte',
        entiteTravail => 'Travail à faire',
        entiteFait => 'Travail coché « fait »',
        _ => 'Copie de devoir',
      };
}

final lectureCahierProvider = Provider<LectureHorsLigne>((ref) => LectureHorsLigne(
      CacheDocumentStore(ref.watch(databaseProvider), 'cahier_texte_hl'),
      ref.watch(fraicheurHorsLigneProvider),
    ));

final cahierRepositoryProvider = Provider<CahierRepository>((ref) => CahierRepository(
      ref.watch(supabaseClientProvider),
      ref.watch(lectureCahierProvider),
      ref.watch(syncRepositoryProvider),
    ));

final seancesClasseProvider = FutureProvider.autoDispose.family<List<Seance>, String>((ref, classeId) {
  ref.watch(suiviSyncProvider);
  return ref.watch(cahierRepositoryProvider).seancesClasse(classeId);
});

final travauxClasseProvider = FutureProvider.autoDispose.family<List<Travail>, String>((ref, classeId) {
  ref.watch(suiviSyncProvider);
  return ref.watch(cahierRepositoryProvider).travauxClasse(classeId);
});

final suiviTravailProvider = FutureProvider.autoDispose.family<SuiviTravail, String>(
  (ref, travailId) => ref.watch(cahierRepositoryProvider).suivi(travailId),
);

final travauxFicheProvider = FutureProvider.autoDispose.family<List<TravailEleve>, String>((ref, ficheId) {
  ref.watch(suiviSyncProvider);
  return ref.watch(cahierRepositoryProvider).travauxFiche(ficheId);
});

final cahierFicheProvider = FutureProvider.autoDispose.family<List<Seance>, String>(
  (ref, ficheId) => ref.watch(cahierRepositoryProvider).cahierFiche(ficheId),
);

final avancementCahierProvider = FutureProvider.autoDispose.family<List<AvancementCahier>, String>(
  (ref, etablissementId) => ref.watch(cahierRepositoryProvider).avancement(etablissementId),
);
