/// Réseaux d'établissements (M19, cahier v4.1 ch. 28) : demande de création
/// validée par Global Service Groupe, Direction Générale, écoles invitées,
/// tableau de bord consolidé (chiffres agrégés seulement), circulaires et
/// calendrier commun.
library;

class ErreurReseau implements Exception {
  const ErreurReseau(this.code);

  final String code;

  String get messageUtilisateur => switch (code) {
        'HORS_CONNEXION' => 'Pas de réseau : action impossible pour le moment. Réessayez une fois connecté.',
        'DEMANDE_DEJA_EN_COURS' => 'Une demande de réseau est déjà en cours d’examen pour votre compte.',
        'FRAIS_CREATION_NON_REGLES' => 'Confirmez d’abord que les frais de création ont été réglés.',
        'MOTIF_REQUIS' => 'Indiquez un motif.',
        'COMPTE_INTROUVABLE' => 'Aucun compte EcoShop avec cette adresse ou ce numéro : la personne doit d’abord s’inscrire.',
        'DERNIERE_DIRECTION_GENERALE' => 'Le réseau doit garder au moins une Direction Générale.',
        'CONFIRMATION_INCORRECTE' => 'Le nom saisi ne correspond pas au nom du réseau.',
        'INVITATION_PLUS_VALABLE' => 'Cette invitation n’est plus valable.',
        'RESEAU_DISSOUS' => 'Ce réseau a été dissous.',
        'PAS_MEMBRE' => 'Votre établissement n’est pas membre de ce réseau.',
        'ANNEE_COURANTE_ABSENTE' => 'Ouvrez d’abord l’année scolaire de votre établissement.',
        'ACCES_REFUSE' => 'Vous n’avez pas les droits pour cette action.',
        _ => 'Opération impossible ($code).',
      };

  @override
  String toString() => 'ErreurReseau($code)';
}

/// Types de réseau proposés à la création.
const typesReseau = <String, String>{
  'confessionnel': 'Confessionnel (Église, mission…)',
  'prive_laique': 'Privé laïc (groupe scolaire)',
  'communautaire': 'Communautaire / associatif',
  'public': 'Public',
  'autre': 'Autre',
};

const rolesReseau = <String, String>{
  'direction_generale': 'Direction Générale',
  'adjoint': 'Adjoint',
  'observateur': 'Observateur',
};

const typesEvenementReseau = <String, String>{
  'rentree': 'Rentrée',
  'conges': 'Congés',
  'examen': 'Examen',
  'formation': 'Formation',
  'reunion': 'Réunion',
  'fete': 'Fête',
  'autre': 'Autre',
};

class SaisieDemandeReseau {
  const SaisieDemandeReseau({
    required this.nom,
    required this.denomination,
    required this.typeReseau,
    required this.paysCode,
    required this.deviseCode,
    required this.courriel,
    required this.telephone,
    required this.adresse,
    required this.premierResponsable,
    this.message,
  });

  final String nom;
  final String denomination;
  final String typeReseau;
  final String paysCode;
  final String deviseCode;
  final String courriel;
  final String telephone;
  final String adresse;
  final String premierResponsable;
  final String? message;

  Map<String, dynamic> versParams(String id) => {
        'p_id': id,
        'p_nom': nom,
        'p_denomination': denomination,
        'p_type': typeReseau,
        'p_pays_code': paysCode,
        'p_devise_code': deviseCode,
        'p_courriel': courriel,
        'p_telephone': telephone,
        'p_adresse': adresse,
        'p_premier_responsable': premierResponsable,
        'p_message': message,
      };
}

class DemandeReseau {
  const DemandeReseau({
    required this.id,
    required this.nom,
    required this.denomination,
    required this.statut,
    required this.creeLe,
    this.typeReseau = 'autre',
    this.paysCode,
    this.courriel,
    this.telephone,
    this.adresse,
    this.premierResponsable,
    this.message,
    this.motifRefus,
    this.enAttenteEnvoi = false,
  });

  final String id;
  final String nom;
  final String denomination;
  final String statut;
  final DateTime creeLe;
  final String typeReseau;
  final String? paysCode;
  final String? courriel;
  final String? telephone;
  final String? adresse;
  final String? premierResponsable;
  final String? message;
  final String? motifRefus;

  /// Saisie sans réseau, pas encore reçue par le serveur.
  final bool enAttenteEnvoi;

  bool get enAttente => statut == 'en_attente';

