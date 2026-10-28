import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_providers.dart';
import '../../configuration/domain/configuration.dart';
import '../../etablissement/domain/etablissement.dart';

/// École en service, vue par l'Administrateur GSG (`gsg_ecoles`).
class EcoleGsg {
  const EcoleGsg({
    required this.id,
    required this.nom,
    required this.slug,
    this.paysCode,
    this.ville,
    this.deviseCode = 'GNF',
    this.statut = 'actif',
    this.logoChemin,
    this.couleurIdentite,
    this.slogan,
    this.creeLe,
    this.valideLe,
    this.telephone,
    this.email,
    this.direction,
    this.eleves = 0,
    this.classes = 0,
    this.personnel = 0,
    this.parents = 0,
    this.comptesActifs30j = 0,
    this.derniereActivite,
  });

  factory EcoleGsg.depuisJson(Map<String, dynamic> j) {
    DateTime? d(Object? v) => v == null ? null : DateTime.tryParse(v as String)?.toLocal();
    int n(Object? v) => (v as num?)?.toInt() ?? 0;
    return EcoleGsg(
      id: j['id'] as String,
      nom: j['nom'] as String,
      slug: j['slug'] as String? ?? '',
      paysCode: j['pays_code'] as String?,
      ville: j['ville'] as String?,
      deviseCode: j['devise_code'] as String? ?? 'GNF',
      statut: j['statut'] as String? ?? 'actif',
      logoChemin: j['logo_chemin'] as String?,
      couleurIdentite: j['couleur_identite'] as String?,
      slogan: j['slogan'] as String?,
      creeLe: d(j['cree_le']),
      valideLe: d(j['valide_le']),
      telephone: j['telephone'] as String?,
      email: j['email'] as String?,
      direction: j['direction'] as String?,
      eleves: n(j['eleves']),
      classes: n(j['classes']),
      personnel: n(j['personnel']),
      parents: n(j['parents']),
      comptesActifs30j: n(j['comptes_actifs_30j']),
      derniereActivite: d(j['derniere_activite']),
    );
  }

  final String id;
  final String nom;
  final String slug;
  final String? paysCode;
  final String? ville;
  final String deviseCode;
  final String statut;
  final String? logoChemin;
  final String? couleurIdentite;
  final String? slogan;
  final DateTime? creeLe;
  final DateTime? valideLe;
  final String? telephone;
  final String? email;
  final String? direction;
  final int eleves;
  final int classes;
  final int personnel;
  final int parents;
  final int comptesActifs30j;
  final DateTime? derniereActivite;

  String get localisation => [ville, paysCode].whereType<String>().where((v) => v.isNotEmpty).join(' · ');

  Etablissement versEtablissement() => Etablissement(
        id: id,
        nom: nom,
        slug: slug,
        paysCode: paysCode,
        ville: ville,
        deviseCode: deviseCode,
        couleurIdentite: couleurIdentite,
        logoChemin: logoChemin,
        slogan: slogan,
      );
}

/// Tableau de bord d'une école (`gsg_tableau_ecole`).
class TableauEcole {
  const TableauEcole(this.brut);

  final Map<String, dynamic> brut;

  Map<String, dynamic> _bloc(String cle) => ((brut[cle] as Map?) ?? const {}).cast<String, dynamic>();
  int _n(Map<String, dynamic> m, String cle) => (m[cle] as num?)?.toInt() ?? 0;

  String? get annee => brut['annee'] as String?;
  Map<String, dynamic> get demande => _bloc('demande');
  Map<String, dynamic> get effectifs => _bloc('effectifs');
  Map<String, dynamic> get utilisation => _bloc('utilisation');
  Map<String, dynamic> get finances => _bloc('finances');

  int effectif(String cle) => _n(effectifs, cle);
  int usage(String cle) => _n(utilisation, cle);

  Map<String, int> get parRole => {
        for (final e in ((effectifs['par_role'] as Map?) ?? const {}).entries) e.key as String: (e.value as num).toInt(),
      };

  /// Actions (appels, notes, pointages, reçus) des 30 derniers jours.
  List<({DateTime jour, int actions})> get parJour => [
        for (final x in (utilisation['par_jour'] as List? ?? const []))
          (
            jour: DateTime.parse((x as Map)['jour'] as String),
            actions: (x['actions'] as num?)?.toInt() ?? 0,
          ),
      ];

  EtatConfiguration get configuration =>
      EtatConfiguration.depuisJson(((brut['configuration'] as Map?) ?? const {}).cast<String, dynamic>());
}

class EcolesGsgRepository {
  EcolesGsgRepository(this._client, this._lecture);

  final SupabaseClient _client;
  final LectureHorsLigne _lecture;

  Future<List<EcoleGsg>> ecoles() => _lecture.lire(
        type: 'ecoles_gsg',
        cle: 'toutes',
        source: () => _client.rpc<dynamic>('gsg_ecoles'),
        decoder: (j) => [for (final x in (j as List)) EcoleGsg.depuisJson((x as Map).cast<String, dynamic>())],
      );

  Future<TableauEcole> tableau(String etablissementId) => _lecture.lire(
        type: 'tableau_ecole_gsg',
        cle: etablissementId,
        source: () => _client.rpc<dynamic>('gsg_tableau_ecole', params: {'p_etablissement': etablissementId}),
        decoder: (j) => TableauEcole(((j as Map?) ?? const {}).cast<String, dynamic>()),
      );
}

final lectureEcolesGsgProvider = Provider<LectureHorsLigne>((ref) {
  return LectureHorsLigne(
    CacheDocumentStore(ref.watch(databaseProvider), 'ecoles_gsg_hl'),
    ref.watch(fraicheurHorsLigneProvider),
  );
});

final ecolesGsgRepositoryProvider = Provider<EcolesGsgRepository>((ref) {
  return EcolesGsgRepository(ref.watch(supabaseClientProvider), ref.watch(lectureEcolesGsgProvider));
});

final ecolesGsgProvider = FutureProvider.autoDispose<List<EcoleGsg>>((ref) {
  return ref.watch(ecolesGsgRepositoryProvider).ecoles();
});

final tableauEcoleGsgProvider = FutureProvider.autoDispose.family<TableauEcole, String>((ref, id) {
  return ref.watch(ecolesGsgRepositoryProvider).tableau(id);
});
