/// Liaison d'un compte à une fiche d'élève, vue par la direction (REG-18,
/// partie E) : une adresse e-mail se crée en deux minutes, la protection
/// contre les comptes multiples se place donc à la liaison. La direction
/// est prévenue de chaque compte lié à un élève de son école, peut révoquer
/// une liaison, et décide des liaisons parents au-delà du plafond.
library;

/// Compte parent (relation parent-élève) ou compte de l'élève lui-même.
enum NatureLiaison {
  parent('parent'),
  eleve('eleve');

  const NatureLiaison(this.code);
  final String code;

  static NatureLiaison depuisCode(String? code) => code == 'eleve' ? NatureLiaison.eleve : NatureLiaison.parent;
}

enum StatutLiaison {
  /// Au-delà du plafond, ou refaite après une révocation : aucun accès tant
  /// que la direction n'a pas accepté.
  enAttente('en_attente'),
  confirmee('confirmee'),
  refusee('refusee'),
  revoquee('revoquee');

  const StatutLiaison(this.code);
  final String code;

  static StatutLiaison depuisCode(String? code) {
    for (final s in StatutLiaison.values) {
      if (s.code == code) return s;
    }
    // Statut inconnu : rien d'actionnable plutôt qu'un bouton trompeur.
    return StatutLiaison.refusee;
  }

  String get libelle => switch (this) {
        StatutLiaison.enAttente => 'En attente de votre accord',
        StatutLiaison.confirmee => 'Liée',
        StatutLiaison.refusee => 'Refusée',
        StatutLiaison.revoquee => 'Révoquée',
      };
}

class LiaisonCompte {
  const LiaisonCompte({
    required this.nature,
    required this.liaisonId,
    required this.ficheEleveId,
    required this.eleve,
    required this.compteId,
    required this.compte,
    required this.statut,
    this.identifiantEcoshop,
    this.lieeLe,
  });

  /// Ligne de la RPC `liaisons_comptes`.
  factory LiaisonCompte.depuisJson(Map<String, dynamic> json) => LiaisonCompte(
        nature: NatureLiaison.depuisCode(json['nature'] as String?),
        liaisonId: json['liaison_id'] as String,
        ficheEleveId: json['fiche_eleve_id'] as String,
        eleve: (json['eleve'] as String?)?.trim() ?? '',
        compteId: json['compte_id'] as String,
        compte: (json['compte'] as String?)?.trim() ?? '',
        statut: StatutLiaison.depuisCode(json['statut'] as String?),
        identifiantEcoshop: json['identifiant_ecoshop'] as String?,
        lieeLe: DateTime.tryParse(json['liee_le'] as String? ?? '')?.toLocal(),
      );

  final NatureLiaison nature;

  /// Relation parent-élève (parent) ou fiche (élève).
  final String liaisonId;
  final String ficheEleveId;
  final String eleve;
  final String compteId;
  final String compte;
  final StatutLiaison statut;
  final String? identifiantEcoshop;
  final DateTime? lieeLe;

  /// Nom du compte, ou son identifiant EcoShop s'il n'a pas de nom.
  String get compteAffiche => compte.isNotEmpty ? compte : (identifiantEcoshop ?? 'Compte sans nom');

  bool get peutEtreDecidee => nature == NatureLiaison.parent && statut == StatutLiaison.enAttente;

  bool get peutEtreRevoquee => statut == StatutLiaison.confirmee;
}

class ErreurLiaisons implements Exception {
  const ErreurLiaisons(this.code, [this.detail]);

  final String code;
  final String? detail;

  String get message => switch (code) {
        'PERMISSION_REFUSEE' => 'Réservé à la direction de l’école.',
        'LIAISON_DEJA_TRAITEE' => 'Cette demande a déjà été traitée. Actualisez la liste.',
        'PLAFOND_INVALIDE' => 'Choisissez entre 1 et 10 comptes parents par élève.',
        'ERREUR_RESEAU' => 'Pas de connexion. Réessayez une fois en ligne.',
        _ => 'Une erreur est survenue. Réessayez.',
      };

  @override
  String toString() => 'ErreurLiaisons($code)';
}

abstract interface class LiaisonsRepository {
  /// Liaisons des [jours] derniers jours et toutes celles en attente, les
  /// plus récentes d'abord.
  Future<List<LiaisonCompte>> liaisons(String etablissementId, {int jours = 30});

  /// Accepte ou refuse une liaison parent en attente. Le parent est prévenu.
  Future<StatutLiaison> decider(String relationId, {required bool accepter});

  /// Retire l'accès. Une liaison refaite ensuite attend l'accord de l'école.
  Future<void> revoquer(LiaisonCompte liaison);

  /// Nombre de comptes parents confirmés par fiche ; au-delà, en attente.
  Future<int> plafond(String etablissementId);

  Future<int> definirPlafond(String etablissementId, int plafond);
}
