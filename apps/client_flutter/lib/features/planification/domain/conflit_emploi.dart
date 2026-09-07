/// Conflit d'occupation détecté par la RPC `detecter_conflits_emploi` (IA
/// descriptive) — deux séances qui se chevauchent sur la même ressource
/// (salle, enseignant ou classe). Signal à arbitrer humainement : aucune
/// séance n'est déplacée automatiquement.
class ConflitEmploi {
  const ConflitEmploi({
    required this.type,
    required this.emploiAId,
    required this.emploiBId,
    required this.jourSemaine,
    required this.heureDebut,
    required this.heureFin,
  });

  factory ConflitEmploi.depuisJson(Map<String, dynamic> json) => ConflitEmploi(
        type: json['type'] as String,
        emploiAId: json['a'] as String,
        emploiBId: json['b'] as String,
        jourSemaine: json['jour_semaine'] as int,
        heureDebut: (json['heure_debut'] as String).substring(0, 5),
        heureFin: (json['heure_fin'] as String).substring(0, 5),
      );

  /// `salle`, `enseignant` ou `classe` — ressource en conflit.
  final String type;
  final String emploiAId;
  final String emploiBId;
  final int jourSemaine;
  final String heureDebut;
  final String heureFin;
}
