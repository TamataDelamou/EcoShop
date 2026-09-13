import 'enums_rh.dart';

/// Projection cliente de `public.employes` (M8) — dossier RH adossé au compte
/// (`profiles`). Lecture seule côté client (aucune écriture hors-ligne :
/// création/édition d'un dossier RH est une action de bureau, toujours en
/// ligne, cf. `RhRepository.creerOuModifierEmploye`).
class Employe {
  const Employe({
    required this.id,
    required this.etablissementId,
    required this.profileId,
    required this.matricule,
    this.categorie = CategorieEmploye.personnel,
    required this.dateEmbauche,
    this.statut = StatutEmploye.actif,
    this.nomAffiche,
    this.telephone,
    this.email,
  });

  factory Employe.depuisJson(Map<String, dynamic> json) {
    final profil = json['profiles'] as Map<String, dynamic>?;
    return Employe(
      id: json['id'] as String,
      etablissementId: json['etablissement_id'] as String,
      profileId: json['profile_id'] as String,
      matricule: json['matricule'] as String,
      categorie: CategorieEmploye.depuisCode(json['categorie'] as String?),
      dateEmbauche: DateTime.parse(json['date_embauche'] as String),
      statut: StatutEmploye.depuisCode(json['statut'] as String?),
      nomAffiche: profil == null ? null : '${profil['prenom']} ${profil['nom']}',
      telephone: json['telephone'] as String?,
      email: json['email'] as String?,
    );
  }

  factory Employe.depuisJsonCache(Map<String, dynamic> json) => Employe(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        profileId: json['profile_id'] as String,
        matricule: json['matricule'] as String,
        categorie: CategorieEmploye.depuisCode(json['categorie'] as String?),
        dateEmbauche: DateTime.parse(json['date_embauche'] as String),
        statut: StatutEmploye.depuisCode(json['statut'] as String?),
        nomAffiche: json['nom_affiche'] as String?,
        telephone: json['telephone'] as String?,
        email: json['email'] as String?,
      );

  Map<String, dynamic> versJsonCache() => {
        'id': id,
        'etablissement_id': etablissementId,
        'profile_id': profileId,
        'matricule': matricule,
        'categorie': categorie.code,
        'date_embauche': _dateIso(dateEmbauche),
        'statut': statut.code,
        'nom_affiche': nomAffiche,
        'telephone': telephone,
        'email': email,
      };

  /// Colonnes réelles de `public.employes` — pour la création/édition.
  Map<String, dynamic> versJsonEcriture() => {
        'id': id,
        'etablissement_id': etablissementId,
        'profile_id': profileId,
        'matricule': matricule,
        'categorie': categorie.code,
        'date_embauche': _dateIso(dateEmbauche),
        'statut': statut.code,
        'telephone': telephone,
        'email': email,
      };

  final String id;
  final String etablissementId;
  final String profileId;
  final String matricule;
  final CategorieEmploye categorie;
  final DateTime dateEmbauche;
  final StatutEmploye statut;

  /// Peuplé via l'embed `profiles(prenom, nom)` — affichage uniquement.
  final String? nomAffiche;

  /// Contact professionnel interne, à l'usage des responsables scolaires
  /// (D5) — jamais imprimé sur un document distribué aux familles.
  final String? telephone;

  /// Ce qui apparaît sur le bulletin (tableau par matière, D5) — décision
  /// explicite du porteur de projet, qui écarte le téléphone (personnel vs
  /// professionnel) de tout document distribué à une classe entière.
  final String? email;

  static String _dateIso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
