/// Changement de plan de comptes avec historique (REG-03, lot C6).
///
/// Le serveur propose la table de correspondance, archive les états publiés
/// et applique le changement au premier jour d'un exercice ; les pièces ne
/// sont jamais modifiées (migration `20260906001542`, tests/rls/70).
library;

import 'referentiel_comptable.dart';

double _num(Object? v) => (v as num?)?.toDouble() ?? 0;

/// D'où vient la proposition de compte cible.
enum OrigineCorrespondance {
  identique('identique', 'Même compte'),
  table('table', 'Correspondance connue'),
  memeNumero('meme_numero', 'Même numéro, intitulé différent'),
  rattachement('rattachement', 'Compte de rattachement'),
  nature('nature', 'Selon la nature du compte'),
  manuel('manuel', 'Choisi par l\'école'),
  aucune('', 'À choisir');

  const OrigineCorrespondance(this.code, this.libelle);

  final String code;
  final String libelle;

  static OrigineCorrespondance depuisCode(String? code) =>
      OrigineCorrespondance.values.firstWhere((o) => o.code == (code ?? ''), orElse: () => OrigineCorrespondance.aucune);
}

class LigneCorrespondance {
  const LigneCorrespondance({
    required this.ancienCompteId,
    required this.ancienCode,
    required this.ancienIntitule,
    required this.solde,
    this.codeCible,
    this.intituleCible,
    this.origine = OrigineCorrespondance.aucune,
    this.aVerifier = true,
  });

  factory LigneCorrespondance.depuisJson(Map<String, dynamic> json) => LigneCorrespondance(
        ancienCompteId: json['ancien_compte_id'] as String,
        ancienCode: json['ancien_code'] as String,
        ancienIntitule: json['ancien_intitule'] as String,
        solde: _num(json['solde']),
        codeCible: json['code_cible'] as String?,
        intituleCible: json['intitule_cible'] as String?,
        origine: OrigineCorrespondance.depuisCode(json['origine'] as String?),
        aVerifier: json['a_verifier'] as bool? ?? true,
      );

  final String ancienCompteId;
  final String ancienCode;
  final String ancienIntitule;

  /// Solde de bilan à reporter (0 pour les comptes de gestion).
  final double solde;
  final String? codeCible;
  final String? intituleCible;
  final OrigineCorrespondance origine;
  final bool aVerifier;

  bool get aCompleter => codeCible == null;
}

class ChangementPlan {
  const ChangementPlan({
    required this.id,
    required this.statut,
    required this.ancien,
    required this.nouveau,
    required this.dateEffet,
    this.exercice,
    required this.aCompleter,
    required this.aVerifier,
    this.lignes = const [],
  });

  factory ChangementPlan.depuisJson(Map<String, dynamic> json) => ChangementPlan(
        id: json['id'] as String,
        statut: json['statut'] as String? ?? 'brouillon',
        ancien: ReferentielComptable.depuisCode(json['ancien_referentiel'] as String?),
        nouveau: ReferentielComptable.depuisCode(json['nouveau_referentiel'] as String?),
        dateEffet: DateTime.parse(json['date_effet'] as String),
        exercice: json['exercice'] as String?,
        aCompleter: (json['a_completer'] as num?)?.toInt() ?? 0,
        aVerifier: (json['a_verifier'] as num?)?.toInt() ?? 0,
        lignes: [
          for (final l in (json['lignes'] as List<dynamic>? ?? const []))
            LigneCorrespondance.depuisJson(l as Map<String, dynamic>),
        ],
      );

  final String id;
  final String statut;
  final ReferentielComptable ancien;
  final ReferentielComptable nouveau;
  final DateTime dateEffet;
  final String? exercice;
  final int aCompleter;
  final int aVerifier;
  final List<LigneCorrespondance> lignes;

  bool get applicable => statut == 'brouillon' && aCompleter == 0;
}

class CompteCible {
  const CompteCible({required this.code, required this.intitule});

  factory CompteCible.depuisJson(Map<String, dynamic> json) =>
      CompteCible(code: json['code'] as String, intitule: json['intitule'] as String);

  final String code;
  final String intitule;

  String get libelle => '$code — $intitule';
}

class ResultatChangementPlan {
  const ResultatChangementPlan({required this.comptesCharges, required this.comptesRetires, required this.exercicesArchives});

  factory ResultatChangementPlan.depuisJson(Map<String, dynamic> json) => ResultatChangementPlan(
        comptesCharges: (json['comptes_charges'] as num?)?.toInt() ?? 0,
        comptesRetires: (json['comptes_retires'] as num?)?.toInt() ?? 0,
        exercicesArchives: (json['exercices_archives'] as num?)?.toInt() ?? 0,
      );

  final int comptesCharges;
  final int comptesRetires;
  final int exercicesArchives;
}

class ErreurChangementPlan implements Exception {
  const ErreurChangementPlan(this.code);

  final String code;

  String get messageUtilisateur => switch (code) {
        'ACCES_REFUSE' => 'Seule la Direction peut changer de plan de comptes.',
        'EXERCICE_VIERGE_REQUIS' =>
          'Le changement prend effet au premier jour d\'un exercice sans écriture : clôturez l\'exercice en cours '
              '(ou ouvrez le suivant), puis revenez ici.',
        'MEME_PLAN' => 'Ce référentiel utilise déjà le même plan de comptes : adoptez-le directement.',
        'CHOIX_DIRECT_POSSIBLE' => 'Le retour à la comptabilité simplifiée se fait directement, sans table de correspondance.',
        'COMPTE_CIBLE_INVALIDE' =>
          'Choisissez un compte de détail du nouveau plan, ou un sous-compte d\'un compte de détail (par ex. 5711 sous 571).',
        'CORRESPONDANCES_INCOMPLETES' => 'Certains comptes n\'ont pas encore de compte cible.',
        'ECRITURES_APRES_DATE_EFFET' =>
          'Des écritures ont été saisies depuis la préparation, à partir de la date d\'effet : préparez à nouveau.',
        'CHANGEMENT_DEJA_APPLIQUE' => 'Ce changement est déjà appliqué.',
        'REFERENTIEL_MODIFIE_ENTRE_TEMPS' => 'Le référentiel a changé entre-temps : préparez à nouveau.',
        'HORS_CONNEXION' =>
          'Pas de réseau. Les écrans déjà consultés restent lisibles sur cet appareil ; cette action (ou une page '
              'jamais ouverte ici) attend le retour du réseau.',
        _ => 'Opération impossible pour le moment. Réessayez dans un instant.',
      };

  @override
  String toString() => 'ErreurChangementPlan($code)';
}

abstract interface class ChangementPlanRepository {
  Future<ChangementPlan> proposer(String etablissementId, ReferentielComptable cible, FormeJuridique? forme);
  Future<ChangementPlan> definir(String changementId, String ancienCompteId, String? codeCible);
  Future<ResultatChangementPlan> appliquer(String changementId);
  Future<void> abandonner(String changementId);
  Future<List<CompteCible>> comptesCibles(ReferentielComptable referentiel);
}
