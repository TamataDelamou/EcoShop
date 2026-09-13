/// Ligne du tableau par matière d'un bulletin (D5, secondaire uniquement) —
/// RPC serveur `detail_bulletin_matieres` : moyenne déléguée à
/// `calculer_moyenne_eleve` (aucun nouveau calcul côté client), nom et email
/// de l'enseignant affecté (jamais le téléphone, réservé à l'usage interne
/// des responsables scolaires — voir `Employe.telephone`).
class DetailMatiereBulletin {
  const DetailMatiereBulletin({
    required this.matiere,
    this.coefficient,
    this.moyenne,
    this.enseignantNom,
    this.enseignantEmail,
  });

  factory DetailMatiereBulletin.depuisJson(Map<String, dynamic> json) {
    return DetailMatiereBulletin(
      matiere: json['matiere'] as String,
      coefficient: json['coefficient'] as int?,
      moyenne: (json['moyenne'] as num?)?.toDouble(),
      enseignantNom: json['enseignant_nom'] as String?,
      enseignantEmail: json['enseignant_email'] as String?,
    );
  }

  final String matiere;
  final int? coefficient;
  final double? moyenne;
  final String? enseignantNom;
  final String? enseignantEmail;
}
