/// Une entrée de l'historique des restrictions déclenchées par PARENT IA
/// (`public.parent_ia_historique`) — écrite UNIQUEMENT par
/// `enregistrer_restriction_parent_ia` (SECURITY DEFINER), jamais par le
/// client. Consultée en lecture seule par le parent et par l'élève.
class RestrictionParentIa {
  const RestrictionParentIa({
    required this.id,
    required this.appConcernee,
    required this.tempsUsageMinutes,
    required this.niveauRisqueEchec,
    required this.sourceDonnee,
    required this.createdAt,
    this.matiereARisque,
  });

  final String id;
  final String appConcernee;
  final int tempsUsageMinutes;

  /// 0-100 — score de risque d'échec réutilisé (`risque_reussite_actuel`,
  /// sous-livrable 1/7), jamais recalculé pour ce module.
  final int niveauRisqueEchec;
  final String? matiereARisque;

  /// 'declaration_manuelle' uniquement pour cette passe — 'auto_android'
  /// reste un écart documenté séparément (voir rapport 4/7).
  final String sourceDonnee;
  final DateTime createdAt;

  factory RestrictionParentIa.depuisJson(Map<String, dynamic> json) =>
      RestrictionParentIa(
        id: json['id'] as String,
        appConcernee: json['app_concernee'] as String,
        tempsUsageMinutes: json['temps_usage_minutes'] as int,
        niveauRisqueEchec: json['niveau_risque_echec'] as int,
        matiereARisque: json['matiere_a_risque'] as String?,
        sourceDonnee: json['source_donnee'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
