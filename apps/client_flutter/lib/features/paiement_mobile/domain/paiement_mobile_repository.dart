import 'transaction_mobile_money.dart';

/// Résultat de l'initiation : la page Orange Money où envoyer le payeur.
class InitiationPaiementMobile {
  const InitiationPaiementMobile({
    required this.transactionId,
    required this.urlPaiement,
    required this.montant,
    required this.devise,
  });

  final String transactionId;
  final Uri urlPaiement;
  final double montant;
  final String devise;
}

/// État d'activation d'Orange Money pour un établissement — seule la partie
/// PUBLIQUE du sous-compte est lisible ; les identifiants marchands ne
/// quittent jamais le serveur.
class EtatOrangeMoney {
  const EtatOrangeMoney({required this.active, this.referencePublique});

  const EtatOrangeMoney.inactif()
      : active = false,
        referencePublique = null;

  final bool active;

  /// Ex. `OM-0058` (4 derniers caractères de la clé marchand, jamais la clé).
  final String? referencePublique;
}

/// Port des paiements mobile money du circuit établissement (REG-02).
///
/// Toujours réseau direct, jamais de file hors-ligne : un paiement ne se
/// rejoue pas en différé, et son statut n'a de sens que lu en direct.
abstract interface class PaiementMobileRepository {
  /// Crée la transaction côté serveur puis chez Orange Money (Edge Function
  /// `initier_paiement_orange_money`). Le montant est recalculé ou borné par
  /// le serveur ; [montant] n'est qu'une demande (scolarité, paiement partiel).
  Future<InitiationPaiementMobile> initierPaiementOrange({
    required ObjetPaiementMobile objet,
    required String cibleId,
    double? montant,
  });

  /// Relit une transaction (statut tenu à jour par le serveur).
  Future<TransactionMobileMoney> lireTransaction(String transactionId);

  /// Transactions récentes d'un établissement (personnel uniquement, RLS).
  Future<List<TransactionMobileMoney>> transactionsEtablissement(String etablissementId, {int limite = 50});

  /// Activation par la Direction : identifiants du compte marchand Orange
  /// Money PROPRE à l'établissement. Écrits côté serveur, jamais relus.
  Future<void> activerOrangeMoney({
    required String etablissementId,
    required String clientId,
    required String clientSecret,
    required String merchantKey,
    required bool production,
  });

  Future<EtatOrangeMoney> etatOrangeMoney(String etablissementId);
}

/// Erreur métier stable, traduite en message compréhensible pour l'écran.
class ErreurPaiementMobile implements Exception {
  const ErreurPaiementMobile(this.code, [this.detail]);

  final String code;
  final String? detail;

  String get messageUtilisateur => switch (code) {
        'ORANGE_MONEY_NON_ACTIVE' => "Cet établissement n'a pas encore activé le paiement Orange Money.",
        'PAIEMENT_DEJA_EN_COURS' =>
          'Un paiement est déjà en cours pour ce dossier. Terminez-le sur Orange Money ou patientez quelques minutes.',
        'MONTANT_SUPERIEUR_AU_SOLDE' => 'Le montant dépasse le reste à payer.',
        'MONTANT_GNF_ENTIER_REQUIS' => 'Le montant doit être un nombre entier de francs guinéens.',
        'RIEN_A_PAYER' => "Il n'y a rien à payer pour le moment.",
        'ACCES_REFUSE' => "Vous n'êtes pas autorisé à effectuer ce paiement.",
        'COMMANDE_NON_PAYABLE' => 'Cette commande ne peut plus être payée.',
        'COMMANDE_INTROUVABLE' || 'INSCRIPTION_INTROUVABLE' => 'Dossier introuvable. Actualisez puis réessayez.',
        'ORANGE_INDISPONIBLE' => 'Orange Money ne répond pas pour le moment. Réessayez dans quelques instants.',
        'IDENTIFIANTS_INCOMPLETS' => 'Renseignez les trois identifiants fournis par Orange Money.',
        'URL_PAIEMENT_INDISPONIBLE' => "La page Orange Money n'a pas pu s'ouvrir sur cet appareil.",
        _ => 'Opération impossible pour le moment. Vérifiez votre connexion et réessayez.',
      };

  @override
  String toString() => 'ErreurPaiementMobile($code)';
}
