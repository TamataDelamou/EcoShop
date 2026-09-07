import 'classe.dart';
import 'enums_scolarite.dart';

/// Projection cliente de `public.affectations_enseignants` (M5).
class AffectationEnseignant {
  const AffectationEnseignant({
    required this.id,
    required this.etablissementId,
    required this.anneeScolaireId,
    required this.enseignantProfileId,
    required this.classeId,
    this.programmeMatiereId,
    this.roleAffectation = RoleAffectation.enseignant,
    this.volumeHoraireHebdo,
    this.nomEnseignant,
    this.nomMatiere,
    this.classe,
  });

  factory AffectationEnseignant.depuisJson(Map<String, dynamic> json) {
    final enseignant = json['profiles'] as Map<String, dynamic>?;
    final matiere = json['programmes_matieres'] as Map<String, dynamic>?;
    final classeJson = json['classes'] as Map<String, dynamic>?;
    return AffectationEnseignant(
      id: json['id'] as String,
      etablissementId: json['etablissement_id'] as String,
      anneeScolaireId: json['annee_scolaire_id'] as String,
      enseignantProfileId: json['enseignant_profile_id'] as String,
      classeId: json['classe_id'] as String,
      programmeMatiereId: json['programme_matiere_id'] as String?,
      roleAffectation: RoleAffectation.depuisCode(json['role_affectation'] as String?),
      volumeHoraireHebdo: json['volume_horaire_hebdo'] as int?,
      nomEnseignant: enseignant == null
          ? null
          : [enseignant['prenom'], enseignant['nom']]
              .where((v) => v != null && (v as String).isNotEmpty)
              .join(' '),
      nomMatiere: matiere?['nom'] as String?,
      classe: classeJson == null ? null : Classe.depuisJson(classeJson),
    );
  }

  /// Sérialisation plate pour le cache local (symétrique de [depuisJsonCache]) —
  /// distincte de la lecture réseau, qui vient sous forme d'embed PostgREST.
  Map<String, dynamic> versJsonCache() => {
        'id': id,
        'etablissement_id': etablissementId,
        'annee_scolaire_id': anneeScolaireId,
        'enseignant_profile_id': enseignantProfileId,
        'classe_id': classeId,
        'programme_matiere_id': programmeMatiereId,
        'role_affectation': roleAffectation.code,
        'volume_horaire_hebdo': volumeHoraireHebdo,
        'nom_enseignant': nomEnseignant,
        'nom_matiere': nomMatiere,
        'classe': classe?.versJson(),
      };

  factory AffectationEnseignant.depuisJsonCache(Map<String, dynamic> json) {
    final classeJson = json['classe'] as Map<String, dynamic>?;
    return AffectationEnseignant(
      id: json['id'] as String,
      etablissementId: json['etablissement_id'] as String,
      anneeScolaireId: json['annee_scolaire_id'] as String,
      enseignantProfileId: json['enseignant_profile_id'] as String,
      classeId: json['classe_id'] as String,
      programmeMatiereId: json['programme_matiere_id'] as String?,
      roleAffectation: RoleAffectation.depuisCode(json['role_affectation'] as String?),
      volumeHoraireHebdo: json['volume_horaire_hebdo'] as int?,
      nomEnseignant: json['nom_enseignant'] as String?,
      nomMatiere: json['nom_matiere'] as String?,
      classe: classeJson == null ? null : Classe.depuisJson(classeJson),
    );
  }

  final String id;
  final String etablissementId;
  final String anneeScolaireId;
  final String enseignantProfileId;
  final String classeId;
  final String? programmeMatiereId;
  final RoleAffectation roleAffectation;
  final int? volumeHoraireHebdo;

  /// Peuplés via l'embed PostgREST (`profiles`, `programmes_matieres`) — non
  /// persistés tels quels, purement d'affichage (voir [versJsonCache] pour la
  /// forme plate utilisée par le cache local).
  final String? nomEnseignant;
  final String? nomMatiere;

  /// Peuplée uniquement par `mesAffectations()` (embed `classes(*)`) — sert à
  /// naviguer directement vers le détail de la classe depuis « Mes classes ».
  final Classe? classe;
}