  factory DemandeReseau.depuisJson(Map<String, dynamic> j) => DemandeReseau(
        id: j['id'] as String,
        nom: j['nom'] as String? ?? '',
        denomination: j['denomination'] as String? ?? '',
        statut: j['statut'] as String? ?? 'en_attente',
        creeLe: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
        typeReseau: j['type_reseau'] as String? ?? 'autre',
        paysCode: j['pays_code'] as String?,
        courriel: j['courriel'] as String?,
        telephone: j['telephone'] as String?,
        adresse: j['adresse'] as String?,
        premierResponsable: j['premier_responsable'] as String?,
        message: j['message'] as String?,
        motifRefus: j['motif_refus'] as String?,
      );
}

class EcoleDuReseau {
  const EcoleDuReseau({
    required this.etablissementId,
    required this.nom,
    required this.statut,
    this.ville,
    this.retraitMotif,
  });

  final String etablissementId;
  final String nom;
  final String? ville;

  /// `invite`, `membre`, `refuse`, `retrait_demande`, `retire`.
  final String statut;
  final String? retraitMotif;

  String get libelleStatut => switch (statut) {
        'invite' => 'Invitée',
        'membre' => 'Membre',
        'refuse' => 'A refusé',
        'retrait_demande' => 'Retrait demandé (décision GSG)',
        'retire' => 'Retirée',
        _ => statut,
      };

  factory EcoleDuReseau.depuisJson(Map<String, dynamic> j) => EcoleDuReseau(
        etablissementId: j['etablissement_id'] as String,
        nom: j['nom'] as String? ?? '',
        ville: j['ville'] as String?,
        statut: (j['statut'] ?? j['statut_reseau']) as String? ?? '',
        retraitMotif: j['retrait_motif'] as String?,
      );
}

class ResponsableReseau {
  const ResponsableReseau({required this.profileId, required this.role, required this.nom});

  final String profileId;
  final String role;
  final String nom;

  factory ResponsableReseau.depuisJson(Map<String, dynamic> j) => ResponsableReseau(
        profileId: j['profile_id'] as String,
        role: j['role'] as String? ?? 'observateur',
        nom: (j['nom'] as String?)?.trim().isNotEmpty == true ? (j['nom'] as String).trim() : 'Compte sans nom',
      );
}

class MonReseau {
  const MonReseau({
    required this.id,
    required this.nom,
    required this.denomination,
    required this.deviseCode,
    required this.ecoles,
    required this.responsables,
    this.monRole,
  });

  final String id;
  final String nom;
  final String denomination;
  final String deviseCode;

  /// `direction_generale`, `adjoint`, `observateur`, ou `null` pour la
  /// direction d'une école membre (ou invitée).
  final String? monRole;
  final List<EcoleDuReseau> ecoles;
  final List<ResponsableReseau> responsables;

  bool get estResponsable => monRole != null;
  bool get estDirectionGenerale => monRole == 'direction_generale';
  bool get peutPiloter => monRole == 'direction_generale' || monRole == 'adjoint';

  factory MonReseau.depuisJson(Map<String, dynamic> j) => MonReseau(
        id: j['reseau_id'] as String,
        nom: j['nom'] as String? ?? '',
        denomination: j['denomination'] as String? ?? '',
        deviseCode: j['devise_code'] as String? ?? 'GNF',
        monRole: j['mon_role'] as String?,
        ecoles: [for (final e in (j['ecoles'] as List?) ?? const []) EcoleDuReseau.depuisJson(e as Map<String, dynamic>)],
        responsables: [
          for (final r in (j['responsables'] as List?) ?? const []) ResponsableReseau.depuisJson(r as Map<String, dynamic>),
        ],
      );
}

