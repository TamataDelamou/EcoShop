import 'enums_notes.dart';

/// Projection cliente de `public.appreciations` (M6) — commentaires de bulletin.
class Appreciation {
  const Appreciation({
    required this.id,
    required this.etablissementId,
    required this.ficheEleveId,
    required this.anneeScolaireId,
    required this.texte,
    required this.redigePar,
    this.periodeId,
    this.programmeMatiereId,
    this.type = TypeAppreciation.generale,
    this.ton,
    this.pointsForts = const [],
    this.pointsFaibles = const [],
    this.nomMatiere,
  });

  factory Appreciation.depuisJson(Map<String, dynamic> json) {
    final matiere = json['programmes_matieres'] as Map<String, dynamic>?;
    return Appreciation(
      id: json['id'] as String,
      etablissementId: json['etablissement_id'] as String,
      ficheEleveId: json['fiche_eleve_id'] as String,
      anneeScolaireId: json['annee_scolaire_id'] as String,
      texte: json['texte'] as String,
      redigePar: json['redige_par'] as String,
      periodeId: json['periode_id'] as String?,
      programmeMatiereId: json['programme_matiere_id'] as String?,
      type: TypeAppreciation.depuisCode(json['type'] as String?),
      ton: TonAppreciation.depuisCode(json['ton'] as String?),
      pointsForts: (json['points_forts'] as List<dynamic>?)?.cast<String>() ?? const [],
      pointsFaibles: (json['points_faibles'] as List<dynamic>?)?.cast<String>() ?? const [],
      nomMatiere: matiere?['nom'] as String?,
    );
  }

  final String id;
  final String etablissementId;
  final String ficheEleveId;
  final String anneeScolaireId;
  final String texte;
  final String redigePar;
  final String? periodeId;
  final String? programmeMatiereId;
  final TypeAppreciation type;
  final TonAppreciation? ton;
  final List<String> pointsForts;
  final List<String> pointsFaibles;

  /// Peuplé via l'embed `programmes_matieres(nom)` — affichage uniquement.
  final String? nomMatiere;
}
