import 'enums_vie_scolaire.dart';

/// Projection cliente de `public.alertes_decrochage` (M7) — signal IA à
/// validation humaine obligatoire (contrat M07 §5, jamais un verdict).
///
/// Invisible à l'élève/parent tant que [statut] n'est pas `transmise`
/// (`alerte_visible`) : le client ne doit jamais présumer d'un accès plus
/// large que ce que RLS accorde déjà.
class AlerteDecrochage {
  const AlerteDecrochage({
    required this.id,
    required this.etablissementId,
    required this.ficheEleveId,
    required this.anneeScolaireId,
    required this.score,
    required this.dateCalcul,
    this.seuil = 0.6,
    this.facteurs = const {},
    this.statut = StatutAlerte.ouverte,
    this.transmiseLe,
    this.traiteePar,
    this.nomEleve,
  });

  factory AlerteDecrochage.depuisJson(Map<String, dynamic> json) {
    final fiche = json['fiches_eleves'] as Map<String, dynamic>?;
    return AlerteDecrochage(
      id: json['id'] as String,
      etablissementId: json['etablissement_id'] as String,
      ficheEleveId: json['fiche_eleve_id'] as String,
      anneeScolaireId: json['annee_scolaire_id'] as String,
      score: (json['score'] as num).toDouble(),
      dateCalcul: DateTime.parse(json['date_calcul'] as String),
      seuil: (json['seuil'] as num?)?.toDouble() ?? 0.6,
      facteurs: (json['facteurs'] as Map<String, dynamic>?) ?? const {},
      statut: StatutAlerte.depuisCode(json['statut'] as String?),
      transmiseLe: json['transmise_le'] == null ? null : DateTime.parse(json['transmise_le'] as String),
      traiteePar: json['traitee_par'] as String?,
      nomEleve: fiche == null ? null : '${fiche['prenom']} ${fiche['nom']}',
    );
  }

  final String id;
  final String etablissementId;
  final String ficheEleveId;
  final String anneeScolaireId;
  final double score;
  final DateTime dateCalcul;
  final double seuil;
  final Map<String, dynamic> facteurs;
  final StatutAlerte statut;
  final DateTime? transmiseLe;
  final String? traiteePar;

  /// Peuplé via l'embed `fiches_eleves(prenom, nom)` — affichage uniquement.
  final String? nomEleve;
}
