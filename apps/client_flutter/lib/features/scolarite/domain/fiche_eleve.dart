/// Projection cliente de `public.fiches_eleves` (M2 + enrichissement M5,
/// champs administratifs complémentaires M15quater).
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
    this.numeroClasse,
    this.nomPere,
    this.nomMere,
    this.quartier,
    this.personneUrgenceNom,
    this.personneUrgenceTelephone,
    this.redoublant = false,
    this.telephoneEleve,
    this.telephonePere,
    this.telephoneMere,
    this.tuteurNom,
    this.tuteurLien,
    this.tuteurTelephone,
    this.handicapPrecision,
    this.ecoleOrigine,
    this.matriculeNational,
    this.photoChemin,
    this.situationHandicap = false,
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
      numeroClasse: json['numero_classe'] as int?,
      nomPere: json['nom_pere'] as String?,
      nomMere: json['nom_mere'] as String?,
      quartier: json['quartier'] as String?,
      personneUrgenceNom: json['personne_urgence_nom'] as String?,
      personneUrgenceTelephone: json['personne_urgence_telephone'] as String?,
      redoublant: json['redoublant'] as bool? ?? false,
      telephoneEleve: json['telephone_eleve'] as String?,
      telephonePere: json['telephone_pere'] as String?,
      telephoneMere: json['telephone_mere'] as String?,
      tuteurNom: json['tuteur_nom'] as String?,
      tuteurLien: json['tuteur_lien'] as String?,
      tuteurTelephone: json['tuteur_telephone'] as String?,
      handicapPrecision: json['handicap_precision'] as String?,
      ecoleOrigine: json['ecole_origine'] as String?,
      matriculeNational: json['matricule_national'] as String?,
      photoChemin: json['photo_chemin'] as String?,
      situationHandicap: json['situation_handicap'] as bool? ?? false,
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
        'numero_classe': numeroClasse,
        'nom_pere': nomPere,
        'nom_mere': nomMere,
        'quartier': quartier,
        'personne_urgence_nom': personneUrgenceNom,
        'personne_urgence_telephone': personneUrgenceTelephone,
        'redoublant': redoublant,
        'telephone_eleve': telephoneEleve,
        'telephone_pere': telephonePere,
        'telephone_mere': telephoneMere,
        'tuteur_nom': tuteurNom,
        'tuteur_lien': tuteurLien,
        'tuteur_telephone': tuteurTelephone,
        'handicap_precision': handicapPrecision,
        'ecole_origine': ecoleOrigine,
        'matricule_national': matriculeNational,
        'photo_chemin': photoChemin,
        'situation_handicap': situationHandicap,
      };

  /// Colonnes modifiables par une mise à jour administrative du dossier
  /// (jamais `matricule`/`profile_id`, qui suivent leurs propres règles).
  Map<String, dynamic> versJsonMiseAJourAdmin() => {
        'numero_classe': numeroClasse,
        'nom_pere': nomPere,
        'nom_mere': nomMere,
        'quartier': quartier,
        'personne_urgence_nom': personneUrgenceNom,
        'personne_urgence_telephone': personneUrgenceTelephone,
        'redoublant': redoublant,
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

  /// Numéro de l'élève dans la liste de sa classe (usage administratif).
  final int? numeroClasse;
  final String? nomPere;
  final String? nomMere;
  final String? quartier;
  final String? personneUrgenceNom;
  final String? personneUrgenceTelephone;
  final bool redoublant;

  // Fiche d'inscription complète (REG-39).
  final String? telephoneEleve;
  final String? telephonePere;
  final String? telephoneMere;
  final String? tuteurNom;
  final String? tuteurLien;
  final String? tuteurTelephone;
  final String? handicapPrecision;
  final String? ecoleOrigine;
  final String? matriculeNational;
  final String? photoChemin;
  final bool situationHandicap;

  String get nomComplet => '$prenom $nom';
  bool get estActive => statut == 'actif';

  static String _dateIso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
