import 'arborescence_niveau.dart';
import 'arborescence_pays.dart';
import 'paquet_referentiel.dart';
import 'pays_pedagogique.dart';
import 'systeme_educatif.dart';

/// Erreur métier du référentiel pédagogique, à code stable.
class ErreurReferentiel implements Exception {
  const ErreurReferentiel(this.code, [this.detail]);

  final String code;
  final String? detail;

  @override
  String toString() => 'ErreurReferentiel($code)';
}

/// Port de lecture du référentiel pédagogique CEDEAO (M4).
///
/// Module en **lecture seule côté client** (contrat M04 §3-4) : aucune
/// méthode d'écriture n'existe ici, l'édition passe exclusivement par le
/// back-office / `service_role`. Chaque implémentation doit fonctionner hors
/// connexion en retombant sur le cache local (ch. §5, repli SQLite/Drift).
abstract interface class ReferentielRepository {
  /// Les 4 familles de systèmes éducatifs (invariant du modèle).
  Future<List<SystemeEducatif>> systemesEducatifs();

  /// Pays pédagogiques déployés (RLS : `statut_deploiement = 'deploye'`).
  Future<List<PaysPedagogique>> paysPedagogiques();

  /// Cycles, niveaux et examens publiés d'un pays.
  Future<ArborescencePays> arborescencePays(String paysCode);

  /// Filières, programmes et matières publiés d'un niveau.
  Future<ArborescenceNiveau> arborescenceNiveau(String niveauId);

  /// Paquets de téléchargement hors-ligne publiés pour un pays (et,
  /// optionnellement, restreints à un niveau).
  Future<List<PaquetReferentiel>> paquetsDisponibles({
    required String paysCode,
    String? niveauId,
  });
}