double? _nombre(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
int _entier(Object? v) => v == null ? 0 : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

class IndicateursEcole {
  const IndicateursEcole({
    required this.etablissementId,
    required this.nom,
    required this.effectif,
    required this.retraits,
    required this.montantDu,
    required this.montantEncaisse,
    required this.alertesDecrochage,
    required this.personnel,
    required this.enseignants,
    required this.anneeOuverte,
    this.ville,
    this.tauxRecouvrement,
    this.tauxPresence,
    this.elevesParEnseignant,
  });

  final String etablissementId;
  final String nom;
  final String? ville;
  final bool anneeOuverte;
  final int effectif;
  final int retraits;
  final double montantDu;
  final double montantEncaisse;
  final double? tauxRecouvrement;
  final double? tauxPresence;
  final int alertesDecrochage;
  final int personnel;
  final int enseignants;
  final double? elevesParEnseignant;

  factory IndicateursEcole.depuisJson(Map<String, dynamic> j) => IndicateursEcole(
        etablissementId: j['etablissement_id'] as String,
        nom: j['nom'] as String? ?? '',
        ville: j['ville'] as String?,
        anneeOuverte: j['annee_ouverte'] as bool? ?? false,
        effectif: _entier(j['effectif']),
        retraits: _entier(j['retraits']),
        montantDu: _nombre(j['montant_du']) ?? 0,
        montantEncaisse: _nombre(j['montant_encaisse']) ?? 0,
        tauxRecouvrement: _nombre(j['taux_recouvrement']),
        tauxPresence: _nombre(j['taux_presence']),
        alertesDecrochage: _entier(j['alertes_decrochage']),
        personnel: _entier(j['personnel']),
        enseignants: _entier(j['enseignants']),
        elevesParEnseignant: _nombre(j['eleves_par_enseignant']),
      );
}

class TableauBordReseau {
  const TableauBordReseau({
    required this.nom,
    required this.deviseCode,
    required this.ecoles,
    required this.effectif,
    required this.montantDu,
    required this.montantEncaisse,
    required this.alertesDecrochage,
    required this.personnel,
    required this.enseignants,
    required this.genereLe,
    this.tauxRecouvrement,
  });

  final String nom;
  final String deviseCode;
  final List<IndicateursEcole> ecoles;
  final int effectif;
  final double montantDu;
  final double montantEncaisse;
  final double? tauxRecouvrement;
  final int alertesDecrochage;
  final int personnel;
  final int enseignants;
  final DateTime genereLe;

  /// Présence moyenne des écoles qui ont des relevés (non pondérée).
  double? get tauxPresenceMoyen {
    final t = [for (final e in ecoles) if (e.tauxPresence != null) e.tauxPresence!];
    return t.isEmpty ? null : t.reduce((a, b) => a + b) / t.length;
  }

  factory TableauBordReseau.depuisJson(Map<String, dynamic> j) {
    final reseau = (j['reseau'] as Map?)?.cast<String, dynamic>() ?? const {};
    final totaux = (j['totaux'] as Map?)?.cast<String, dynamic>() ?? const {};
    return TableauBordReseau(
      nom: reseau['nom'] as String? ?? '',
      deviseCode: reseau['devise_code'] as String? ?? 'GNF',
      ecoles: [for (final e in (j['ecoles'] as List?) ?? const []) IndicateursEcole.depuisJson(e as Map<String, dynamic>)],
      effectif: _entier(totaux['effectif']),
      montantDu: _nombre(totaux['montant_du']) ?? 0,
      montantEncaisse: _nombre(totaux['montant_encaisse']) ?? 0,
      tauxRecouvrement: _nombre(totaux['taux_recouvrement']),
      alertesDecrochage: _entier(totaux['alertes_decrochage']),
      personnel: _entier(totaux['personnel']),
      enseignants: _entier(totaux['enseignants']),
      genereLe: DateTime.tryParse(j['genere_le'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class CirculaireReseau {
  const CirculaireReseau({
    required this.id,
    required this.titre,
    required this.corps,
    required this.importante,
    required this.publieeLe,
    this.lue = false,
    this.lectures,
    this.destinataires,
    this.enAttenteEnvoi = false,
  });

  final String id;
  final String titre;
  final String corps;
  final bool importante;
  final DateTime publieeLe;
  final bool lue;

  /// Pour les responsables du réseau seulement.
  final int? lectures;
  final int? destinataires;
  final bool enAttenteEnvoi;

  factory CirculaireReseau.depuisJson(Map<String, dynamic> j) => CirculaireReseau(
        id: j['id'] as String,
        titre: j['titre'] as String? ?? '',
        corps: j['corps'] as String? ?? '',
        importante: j['importante'] as bool? ?? false,
        publieeLe: DateTime.tryParse(j['publiee_le'] as String? ?? '')?.toLocal() ?? DateTime.now(),
        lue: j['lue'] as bool? ?? false,
        lectures: j['lectures'] == null ? null : _entier(j['lectures']),
        destinataires: j['destinataires'] == null ? null : _entier(j['destinataires']),
      );
}

class EvenementReseau {
  const EvenementReseau({
    required this.id,
    required this.titre,
    required this.type,
    required this.debut,
    required this.fin,
    this.description,
    this.importe = false,
    this.enAttenteEnvoi = false,
  });

  final String id;
  final String titre;
  final String type;
  final DateTime debut;
  final DateTime fin;
  final String? description;

  /// Déjà ajouté à l'agenda de l'école de l'utilisateur.
  final bool importe;
  final bool enAttenteEnvoi;

  String get libelleType => typesEvenementReseau[type] ?? type;

  factory EvenementReseau.depuisJson(Map<String, dynamic> j) => EvenementReseau(
        id: j['id'] as String,
        titre: j['titre'] as String? ?? '',
        type: (j['type'] ?? j['type_evenement']) as String? ?? 'autre',
        debut: DateTime.parse(j['date_debut'] as String),
        fin: DateTime.parse(j['date_fin'] as String),
        description: j['description'] as String?,
        importe: j['importe'] as bool? ?? false,
      );
}

class RetraitADecider {
  const RetraitADecider({required this.etablissementId, required this.nom, this.motif, this.demandeLe});

  final String etablissementId;
  final String nom;
  final String? motif;
  final DateTime? demandeLe;

  factory RetraitADecider.depuisJson(Map<String, dynamic> j) => RetraitADecider(
        etablissementId: j['etablissement_id'] as String,
        nom: j['nom'] as String? ?? '',
        motif: j['motif'] as String?,
        demandeLe: DateTime.tryParse(j['demande_le'] as String? ?? ''),
      );
}

class ReseauVueGsg {
  const ReseauVueGsg({
    required this.id,
    required this.nom,
    required this.denomination,
    required this.statut,
    required this.membres,
    required this.invitations,
    required this.retraits,
  });

  final String id;
  final String nom;
  final String denomination;
  final String statut;
  final int membres;
  final int invitations;
  final List<RetraitADecider> retraits;

  factory ReseauVueGsg.depuisJson(Map<String, dynamic> j) => ReseauVueGsg(
        id: j['reseau_id'] as String,
        nom: j['nom'] as String? ?? '',
        denomination: j['denomination'] as String? ?? '',
        statut: j['statut'] as String? ?? 'actif',
        membres: _entier(j['membres']),
        invitations: _entier(j['invitations']),
        retraits: [
          for (final r in (j['retraits_a_decider'] as List?) ?? const []) RetraitADecider.depuisJson(r as Map<String, dynamic>),
        ],
      );
}

abstract interface class ReseauRepository {
  // Création (tout compte sauf élève), validation GSG
  Future<DemandeReseau> soumettreDemande(SaisieDemandeReseau saisie);
  Future<DemandeReseau?> maDerniereDemande();
  Future<List<DemandeReseau>> demandesATraiter();
  Future<void> traiterDemande({required String demandeId, required bool accepter, String? motif, bool fraisRegles});
  Future<List<ReseauVueGsg>> vueEnsemble();
  Future<void> deciderRetrait({required String reseauId, required String etablissementId, required bool accorder});

  // Réseaux du compte
  Future<List<MonReseau>> mesReseaux();
  Future<TableauBordReseau> tableauBord(String reseauId);

  // Pilotage (Direction Générale, adjoint)
  Future<List<EcoleDuReseau>> rechercherEtablissements(String reseauId, String texte);
  Future<void> inviter(String reseauId, String etablissementId);
  Future<void> nommerResponsable(String reseauId, String identifiant, String role);
  Future<void> retirerResponsable(String reseauId, String profileId);
  Future<void> dissoudre(String reseauId, String confirmationNom);
  Future<bool> publierCirculaire({required String reseauId, required String titre, required String corps, required bool importante});
  Future<bool> enregistrerEvenement({
    required String reseauId,
    required String titre,
    required String type,
    required DateTime debut,
    required DateTime fin,
    String? description,
    String? id,
  });
  Future<void> supprimerEvenement(String evenementId);

  // Écoles du réseau
  Future<List<CirculaireReseau>> circulaires(String reseauId);
  Future<List<EvenementReseau>> evenements(String reseauId, {String? etablissementId});
  Future<bool> repondreInvitation({required String reseauId, required String etablissementId, required bool accepter});
  Future<void> marquerLue(String circulaireId);
  Future<void> importerEvenement(String evenementId, String etablissementId);
  Future<void> demanderRetrait({required String reseauId, required String etablissementId, required String motif});
}
