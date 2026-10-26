/// Code du compte et appareils (REG-22, partie A).
///
/// Le code à 6 chiffres est celui du COMPTE : le serveur le vérifie sur tout
/// nouvel appareil (toute nouvelle connexion). Cet état, lu par
/// `etat_appareil`, dit à l'application quelle étape montrer.
library;

enum StatutAppareil {
  /// Appareil connu : tout est permis.
  approuve,

  /// Nouvelle connexion d'un compte doté d'un code : code demandé.
  aVerifier,

  /// Pas encore décrit au serveur (juste après la connexion).
  nonEnregistre;

  static StatutAppareil depuis(String? code) => switch (code) {
    'approuvee' => approuve,
    'a_verifier' => aVerifier,
    _ => nonEnregistre,
  };
}

enum TypeDemandeAppareil {
  approbation,
  recuperation,
  ecole;

  static TypeDemandeAppareil depuis(String? code) => switch (code) {
    'recuperation' => recuperation,
    'ecole' => ecole,
    _ => approbation,
  };
}

/// Demande en cours : autorisation par un appareil connu, récupération par
/// e-mail (48 h), déblocage à l'école.
class DemandeAppareil {
  const DemandeAppareil({
    required this.id,
    required this.type,
    required this.echeance,
    this.statut,
    this.modele,
    this.demandeLe,
  });

  final String id;
  final TypeDemandeAppareil type;

  /// Autorisation : limite (10 min). Récupération : date d'effet (48 h).
  final DateTime echeance;
  final String? statut;
  final String? modele;
  final DateTime? demandeLe;

  bool get estApprouvee => statut == 'approuvee';

  factory DemandeAppareil.depuisJson(Map<String, dynamic> j) => DemandeAppareil(
    id: j['id'] as String,
    type: TypeDemandeAppareil.depuis(j['type'] as String?),
    echeance: DateTime.parse(j['echeance'] as String).toLocal(),
    statut: j['statut'] as String?,
    modele: j['modele'] as String?,
    demandeLe: j['demande_le'] == null ? null : DateTime.parse(j['demande_le'] as String).toLocal(),
  );

  Map<String, dynamic> versJson() => {
    'id': id,
    'type': type.name,
    'echeance': echeance.toUtc().toIso8601String(),
    'statut': statut,
    'modele': modele,
    'demande_le': demandeLe?.toUtc().toIso8601String(),
  };
}

class EtatAppareil {
  const EtatAppareil({
    required this.obligatoire,
    required this.aUnCode,
    required this.statut,
    this.versionCode,
    this.prenom,
    this.bloqueJusquA,
    this.motifBlocage,
    this.essaisRestants = 5,
    this.mesDemandes = const [],
    this.aTraiter = const [],
  });

  /// Rien à vérifier : serveur sans la fonction (application plus récente que
  /// le serveur), mode diagnostic, ou lecture impossible. Le serveur reste
  /// seul juge : s'il refuse, l'erreur APPAREIL_A_VERIFIER ramène ici.
  static const libre = EtatAppareil(obligatoire: false, aUnCode: false, statut: StatutAppareil.approuve);

  /// Interrupteur du serveur (`code_compte_obligatoire`).
  final bool obligatoire;
  final bool aUnCode;
  final StatutAppareil statut;
  final int? versionCode;
  final String? prenom;
  final DateTime? bloqueJusquA;

  /// `echecs` (5 codes faux) ou `pas_moi` (connexion signalée).
  final String? motifBlocage;
  final int essaisRestants;

  /// Demandes faites par cet appareil.
  final List<DemandeAppareil> mesDemandes;

  /// Demandes d'autres appareils, à traiter ici (appareil connu seulement).
  final List<DemandeAppareil> aTraiter;

  /// Code du compte à saisir avant tout le reste.
  bool get aVerifier => obligatoire && aUnCode && statut != StatutAppareil.approuve;

  bool get bloque => bloqueJusquA != null;
  bool get bloquePasMoi => bloque && motifBlocage == 'pas_moi';

