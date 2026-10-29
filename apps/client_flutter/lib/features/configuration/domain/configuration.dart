import '../../planification/domain/moteur_emploi_du_temps.dart';
import '../../../core/format/coefficient.dart';
import '../../referentiel/domain/programme_matiere.dart';

/// Où en est la mise en route d'un établissement (REG-23) — réponse de
/// `etat_configuration_etablissement`.
class EtatConfiguration {
  const EtatConfiguration({
    this.anneeId,
    this.anneeLibelle,
    this.anneeCourante = false,
    this.periodes = 0,
    this.classes = 0,
    this.classesSansNiveau = 0,
    this.groupes = 0,
    this.salles = 0,
    this.frais = 0,
    this.personnel = 0,
    this.enseignants = 0,
    this.affectations = 0,
    this.classesSansAffectation = 0,
    this.grilleHoraire = false,
    this.seances = 0,
    this.elevesInscrits = 0,
    this.campagneInscription = false,
    this.identiteVisuelle = false,
    this.slogan = false,
    this.paiementMobile = false,
    this.niveauxClasses = 0,
    this.niveauxSansMatieres = 0,
  });

  factory EtatConfiguration.depuisJson(Map<String, dynamic> j) {
    final annee = j['annee'] as Map<String, dynamic>?;
    int n(String cle) => (j[cle] as num?)?.toInt() ?? 0;
    bool b(String cle) => j[cle] as bool? ?? false;
    return EtatConfiguration(
      anneeId: annee?['id'] as String?,
      anneeLibelle: annee?['libelle'] as String?,
      anneeCourante: annee?['courante'] as bool? ?? false,
      periodes: n('periodes'),
      classes: n('classes'),
      classesSansNiveau: n('classes_sans_niveau'),
      groupes: n('groupes'),
      salles: n('salles'),
      frais: n('frais'),
      personnel: n('personnel'),
      enseignants: n('enseignants'),
      affectations: n('affectations'),
      classesSansAffectation: n('classes_sans_affectation'),
      grilleHoraire: b('grille_horaire'),
      seances: n('seances'),
      elevesInscrits: n('eleves_inscrits'),
      campagneInscription: b('campagne_inscription'),
      identiteVisuelle: b('identite_visuelle'),
      slogan: b('slogan'),
      paiementMobile: b('paiement_mobile'),
      niveauxClasses: n('niveaux_classes'),
      niveauxSansMatieres: n('niveaux_sans_matieres'),
    );
  }

  final String? anneeId;
  final String? anneeLibelle;
  final bool anneeCourante;
  final int periodes;
  final int classes;
  final int classesSansNiveau;
  final int groupes;
  final int salles;
  final int frais;
  final int personnel;
  final int enseignants;
  final int affectations;
  final int classesSansAffectation;
  final bool grilleHoraire;
  final int seances;
  final int elevesInscrits;
  final bool campagneInscription;
  final bool identiteVisuelle;
  final bool slogan;
  final bool paiementMobile;

  /// Couples niveau-série des classes de l'année (REG-33).
  final int niveauxClasses;

  /// Couples niveau-série sans aucune matière (ni programme de l'école, ni
  /// programme national) : pas de cours ni de notes possibles.
  final int niveauxSansMatieres;
}

/// Groupe pédagogique : partie de classe (demi-classe, langue, option,
/// soutien) ou groupe de plusieurs classes.
class GroupePedagogique {
  const GroupePedagogique({
    required this.id,
    required this.etablissementId,
    required this.anneeScolaireId,
    this.classeId,
    required this.nom,
    this.type = 'demi_classe',
    this.capacite,
    this.effectif = 0,
  });

