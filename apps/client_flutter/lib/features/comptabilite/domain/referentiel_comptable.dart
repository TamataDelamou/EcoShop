/// Référentiel comptable choisi par l'établissement (REG-03, lot C1).
///
/// Un seul moteur d'écritures (M14) ; seuls le plan de comptes et, plus tard,
/// les états financiers changent. La base est l'unique autorité : droits
/// (Direction), chargement du plan, protection des comptes réglementaires
/// (migration `20260906001534`, tests/rls/63).
enum ReferentielComptable {
  simplifie('simplifie'),
  syscohadaSmt('syscohada_smt'),
  syscohadaNormal('syscohada_normal'),
  sycebnl('sycebnl');

  const ReferentielComptable(this.code);

  final String code;

  String get libelle => switch (this) {
        ReferentielComptable.simplifie => 'Comptabilité simplifiée',
        ReferentielComptable.syscohadaSmt => 'SYSCOHADA — Système minimal de trésorerie',
        ReferentielComptable.syscohadaNormal => 'SYSCOHADA — Système normal',
        ReferentielComptable.sycebnl => 'SYCEBNL — Entités à but non lucratif',
      };

  String get libelleCourt => switch (this) {
        ReferentielComptable.simplifie => 'Simplifiée',
        ReferentielComptable.syscohadaSmt => 'SYSCOHADA SMT',
        ReferentielComptable.syscohadaNormal => 'SYSCOHADA normal',
        ReferentielComptable.sycebnl => 'SYCEBNL',
      };

  String get description => switch (this) {
        ReferentielComptable.simplifie =>
          'Plan de comptes libre, pour le suivi de gestion. Ne remplace pas une comptabilité réglementaire.',
        ReferentielComptable.syscohadaSmt =>
          'Petites entreprises de services : comptabilité de trésorerie (recettes et dépenses) et états simplifiés.',
        ReferentielComptable.syscohadaNormal =>
          'Entreprises au-dessus du seuil : bilan, compte de résultat, tableau des flux et notes annexes.',
        ReferentielComptable.sycebnl =>
          'Associations, écoles confessionnelles et fondations : dons, subventions et fonds affectés suivis à part.',
      };

  /// Les référentiels OHADA imposent un plan de comptes verrouillé.
  bool get estReglementaire => this != ReferentielComptable.simplifie;

  static ReferentielComptable depuisCode(String? code) =>
      ReferentielComptable.values.firstWhere((r) => r.code == code, orElse: () => ReferentielComptable.simplifie);
}

enum FormeJuridique {
  societe('societe', 'Société (SARL, SA…)'),
  entrepriseIndividuelle('entreprise_individuelle', 'Entreprise individuelle'),
  association('association', 'Association'),
  confessionnelle('confessionnelle', 'Organisation confessionnelle (Église, mosquée…)'),
  fondation('fondation', 'Fondation'),
  publique('publique', 'Établissement public'),
  autre('autre', 'Je ne sais pas / autre');

  const FormeJuridique(this.code, this.libelle);

  final String code;
  final String libelle;

  static FormeJuridique? depuisCode(String? code) {
    for (final f in FormeJuridique.values) {
      if (f.code == code) return f;
    }
    return null;
  }
}

/// Paramètres comptables enregistrés (absents = jamais choisi = simplifié).
class ParametresComptables {
  const ParametresComptables({
    required this.referentiel,
    this.formeJuridique,
    this.chiffreAffairesEstime,
    this.choisiLe,
  });

  factory ParametresComptables.depuisJson(Map<String, dynamic> json) => ParametresComptables(
        referentiel: ReferentielComptable.depuisCode(json['referentiel'] as String?),
        formeJuridique: FormeJuridique.depuisCode(json['forme_juridique'] as String?),
        chiffreAffairesEstime: (json['chiffre_affaires_estime'] as num?)?.toDouble(),
        choisiLe: json['choisi_le'] == null ? null : DateTime.parse(json['choisi_le'] as String),
      );

  static const parDefaut = ParametresComptables(referentiel: ReferentielComptable.simplifie);

  final ReferentielComptable referentiel;
  final FormeJuridique? formeJuridique;
  final double? chiffreAffairesEstime;
  final DateTime? choisiLe;

  bool get jamaisChoisi => choisiLe == null;
}

/// Réponse de l'assistant : une recommandation motivée, jamais une décision.
class RecommandationReferentiel {
  const RecommandationReferentiel({
    required this.referentiel,
    required this.raison,
    this.alternatives = const [],
    this.seuilSmt,
    this.seuilDevise,
    this.seuilAConfirmer = true,
  });

  factory RecommandationReferentiel.depuisJson(Map<String, dynamic> json) => RecommandationReferentiel(
        referentiel: ReferentielComptable.depuisCode(json['referentiel'] as String?),
        raison: json['raison'] as String? ?? '',
        alternatives: [
          for (final a in (json['alternatives'] as List<dynamic>? ?? const [])) ReferentielComptable.depuisCode(a as String),
        ],
        seuilSmt: (json['seuil_smt'] as num?)?.toDouble(),
        seuilDevise: json['seuil_devise'] as String?,
        seuilAConfirmer: json['seuil_a_confirmer'] as bool? ?? true,
      );

  final ReferentielComptable referentiel;
  final String raison;
  final List<ReferentielComptable> alternatives;
  final double? seuilSmt;
  final String? seuilDevise;
  final bool seuilAConfirmer;
}

class ResultatChoixReferentiel {
  const ResultatChoixReferentiel({required this.referentiel, required this.comptesCharges});

  final ReferentielComptable referentiel;
  final int comptesCharges;
}

class ErreurReferentielComptable implements Exception {
  const ErreurReferentielComptable(this.code);

  final String code;

  String get messageUtilisateur => switch (code) {
        'ACCES_REFUSE' => 'Seule la Direction de l\'établissement peut choisir le référentiel comptable.',
        'ECRITURES_EXISTANTES' =>
          'Des écritures existent déjà : le changement de plan de comptes se fera à l\'ouverture du prochain exercice.',
        'REFERENTIEL_INCONNU' || 'FORME_JURIDIQUE_INCONNUE' => 'Choix invalide, veuillez réessayer.',
        _ => 'Connexion impossible pour le moment. Réessayez dans un instant.',
      };

  @override
  String toString() => 'ErreurReferentielComptable($code)';
}

abstract interface class ReferentielComptableRepository {
  Future<ParametresComptables> parametres(String etablissementId);

  Future<RecommandationReferentiel> recommander({
    required FormeJuridique formeJuridique,
    double? chiffreAffaires,
    required String devise,
    required bool souhaitReglementaire,
  });

  Future<ResultatChoixReferentiel> choisir({
    required String etablissementId,
    required ReferentielComptable referentiel,
    FormeJuridique? formeJuridique,
    double? chiffreAffaires,
  });
}