  DemandeAppareil? get maRecuperation {
    for (final d in mesDemandes) {
      if (d.type == TypeDemandeAppareil.recuperation) return d;
    }
    return null;
  }

  DemandeAppareil? get monApprobation {
    for (final d in mesDemandes) {
      if (d.type == TypeDemandeAppareil.approbation) return d;
    }
    return null;
  }

  List<DemandeAppareil> get autorisationsATraiter =>
      [for (final d in aTraiter) if (d.type == TypeDemandeAppareil.approbation) d];

  DemandeAppareil? get recuperationEnCours {
    for (final d in aTraiter) {
      if (d.type == TypeDemandeAppareil.recuperation) return d;
    }
    return null;
  }

  factory EtatAppareil.depuisJson(Map<String, dynamic> j) {
    List<DemandeAppareil> liste(Object? v) => [
      for (final e in (v as List? ?? const [])) DemandeAppareil.depuisJson((e as Map).cast<String, dynamic>()),
    ];
    final bloque = j['bloque_jusqu_a'] as String?;
    return EtatAppareil(
      obligatoire: j['obligatoire'] == true,
      aUnCode: j['a_un_code'] == true,
      statut: StatutAppareil.depuis(j['statut'] as String?),
      versionCode: (j['version_code'] as num?)?.toInt(),
      prenom: j['prenom'] as String?,
      // « infinity » (Ce n'est pas moi) : pas de date de fin.
      bloqueJusquA: bloque == null ? null : (DateTime.tryParse(bloque)?.toLocal() ?? DateTime(9999)),
      motifBlocage: j['motif_blocage'] as String?,
      essaisRestants: (j['essais_restants'] as num?)?.toInt() ?? 5,
      mesDemandes: liste(j['mes_demandes']),
      aTraiter: liste(j['a_traiter']),
    );
  }

  Map<String, dynamic> versJson() => {
    'obligatoire': obligatoire,
    'a_un_code': aUnCode,
    'statut': switch (statut) {
      StatutAppareil.approuve => 'approuvee',
      StatutAppareil.aVerifier => 'a_verifier',
      StatutAppareil.nonEnregistre => 'non_enregistre',
    },
    'version_code': versionCode,
    'prenom': prenom,
    'bloque_jusqu_a': bloqueJusquA?.year == 9999 ? 'infinity' : bloqueJusquA?.toUtc().toIso8601String(),
    'motif_blocage': motifBlocage,
    'essais_restants': essaisRestants,
    'mes_demandes': [for (final d in mesDemandes) d.versJson()],
    'a_traiter': [for (final d in aTraiter) d.versJson()],
  };
}

/// Résultat de la saisie du code du compte sur un nouvel appareil.
sealed class ResultatCodeCompte {
  const ResultatCodeCompte();
}

class CodeCompteBon extends ResultatCodeCompte {
  const CodeCompteBon(this.version);
  final int version;
}

class CodeCompteFaux extends ResultatCodeCompte {
  const CodeCompteFaux(this.essaisRestants);
  final int essaisRestants;
}

class CodeCompteBloque extends ResultatCodeCompte {
  const CodeCompteBloque(this.jusquA, {this.pasMoi = false});
  final DateTime? jusquA;
  final bool pasMoi;
}

/// Personne que la direction (ou l'administrateur GSG) peut débloquer.
class PersonneDebloquable {
  const PersonneDebloquable({
    required this.profileId,
    required this.nomComplet,
    required this.qualite,
    required this.aUnCode,
    required this.bloque,
    this.courriel,
  });

  final String profileId;
  final String nomComplet;
  final String qualite;
  final bool aUnCode;
  final bool bloque;
  final String? courriel;

  factory PersonneDebloquable.depuisJson(Map<String, dynamic> j) => PersonneDebloquable(
    profileId: j['profile_id'] as String,
    nomComplet: (j['nom_complet'] as String?)?.trim().isNotEmpty == true ? j['nom_complet'] as String : 'Sans nom',
    qualite: (j['qualite'] ?? j['roles'] ?? '') as String,
    aUnCode: j['a_un_code'] == true,
    bloque: j['bloque'] == true,
    courriel: j['courriel'] as String?,
  );
}

