import 'enums_vie_scolaire.dart';

/// Projection cliente de `public.sanctions` (M7) — éducative, jamais
/// punitive par défaut ; une origine `ia` exige une validation humaine avant
/// tout statut autre que `proposee` (trigger `sanctions_verifie_validation`,
/// contrat M07 §5 — éthique IA).
class Sanction {
  const Sanction({
    required this.id,
    required this.etablissementId,
    required this.ficheEleveId,
    required this.anneeScolaireId,
    required this.typeSanction,
    required this.motif,
    required this.dateDebut,
    required this.decisionnaireId,
    this.contexteEducatif,
    this.dateFin,
    this.origine = OrigineSanction.humaine,
    this.recommandationIa,
    this.valideePar,
    this.valideeLe,
    this.statut = StatutSanction.proposee,
  });

  factory Sanction.depuisJson(Map<String, dynamic> json) {
    return Sanction(
      id: json['id'] as String,
      etablissementId: json['etablissement_id'] as String,
      ficheEleveId: json['fiche_eleve_id'] as String,
      anneeScolaireId: json['annee_scolaire_id'] as String,
      typeSanction: TypeSanction.depuisCode(json['type_sanction'] as String?),
      motif: json['motif'] as String,
      dateDebut: DateTime.parse(json['date_debut'] as String),
      decisionnaireId: json['decisionnaire_id'] as String,
      contexteEducatif: json['contexte_educatif'] as String?,
      dateFin: json['date_fin'] == null ? null : DateTime.parse(json['date_fin'] as String),
      origine: OrigineSanction.depuisCode(json['origine'] as String?),
      recommandationIa: json['recommandation_ia'] as Map<String, dynamic>?,
      valideePar: json['validee_par'] as String?,
      valideeLe: json['validee_le'] == null ? null : DateTime.parse(json['validee_le'] as String),
      statut: StatutSanction.depuisCode(json['statut'] as String?),
    );
  }

  Map<String, dynamic> versJsonCache() => {
        'id': id,
        'etablissement_id': etablissementId,
        'fiche_eleve_id': ficheEleveId,
        'annee_scolaire_id': anneeScolaireId,
        'type_sanction': typeSanction.code,
        'motif': motif,
        'date_debut': dateDebut.toIso8601String(),
        'decisionnaire_id': decisionnaireId,
        'contexte_educatif': contexteEducatif,
        'date_fin': dateFin?.toIso8601String(),
        'origine': origine.code,
        'recommandation_ia': recommandationIa,
        'validee_par': valideePar,
        'validee_le': valideeLe?.toIso8601String(),
        'statut': statut.code,
      };

  final String id;
  final String etablissementId;
  final String ficheEleveId;
  final String anneeScolaireId;
  final TypeSanction typeSanction;
  final String motif;
  final DateTime dateDebut;
  final String decisionnaireId;
  final String? contexteEducatif;
  final DateTime? dateFin;
  final OrigineSanction origine;
  final Map<String, dynamic>? recommandationIa;
  final String? valideePar;
  final DateTime? valideeLe;
  final StatutSanction statut;

  bool get estPropositionIaNonValidee => origine == OrigineSanction.ia && valideePar == null;
}
