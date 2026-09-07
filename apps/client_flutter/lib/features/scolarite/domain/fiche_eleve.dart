/// Projection cliente de `public.fiches_eleves` (M2 + enrichissement M5).
///
/// Visible via `fiche_visible()` : personnel de l'établissement, l'élève lié,
/// ou un parent confirmé (contrat M05 §4).
class FicheEleve {
  const FicheEleve({
    required this.id,
    required this.etablissementId,
    required this.matricule,
    required this.nom,
    required this.prenom,
    required this.dateNaissance,
    this.profileId,
    this.lieLe,
    this.sexe,
    this.lieuNaissance,
    this.nationalite,
    this.statut = 'actif',
    this.estSupervise = false,
  });

  factory FicheEleve.depuisJson(Map<String, dynamic> json) {
    return FicheEleve(
      id: json['id'] as String,
      etablissementId: json['etablissement_id'] as String,
      matricule: json['matricule'] as String,
      nom: json['nom'] as String,
      prenom: json['prenom'] as String,
      dateNaissance: DateTime.parse(json['date_naissance'] as String),
      profileId: json['profile_id'] as String?,
      lieLe: json['lie_le'] == null ? null : DateTime.parse(json['lie_le'] as String),
      sexe: json['sexe'] as String?,
      lieuNaissance: json['lieu_naissance'] as String?,
      nationalite: json['nationalite'] as String?,
      statut: json['statut'] as String? ?? 'actif',
      estSupervise: json['est_supervise'] as bool? ?? false,
    );
  }

  Map<String, dynamic> versJson() => {
        'id': id,
        'etablissement_id': etablissementId,
        'matricule': matricule,
        'nom': nom,
        'prenom': prenom,
        'date_naissance': _dateIso(dateNaissance),
        'profile_id': profileId,
        'lie_le': lieLe?.toIso8601String(),
        'sexe': sexe,
        'lieu_naissance': lieuNaissance,
        'nationalite': nationalite,
        'statut': statut,
        'est_supervise': estSupervise,
      };

  final String id;
  final String etablissementId;
  final String matricule;
  final String nom;
  final String prenom;
  final DateTime dateNaissance;
  final String? profileId;
  final DateTime? lieLe;
  final String? sexe;
  final String? lieuNaissance;
  final String? nationalite;
  final String statut;
  final bool estSupervise;

  String get nomComplet => '$prenom $nom';
  bool get estActive => statut == 'actif';

  static String _dateIso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