  factory GroupePedagogique.depuisJson(Map<String, dynamic> j) {
    final membres = j['groupes_membres'];
    return GroupePedagogique(
      id: j['id'] as String,
      etablissementId: j['etablissement_id'] as String,
      anneeScolaireId: j['annee_scolaire_id'] as String,
      classeId: j['classe_id'] as String?,
      nom: j['nom'] as String,
      type: j['type'] as String? ?? 'demi_classe',
      capacite: j['capacite'] as int?,
      effectif: membres is List && membres.isNotEmpty
          ? ((membres.first as Map)['count'] as num?)?.toInt() ?? 0
          : (j['effectif'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> versJson() => {
        'id': id,
        'etablissement_id': etablissementId,
        'annee_scolaire_id': anneeScolaireId,
        'classe_id': classeId,
        'nom': nom,
        'type': type,
        'capacite': capacite,
        'effectif': effectif,
      };

  Map<String, dynamic> versJsonEcriture() => {
        'id': id,
        'etablissement_id': etablissementId,
        'annee_scolaire_id': anneeScolaireId,
        'classe_id': classeId,
        'nom': nom.trim(),
        'type': type,
        'capacite': capacite,
      };

  final String id;
  final String etablissementId;
  final String anneeScolaireId;
  final String? classeId;
  final String nom;
  final String type;
  final int? capacite;
  final int effectif;

  static const types = {
    'demi_classe': 'Demi-classe (TP, atelier)',
    'langue': 'Langue vivante',
    'option': 'Option',
    'soutien': 'Soutien, remédiation',
    'autre': 'Autre',
  };

  String get libelleType => types[type] ?? 'Groupe';
}

/// Cours à donner : un enseignant, une classe (ou un groupe), une matière,
/// un volume par semaine — l'« affectation » de M5, enrichie pour l'emploi
/// du temps (REG-24).
class AffectationCours {
  const AffectationCours({
    required this.id,
    required this.etablissementId,
    required this.anneeScolaireId,
    required this.enseignantId,
    required this.classeId,
    this.matiereId,
    this.groupeId,
    this.heuresParSemaine,
    this.dureeSeance = 60,
    this.salleId,
    this.nomEnseignant,
    this.nomMatiere,
    this.coefficient,
  });

  factory AffectationCours.depuisJson(Map<String, dynamic> j) {
    final p = j['profiles'] as Map<String, dynamic>?;
    final m = j['programmes_matieres'] as Map<String, dynamic>?;
    return AffectationCours(
      id: j['id'] as String,
      etablissementId: j['etablissement_id'] as String,
      anneeScolaireId: j['annee_scolaire_id'] as String,
      enseignantId: j['enseignant_profile_id'] as String,
      classeId: j['classe_id'] as String,
      matiereId: j['programme_matiere_id'] as String?,
      groupeId: j['groupe_id'] as String?,
      heuresParSemaine: j['volume_horaire_hebdo'] as int?,
      dureeSeance: j['duree_seance'] as int? ?? 60,
      salleId: j['salle_id'] as String?,
      nomEnseignant: p == null
          ? j['nom_enseignant'] as String?
          : [p['prenom'], p['nom']].where((v) => v != null && (v as String).isNotEmpty).join(' '),
      nomMatiere: m?['nom'] as String? ?? j['nom_matiere'] as String?,
      coefficient: lireCoefficient(m?['coefficient'] ?? j['coefficient']),
    );
  }

  Map<String, dynamic> versJson() => {
        'id': id,
        'etablissement_id': etablissementId,
        'annee_scolaire_id': anneeScolaireId,
        'enseignant_profile_id': enseignantId,
        'classe_id': classeId,
        'programme_matiere_id': matiereId,
        'groupe_id': groupeId,
        'volume_horaire_hebdo': heuresParSemaine,
        'duree_seance': dureeSeance,
        'salle_id': salleId,
        'nom_enseignant': nomEnseignant,
        'nom_matiere': nomMatiere,
        'coefficient': coefficient,
      };

  Map<String, dynamic> versJsonEcriture() => {
        'id': id,
        'etablissement_id': etablissementId,
        'annee_scolaire_id': anneeScolaireId,
        'enseignant_profile_id': enseignantId,
        'classe_id': classeId,
        'programme_matiere_id': matiereId,
        'groupe_id': groupeId,
        'volume_horaire_hebdo': heuresParSemaine,
        'duree_seance': dureeSeance,
        'salle_id': salleId,
        'role_affectation': 'enseignant',
      };

  final String id;
  final String etablissementId;
  final String anneeScolaireId;
  final String enseignantId;
  final String classeId;
  final String? matiereId;
  final String? groupeId;
  final int? heuresParSemaine;
  final int dureeSeance;
  final String? salleId;
  final String? nomEnseignant;
  final String? nomMatiere;
  final double? coefficient;
}

/// Membre du personnel (liste `membres_personnel`).
class MembrePersonnel {
  const MembrePersonnel({required this.profileId, required this.nomComplet, required this.role, this.poste, this.actif = true});

  factory MembrePersonnel.depuisJson(Map<String, dynamic> j) => MembrePersonnel(
        profileId: j['profile_id'] as String,
        nomComplet: (j['nom_complet'] as String? ?? '').trim().isEmpty ? 'Sans nom' : (j['nom_complet'] as String).trim(),
        role: j['role'] as String? ?? '',
        poste: j['poste'] as String?,
        actif: j['actif'] as bool? ?? true,
      );

  Map<String, dynamic> versJson() =>
      {'profile_id': profileId, 'nom_complet': nomComplet, 'role': role, 'poste': poste, 'actif': actif};

  final String profileId;
  final String nomComplet;
  final String role;
  final String? poste;
  final bool actif;

  /// Peut recevoir des cours : enseignants, et Direction qui enseigne.
  bool get peutEnseigner => actif && (role == 'enseignant' || role == 'direction');
}

/// Grille horaire de l'année (REG-24).
class GrilleHoraire {
  const GrilleHoraire({
    this.id,
    required this.etablissementId,
    required this.anneeScolaireId,
    required this.jours,
    required this.creneaux,
    this.demiJourneesLibres = const {},
    this.regles = const ReglesEmploi(),
  });

  /// Grille de départ courante en Guinée : du lundi au samedi matin,
  /// récréation à 10 h, pause de midi.
  factory GrilleHoraire.parDefaut(String etablissementId, String anneeId) => GrilleHoraire(
        etablissementId: etablissementId,
        anneeScolaireId: anneeId,
        jours: const [1, 2, 3, 4, 5, 6],
        creneaux: const [
          CreneauEmploi(debut: '08:00', fin: '09:00'),
          CreneauEmploi(debut: '09:00', fin: '10:00'),
          CreneauEmploi(debut: '10:00', fin: '10:15', cours: false, libelle: 'Récréation'),
          CreneauEmploi(debut: '10:15', fin: '11:15'),
          CreneauEmploi(debut: '11:15', fin: '12:15'),
          CreneauEmploi(debut: '12:15', fin: '14:00', cours: false, libelle: 'Pause de midi'),
          CreneauEmploi(debut: '14:00', fin: '15:00'),
          CreneauEmploi(debut: '15:00', fin: '16:00'),
        ],
        demiJourneesLibres: const {6: 'apres_midi'},
      );

  factory GrilleHoraire.depuisJson(Map<String, dynamic> j) => GrilleHoraire(
        id: j['id'] as String?,
        etablissementId: j['etablissement_id'] as String,
        anneeScolaireId: j['annee_scolaire_id'] as String,
        jours: [for (final x in (j['jours'] as List? ?? const [])) (x as num).toInt()],
        creneaux: [
          for (final c in (j['creneaux'] as List? ?? const [])) CreneauEmploi.depuisJson((c as Map).cast<String, dynamic>()),
        ],
        demiJourneesLibres: {
          for (final e in ((j['demi_journees_libres'] as Map?) ?? const {}).entries)
            int.parse(e.key.toString()): e.value as String,
        },
        regles: ReglesEmploi.depuisJson((j['regles'] as Map?)?.cast<String, dynamic>()),
      );

  Map<String, dynamic> versJson() => {
        if (id != null) 'id': id,
        'etablissement_id': etablissementId,
        'annee_scolaire_id': anneeScolaireId,
        'jours': jours,
        'creneaux': [for (final c in creneaux) c.versJson()],
        'demi_journees_libres': {for (final e in demiJourneesLibres.entries) '${e.key}': e.value},
        'regles': regles.versJson(),
      };

  GrilleHoraire copier({
    List<int>? jours,
    List<CreneauEmploi>? creneaux,
    Map<int, String>? demiJourneesLibres,
    ReglesEmploi? regles,
  }) =>
      GrilleHoraire(
        id: id,
        etablissementId: etablissementId,
        anneeScolaireId: anneeScolaireId,
        jours: jours ?? this.jours,
        creneaux: creneaux ?? this.creneaux,
        demiJourneesLibres: demiJourneesLibres ?? this.demiJourneesLibres,
        regles: regles ?? this.regles,
      );

  final String? id;
  final String etablissementId;
  final String anneeScolaireId;
  final List<int> jours;
  final List<CreneauEmploi> creneaux;
  final Map<int, String> demiJourneesLibres;
  final ReglesEmploi regles;

  int get heuresDeCoursParSemaine {
    final minutes = creneaux.where((c) => c.cours).fold<int>(0, (s, c) => s + c.minutes) * jours.length;
    return minutes ~/ 60;
  }
}

/// Indisponibilité enregistrée (`contraintes_emploi`).
class Indisponibilite {
  const Indisponibilite({
    required this.id,
    required this.etablissementId,
    required this.anneeScolaireId,
    this.enseignantId,
    this.classeId,
    this.salleId,
    this.jour,
    this.debut,
    this.fin,
    this.raison,
  });

  factory Indisponibilite.depuisJson(Map<String, dynamic> j) {
    String? h(Object? v) => v == null ? null : (v as String).substring(0, 5);
    return Indisponibilite(
      id: j['id'] as String,
      etablissementId: j['etablissement_id'] as String,
      anneeScolaireId: j['annee_scolaire_id'] as String,
      enseignantId: j['enseignant_profile_id'] as String?,
      classeId: j['classe_id'] as String?,
      salleId: j['salle_id'] as String?,
      jour: j['jour_semaine'] as int?,
      debut: h(j['heure_debut']),
      fin: h(j['heure_fin']),
      raison: j['raison'] as String?,
    );
  }

  Map<String, dynamic> versJson() => {
        'id': id,
        'etablissement_id': etablissementId,
        'annee_scolaire_id': anneeScolaireId,
        'enseignant_profile_id': enseignantId,
        'classe_id': classeId,
        'salle_id': salleId,
        'jour_semaine': jour,
        'heure_debut': debut,
        'heure_fin': fin,
        'raison': raison,
        'type': enseignantId != null
            ? 'indisponibilite_enseignant'
            : salleId != null
                ? 'indisponibilite_salle'
                : 'indisponibilite_classe',
      };

  final String id;
  final String etablissementId;
  final String anneeScolaireId;
  final String? enseignantId;
  final String? classeId;
  final String? salleId;
  final int? jour;
  final String? debut;
  final String? fin;
  final String? raison;

  IndisponibiliteEmploi versMoteur() => IndisponibiliteEmploi(
        enseignantId: enseignantId,
        classeId: classeId,
        salleId: salleId,
        jour: jour,
        debut: debut,
        fin: fin,
      );
}

const nomsJours = {1: 'Lundi', 2: 'Mardi', 3: 'Mercredi', 4: 'Jeudi', 5: 'Vendredi', 6: 'Samedi', 7: 'Dimanche'};
const nomsJoursCourts = {1: 'Lun', 2: 'Mar', 3: 'Mer', 4: 'Jeu', 5: 'Ven', 6: 'Sam', 7: 'Dim'};

/// Programme d'une école pour un niveau et une série (REG-33) : copie
/// ajustable du programme national, ou matières créées par l'école quand le
/// programme national n'est pas encore publié.
class ProgrammeEcole {
  const ProgrammeEcole({
    required this.id,
    required this.niveauId,
    this.filiereId,
    required this.nom,
    this.sourceId,
    this.matieres = const [],
  });

  final String id;
  final String niveauId;
  final String? filiereId;
  final String nom;

  /// Programme national d'origine, quand l'école l'a repris.
  final String? sourceId;
  final List<ProgrammeMatiere> matieres;

  /// Somme des coefficients (affichée pour repérer un oubli).
  double get totalCoefficients => matieres.fold(0, (s, m) => s + (m.coefficient ?? 1));

  factory ProgrammeEcole.depuisJson(Map<String, dynamic> j) {
    final matieres = [
      for (final m in (j['programmes_matieres'] as List? ?? const []))
        ProgrammeMatiere.depuisJson((m as Map).cast<String, dynamic>()),
    ]..sort((a, b) => a.ordre.compareTo(b.ordre));
    return ProgrammeEcole(
      id: j['id'] as String,
      niveauId: j['niveau_id'] as String,
      filiereId: j['filiere_id'] as String?,
      nom: j['nom'] as String? ?? '',
      sourceId: j['source_id'] as String?,
      matieres: matieres,
    );
  }

  Map<String, dynamic> versJson() => {
        'id': id,
        'niveau_id': niveauId,
        'filiere_id': filiereId,
        'nom': nom,
        'source_id': sourceId,
        'programmes_matieres': [for (final m in matieres) m.versJson()],
      };
}

/// Programme de l'école pour une classe : celui de sa série, sinon celui de
/// son niveau (tronc commun).
ProgrammeEcole? programmeEcolePour(List<ProgrammeEcole> programmes, String? niveauId, String? filiereId) {
  if (niveauId == null) return null;
  ProgrammeEcole? niveauSeul;
  for (final p in programmes) {
    if (p.niveauId != niveauId) continue;
    if (p.filiereId == filiereId) return p;
    if (p.filiereId == null) niveauSeul = p;
  }
  return niveauSeul;
}