/// Erreur du serveur, traduite en message simple.
class ErreurCodeCompte implements Exception {
  const ErreurCodeCompte(this.code, this.message);

  final String code;
  final String message;

  static String messagePour(String code) => switch (code) {
    'CODE_EVIDENT' => 'Ce code est trop facile à deviner. Choisissez des chiffres sans suite évidente.',
    'CODE_FORMAT' => 'Le code compte 6 chiffres.',
    'CODE_FAUX' => 'Code incorrect.',
    'CODE_BLOQUE' => 'Les nouveaux appareils sont bloqués pour le moment.',
    'CODE_DEJA_DEFINI' => 'Votre compte a déjà un code.',
    'AUCUN_APPAREIL_CONNU' => 'Aucun autre appareil n’est connecté à votre compte. Choisissez une autre solution.',
    'RECUPERATION_EN_COURS' => 'Une récupération est déjà en cours depuis un autre appareil.',
    'RECUPERATION_TROP_TOT' => 'Par sécurité, le nouveau code ne peut être choisi qu’après 48 heures.',
    'AUCUNE_RECUPERATION' => 'Aucun déblocage en cours. Présentez-vous à la direction, ou lancez une récupération.',
    'DEMANDE_EXPIREE' => 'Cette demande a expiré. Recommencez depuis le nouvel appareil.',
    'DEMANDE_INCONNUE' => 'Cette demande n’existe plus.',
    'CHOIX_EXPIRE' => 'Le délai pour choisir un nouveau code est passé. Recommencez.',
    'DEBLOCAGE_SOI_MEME' => 'Vous ne pouvez pas vous débloquer vous-même.',
    'DEBLOCAGE_DIRECTION_PAR_GSG' =>
      'Un membre de la direction est débloqué par l’équipe GSG, après vérification de son identité.',
    'MOTIF_OBLIGATOIRE' => 'Indiquez le motif (au moins 5 caractères).',
    'PERMISSION_REFUSEE' => 'Vous n’avez pas le droit de faire cela.',
    'APPAREIL_A_VERIFIER' => 'Saisissez d’abord le code de votre compte sur cet appareil.',
    'CET_APPAREIL' => 'Pour cet appareil, utilisez « Se déconnecter ».',
    'APPAREIL_INCONNU' => 'Cet appareil est déjà déconnecté.',
    'SESSION_INCONNUE' || 'SESSION_REVOQUEE' => 'Cet appareil a été déconnecté. Reconnectez-vous.',
    _ => 'Le serveur n’a pas pu traiter la demande. Réessayez.',
  };

  @override
  String toString() => message;
}

/// Connexion ouverte du compte (Mon profil › Sécurité › Mes appareils).
class AppareilConnecte {
  const AppareilConnecte({
    required this.sessionId,
    required this.modele,
    required this.connecteLe,
    required this.derniereUtilisation,
    required this.cetAppareil,
    this.systeme,
    this.statut,
  });

  final String sessionId;
  final String modele;
  final String? systeme;
  final String? statut;
  final DateTime connecteLe;
  final DateTime derniereUtilisation;
  final bool cetAppareil;

  bool get aVerifier => statut == 'a_verifier';

  factory AppareilConnecte.depuisJson(Map<String, dynamic> j) => AppareilConnecte(
    sessionId: j['session_id'] as String,
    modele: (j['modele'] as String?) ?? 'Appareil inconnu',
    systeme: j['systeme'] as String?,
    statut: j['statut'] as String?,
    connecteLe: DateTime.parse(j['connecte_le'] as String).toLocal(),
    derniereUtilisation: DateTime.parse(j['derniere_utilisation'] as String).toLocal(),
    cetAppareil: j['cet_appareil'] == true,
  );
}
