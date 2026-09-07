import 'enums_planification.dart';

/// Projection cliente de `public.emplois_du_temps` (M11) — créneau
/// hebdomadaire récurrent. Porte le facteur Last-Write-Wins d'une
/// modification hors-ligne (`modifieLe`/`deviceId`), même principe que
/// `presences` (M7) : dernière écriture gagne, pas de fusion de champs.
class EmploiDuTemps {
  const EmploiDuTemps({
    required this.id,
    required this.etablissementId,
    required this.anneeScolaireId,
    required this.classeId,
    this.enseignantProfileId,
    this.programmeMatiereId,
    this.salleId,
    required this.jourSemaine,
    required this.heureDebut,
    required this.heureFin,
    this.type = TypeSeance.cours,
    this.modifieLe,
    this.deviceId,
    this.nomEnseignant,
    this.nomMatiere,
    this.libelleSalle,
    this.nomClasse,
  });

  factory EmploiDuTemps.depuisJson(Map<String, dynamic> json) {
    final enseignant = json['profiles'] as Map<String, dynamic>?;
    final matiere = json['programmes_matieres'] as Map<String, dynamic>?;
    final salle = json['salles'] as Map<String, dynamic>?;
    final classe = json['classes'] as Map<String, dynamic>?;
    return EmploiDuTemps(
      id: json['id'] as String,
      etablissementId: json['etablissement_id'] as String,
      anneeScolaireId: json['annee_scolaire_id'] as String,
      classeId: json['classe_id'] as String,
      enseignantProfileId: json['enseignant_profile_id'] as String?,
      programmeMatiereId: json['programme_matiere_id'] as String?,
      salleId: json['salle_id'] as String?,
      jourSemaine: json['jour_semaine'] as int,
      heureDebut: _tronquerHeure(json['heure_debut'] as String),
      heureFin: _tronquerHeure(json['heure_fin'] as String),
      type: TypeSeance.depuisCode(json['type'] as String?),
      modifieLe: json['modifie_le'] == null ? null : DateTime.parse(json['modifie_le'] as String),
      deviceId: json['device_id'] as String?,
      nomEnseignant: enseignant == null
          ? null
          : [enseignant['prenom'], enseignant['nom']].where((v) => v != null && (v as String).isNotEmpty).join(' '),
      nomMatiere: matiere?['nom'] as String?,
      libelleSalle: salle?['code'] as String?,
      nomClasse: classe?['nom'] as String?,
    );
  }

  factory EmploiDuTemps.depuisJsonCache(Map<String, dynamic> json) => EmploiDuTemps(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        anneeScolaireId: json['annee_scolaire_id'] as String,
        classeId: json['classe_id'] as String,
        enseignantProfileId: json['enseignant_profile_id'] as String?,
        programmeMatiereId: json['programme_matiere_id'] as String?,
        salleId: json['salle_id'] as String?,
        jourSemaine: json['jour_semaine'] as int,
        heureDebut: json['heure_debut'] as String,
        heureFin: json['heure_fin'] as String,
        type: TypeSeance.depuisCode(json['type'] as String?),
        modifieLe: json['modifie_le'] == null ? null : DateTime.parse(json['modifie_le'] as String),
        deviceId: json['device_id'] as String?,
        nomEnseignant: json['nom_enseignant'] as String?,
        nomMatiere: json['nom_matiere'] as String?,
        libelleSalle: json['libelle_salle'] as String?,
        nomClasse: json['nom_classe'] as String?,
      );

  Map<String, dynamic> versJsonCache() => {
        'id': id,
        'etablissement_id': etablissementId,
        'annee_scolaire_id': anneeScolaireId,
        'classe_id': classeId,
        'enseignant_profile_id': enseignantProfileId,
        'programme_matiere_id': programmeMatiereId,
        'salle_id': salleId,
        'jour_semaine': jourSemaine,
        'heure_debut': heureDebut,
        'heure_fin': heureFin,
        'type': type.code,
        'modifie_le': modifieLe?.toIso8601String(),
        'device_id': deviceId,
        'nom_enseignant': nomEnseignant,
        'nom_matiere': nomMatiere,
        'libelle_salle': libelleSalle,
        'nom_classe': nomClasse,
      };

  /// Colonnes réelles de `public.emplois_du_temps` — pour l'upsert
  /// (contrainte `idx_emplois_creneau_unique`).
  Map<String, dynamic> versJsonEcriture() => {
        'id': id,
        'etablissement_id': etablissementId,
        'annee_scolaire_id': anneeScolaireId,
        'classe_id': classeId,
        'enseignant_profile_id': enseignantProfileId,
        'programme_matiere_id': programmeMatiereId,
        'salle_id': salleId,
        'jour_semaine': jourSemaine,
        'heure_debut': heureDebut,
        'heure_fin': heureFin,
        'type': type.code,
        'modifie_le': (modifieLe ?? DateTime.now()).toIso8601String(),
        'device_id': deviceId,
      };

  factory EmploiDuTemps.depuisJsonEcriture(Map<String, dynamic> json) => EmploiDuTemps(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        anneeScolaireId: json['annee_scolaire_id'] as String,
        classeId: json['classe_id'] as String,
        enseignantProfileId: json['enseignant_profile_id'] as String?,
        programmeMatiereId: json['programme_matiere_id'] as String?,
        salleId: json['salle_id'] as String?,
        jourSemaine: json['jour_semaine'] as int,
        heureDebut: json['heure_debut'] as String,
        heureFin: json['heure_fin'] as String,
        type: TypeSeance.depuisCode(json['type'] as String?),
        modifieLe: json['modifie_le'] == null ? null : DateTime.parse(json['modifie_le'] as String),
        deviceId: json['device_id'] as String?,
      );

  final String id;
  final String etablissementId;
  final String anneeScolaireId;
  final String classeId;
  final String? enseignantProfileId;
  final String? programmeMatiereId;
  final String? salleId;

  /// 1 = lundi … 7 = dimanche (cohérent avec le CHECK serveur `between 1 and 7`).
  final int jourSemaine;

  /// Format `HH:mm`.
  final String heureDebut;
  final String heureFin;
  final TypeSeance type;
  final DateTime? modifieLe;
  final String? deviceId;

  /// Peuplés via les embeds PostgREST — affichage uniquement.
  final String? nomEnseignant;
  final String? nomMatiere;
  final String? libelleSalle;
  final String? nomClasse;

  static String _tronquerHeure(String heure) => heure.length >= 5 ? heure.substring(0, 5) : heure;
}
