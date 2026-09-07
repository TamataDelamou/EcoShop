import 'enums_vie_scolaire.dart';

/// Projection cliente de `public.evenements_scolaires` (M7) — calendrier des
/// événements affectant la présence attendue (`predire_presence`).
class EvenementScolaire {
  const EvenementScolaire({
    required this.id,
    required this.etablissementId,
    required this.anneeScolaireId,
    required this.type,
    required this.libelle,
    required this.dateDebut,
    required this.dateFin,
    this.impactPresence = 0,
    this.source,
  });

  factory EvenementScolaire.depuisJson(Map<String, dynamic> json) {
    return EvenementScolaire(
      id: json['id'] as String,
      etablissementId: json['etablissement_id'] as String,
      anneeScolaireId: json['annee_scolaire_id'] as String,
      type: TypeEvenement.depuisCode(json['type'] as String?),
      libelle: json['libelle'] as String,
      dateDebut: DateTime.parse(json['date_debut'] as String),
      dateFin: DateTime.parse(json['date_fin'] as String),
      impactPresence: (json['impact_presence'] as num?)?.toDouble() ?? 0,
      source: json['source'] as String?,
    );
  }

  Map<String, dynamic> versJsonCache() => {
        'id': id,
        'etablissement_id': etablissementId,
        'annee_scolaire_id': anneeScolaireId,
        'type': type.code,
        'libelle': libelle,
        'date_debut': dateDebut.toIso8601String(),
        'date_fin': dateFin.toIso8601String(),
        'impact_presence': impactPresence,
        'source': source,
      };

  factory EvenementScolaire.depuisJsonCache(Map<String, dynamic> json) => EvenementScolaire(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        anneeScolaireId: json['annee_scolaire_id'] as String,
        type: TypeEvenement.depuisCode(json['type'] as String?),
        libelle: json['libelle'] as String,
        dateDebut: DateTime.parse(json['date_debut'] as String),
        dateFin: DateTime.parse(json['date_fin'] as String),
        impactPresence: (json['impact_presence'] as num?)?.toDouble() ?? 0,
        source: json['source'] as String?,
      );

  final String id;
  final String etablissementId;
  final String anneeScolaireId;
  final TypeEvenement type;
  final String libelle;
  final DateTime dateDebut;
  final DateTime dateFin;
  final double impactPresence;
  final String? source;
}
