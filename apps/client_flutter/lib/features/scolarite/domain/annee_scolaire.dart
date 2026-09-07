/// Projection cliente de `public.annees_scolaires` (M1).
class AnneeScolaire {
  const AnneeScolaire({
    required this.id,
    required this.etablissementId,
    required this.libelle,
    required this.dateDebut,
    required this.dateFin,
    this.courante = false,
    this.cloturee = false,
  });

  factory AnneeScolaire.depuisJson(Map<String, dynamic> json) {
    return AnneeScolaire(
      id: json['id'] as String,
      etablissementId: json['etablissement_id'] as String,
      libelle: json['libelle'] as String,
      dateDebut: DateTime.parse(json['date_debut'] as String),
      dateFin: DateTime.parse(json['date_fin'] as String),
      courante: json['courante'] as bool? ?? false,
      cloturee: json['cloturee'] as bool? ?? false,
    );
  }

  Map<String, dynamic> versJson() => {
        'id': id,
        'etablissement_id': etablissementId,
        'libelle': libelle,
        'date_debut': dateDebut.toIso8601String(),
        'date_fin': dateFin.toIso8601String(),
        'courante': courante,
        'cloturee': cloturee,
      };

  final String id;
  final String etablissementId;
  final String libelle;
  final DateTime dateDebut;
  final DateTime dateFin;
  final bool courante;
  final bool cloturee;
}
