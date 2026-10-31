import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_providers.dart';

/// Tableau d'honneur (REG-39, migration 20260906001595) : les trois
/// premiers de chaque classe d'après les bulletins publiés, et les
/// distinctions décernées par la direction (meilleur professeur, prix
/// d'excellence…). Gardé sur le téléphone pour la lecture sans réseau.
class EleveHonneur {
  const EleveHonneur({
    required this.classeNom,
    required this.nom,
    required this.rang,
    this.moyenne,
    this.effectif,
  });

  factory EleveHonneur.depuisJson(Map<String, dynamic> j) => EleveHonneur(
        classeNom: j['classe_nom'] as String? ?? 'Classe',
        nom: '${j['prenom'] ?? ''} ${j['nom'] ?? ''}'.trim(),
        rang: (j['rang'] as num?)?.toInt() ?? 0,
        moyenne: (j['moyenne'] as num?)?.toDouble(),
        effectif: (j['effectif'] as num?)?.toInt(),
      );

  final String classeNom;
  final String nom;
  final int rang;
  final double? moyenne;
  final int? effectif;
}

class Distinction {
  const Distinction({required this.id, required this.categorie, required this.titre, required this.nom, this.motif});

  factory Distinction.depuisJson(Map<String, dynamic> j) => Distinction(
        id: j['id'] as String,
        categorie: j['categorie'] as String? ?? 'eleve',
        titre: j['titre'] as String? ?? '',
        nom: (j['nom'] as String?)?.trim().isNotEmpty == true ? j['nom'] as String : 'Sans nom',
        motif: j['motif'] as String?,
      );

  final String id;

  /// `eleve`, `enseignant` ou `personnel`.
  final String categorie;
  final String titre;
  final String nom;
  final String? motif;
}

class TableauHonneur {
  const TableauHonneur({this.eleves = const [], this.distinctions = const []});

  factory TableauHonneur.depuisJson(Map<String, dynamic> j) => TableauHonneur(
        eleves: [for (final e in (j['eleves'] as List? ?? const [])) EleveHonneur.depuisJson((e as Map).cast<String, dynamic>())],
        distinctions: [
          for (final d in (j['distinctions'] as List? ?? const [])) Distinction.depuisJson((d as Map).cast<String, dynamic>()),
        ],
      );

  final List<EleveHonneur> eleves;
  final List<Distinction> distinctions;
}

class TableauHonneurRepository {
  TableauHonneurRepository(this._client, this._lecture);

  final SupabaseClient _client;
  final LectureHorsLigne _lecture;

  Future<TableauHonneur> lire({required String etablissementId, required String anneeId, String? periodeId}) =>
      _lecture.lire(
        type: 'tableau_honneur',
        cle: '$etablissementId.$anneeId.${periodeId ?? 'annee'}',
        source: () => _client.rpc<dynamic>('tableau_honneur', params: {
          'p_etablissement': etablissementId,
          'p_annee': anneeId,
          'p_periode': periodeId,
        }),
        decoder: (j) => TableauHonneur.depuisJson(((j as Map?) ?? const {}).cast<String, dynamic>()),
      );

  Future<void> decerner({
    required String etablissementId,
    required String anneeId,
    String? periodeId,
    required String categorie,
    String? ficheEleveId,
    String? profileId,
    required String titre,
    String? motif,
  }) async {
    try {
      await _client.from('distinctions').insert({
        'etablissement_id': etablissementId,
        'annee_scolaire_id': anneeId,
        'periode_id': periodeId,
        'categorie': categorie,
        'fiche_eleve_id': ficheEleveId,
        'profile_id': profileId,
        'titre': titre.trim(),
        if (motif != null && motif.trim().isNotEmpty) 'motif': motif.trim(),
      });
    } on PostgrestException {
      throw Exception('Enregistrement impossible pour le moment. Vérifiez votre connexion.');
    }
  }

  Future<void> retirer(String distinctionId) async {
    await _client
        .from('distinctions')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', distinctionId);
  }

  Future<void> purger() => _lecture.purger();
}

final tableauHonneurRepositoryProvider = Provider<TableauHonneurRepository>((ref) => TableauHonneurRepository(
      ref.watch(supabaseClientProvider),
      LectureHorsLigne(CacheDocumentStore(ref.watch(databaseProvider), 'tableau_honneur_hl'), ref.watch(fraicheurHorsLigneProvider)),
    ));

typedef ParamsHonneur = ({String etablissementId, String anneeId, String? periodeId});

final tableauHonneurProvider = FutureProvider.autoDispose.family<TableauHonneur, ParamsHonneur>(
  (ref, p) => ref.watch(tableauHonneurRepositoryProvider).lire(
        etablissementId: p.etablissementId,
        anneeId: p.anneeId,
        periodeId: p.periodeId,
      ),
);
