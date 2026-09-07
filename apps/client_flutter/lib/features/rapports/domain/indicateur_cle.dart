/// Projection cliente de `public.indicateurs_cles` (M10) — KPI pré-calculés
/// par la RPC `consolider_indicateurs_etablissement` (`effectifs`,
/// `taux_reussite`, `absentisme`, `turnover`, `masse_salariale`,
/// `engagement_parents`). Lecture seule côté client : la RPC est le seul
/// point d'écriture légitime (`indicateurs_insert`/`update` exigent
/// `rapports.administrer`, jamais accordée pour une écriture directe
/// depuis l'IHM).
class IndicateurCle {
  const IndicateurCle({
    required this.id,
    required this.etablissementId,
    required this.anneeScolaireId,
    this.periodeId,
    this.classeId,
    required this.code,
    this.valeurNumeric,
    this.valeurTexte,
    required this.calculeLe,
    this.version = 1,
  });

  factory IndicateurCle.depuisJson(Map<String, dynamic> json) => IndicateurCle(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        anneeScolaireId: json['annee_scolaire_id'] as String,
        periodeId: json['periode_id'] as String?,
        classeId: json['classe_id'] as String?,
        code: json['code'] as String,
        valeurNumeric: (json['valeur_numeric'] as num?)?.toDouble(),
        valeurTexte: json['valeur_texte'] as String?,
        calculeLe: DateTime.parse(json['calcule_le'] as String),
        version: json['version'] as int? ?? 1,
      );

  final String id;
  final String etablissementId;
  final String anneeScolaireId;
  final String? periodeId;
  final String? classeId;
  final String code;
  final double? valeurNumeric;
  final String? valeurTexte;
  final DateTime calculeLe;
  final int version;

  String get libelle => switch (code) {
        'effectifs' => 'Effectifs',
        'taux_reussite' => 'Taux de réussite',
        'absentisme' => 'Absentéisme',
        'turnover' => 'Turn-over RH',
        'masse_salariale' => 'Masse salariale',
        'engagement_parents' => 'Engagement des parents',
        _ => code,
      };

  /// Vrai pour les indicateurs exprimés en proportion (0-1) — affichage en %.
  bool get estUnTaux =>
      const {'taux_reussite', 'absentisme', 'turnover', 'engagement_parents'}.contains(code);
}
