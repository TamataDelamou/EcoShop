/// États financiers (REG-03, lot C4) — calculés par le serveur
/// (`etat_financier`, migration `20260906001537`, tests/rls/66).
library;

enum PartieEtat {
  actif('actif', 'Bilan — actif'),
  passif('passif', 'Bilan — passif'),
  resultat('resultat', 'Compte de résultat');

  const PartieEtat(this.code, this.titre);

  final String code;
  final String titre;

  static PartieEtat depuisCode(String? c) =>
      PartieEtat.values.firstWhere((p) => p.code == c, orElse: () => PartieEtat.resultat);
}

double? _num(Object? v) => (v as num?)?.toDouble();

class LigneEtat {
  const LigneEtat({
    required this.partie,
    required this.reference,
    required this.libelle,
    required this.total,
    required this.montant,
    this.montantN1,
    this.brut,
    this.amortissements,
  });

  factory LigneEtat.depuisJson(Map<String, dynamic> json) => LigneEtat(
        partie: PartieEtat.depuisCode(json['etat'] as String?),
        reference: json['reference'] as String,
        libelle: json['libelle'] as String,
        total: json['total'] as bool? ?? false,
        montant: _num(json['montant']) ?? 0,
        montantN1: _num(json['montant_n1']),
        brut: _num(json['brut']),
        amortissements: _num(json['amortissements']),
      );

  final PartieEtat partie;
  final String reference;
  final String libelle;
  final bool total;
  final double montant;
  final double? montantN1;
  final double? brut;
  final double? amortissements;

  /// Une ligne de détail vide (et sans N-1) n'est pas affichée.
  bool get visible => total || montant != 0 || (montantN1 ?? 0) != 0;
}

class TresorerieEtat {
  const TresorerieEtat({this.soldeDebut = 0, this.encaissements = 0, this.decaissements = 0, this.soldeFin = 0});

  factory TresorerieEtat.depuisJson(Map<String, dynamic>? json) => json == null
      ? const TresorerieEtat()
      : TresorerieEtat(
          soldeDebut: _num(json['solde_debut']) ?? 0,
          encaissements: _num(json['encaissements']) ?? 0,
          decaissements: _num(json['decaissements']) ?? 0,
          soldeFin: _num(json['solde_fin']) ?? 0,
        );

  final double soldeDebut;
  final double encaissements;
  final double decaissements;
  final double soldeFin;
}

class EtatFinancier {
  const EtatFinancier({
    required this.referentiel,
    required this.plan,
    required this.provisoire,
    required this.exerciceLibelle,
    required this.dateDebut,
    required this.dateFin,
    required this.cloture,
    required this.situationAu,
    required this.lignes,
    required this.equilibre,
    this.exercicePrecedent,
    this.resultat,
    this.nonClasses = const [],
    this.tresorerie = const TresorerieEtat(),
  });

  factory EtatFinancier.depuisJson(Map<String, dynamic> json) {
    final x = json['exercice'] as Map<String, dynamic>;
    return EtatFinancier(
      referentiel: json['referentiel'] as String? ?? 'simplifie',
      plan: json['plan'] as String? ?? 'simplifie',
      provisoire: json['provisoire'] as bool? ?? true,
      exerciceLibelle: x['libelle'] as String,
      dateDebut: DateTime.parse(x['date_debut'] as String),
      dateFin: DateTime.parse(x['date_fin'] as String),
      cloture: x['cloture'] as bool? ?? false,
      situationAu: DateTime.parse(x['situation_au'] as String),
      exercicePrecedent: json['exercice_precedent'] as String?,
      lignes: [for (final l in (json['lignes'] as List<dynamic>? ?? const [])) LigneEtat.depuisJson(l as Map<String, dynamic>)],
      equilibre: json['equilibre'] as bool? ?? false,
      resultat: _num(json['resultat']),
      nonClasses: [
        for (final n in (json['non_classes'] as List<dynamic>? ?? const []))
          '${(n as Map<String, dynamic>)['code']}',
      ],
      tresorerie: TresorerieEtat.depuisJson(json['tresorerie'] as Map<String, dynamic>?),
    );
  }

  final String referentiel;
  final String plan;
  final bool provisoire;
  final String exerciceLibelle;
  final DateTime dateDebut;
  final DateTime dateFin;
  final bool cloture;
  final DateTime situationAu;
  final String? exercicePrecedent;
  final List<LigneEtat> lignes;
  final bool equilibre;
  final double? resultat;
  final List<String> nonClasses;
  final TresorerieEtat tresorerie;

  List<LigneEtat> partie(PartieEtat p) => [for (final l in lignes) if (l.partie == p && l.visible) l];

  String get titreReferentiel => switch (referentiel) {
        'syscohada_smt' => 'SYSCOHADA révisé — Système minimal de trésorerie',
        'syscohada_normal' => 'SYSCOHADA révisé — Système normal',
        'sycebnl' => 'SYCEBNL — entités à but non lucratif',
        _ => 'Comptabilité simplifiée',
      };

  /// Libellé du résultat selon la nature de l'entité.
  String get libelleResultat {
    final r = resultat ?? 0;
    if (plan == 'sycebnl') return r >= 0 ? 'Excédent' : 'Déficit';
    return r >= 0 ? 'Bénéfice' : 'Perte';
  }
}

class LignePca {
  const LignePca({required this.code, required this.intitule, required this.encaisse, required this.montant});

  factory LignePca.depuisJson(Map<String, dynamic> json) => LignePca(
        code: json['code'] as String,
        intitule: json['intitule'] as String,
        encaisse: _num(json['encaisse']) ?? 0,
        montant: _num(json['montant']) ?? 0,
      );

  final String code;
  final String intitule;
  final double encaisse;
  final double montant;
}

class ApercuPca {
  const ApercuPca({required this.dejaPasses, required this.total, this.lignes = const []});

  factory ApercuPca.depuisJson(Map<String, dynamic> json) => ApercuPca(
        dejaPasses: json['deja_passes'] as bool? ?? false,
        total: _num(json['total']) ?? 0,
        lignes: [for (final l in (json['lignes'] as List<dynamic>? ?? const [])) LignePca.depuisJson(l as Map<String, dynamic>)],
      );

  final bool dejaPasses;
  final double total;
  final List<LignePca> lignes;
}

class ErreurEtatsFinanciers implements Exception {
  const ErreurEtatsFinanciers(this.code);

  final String code;

  String get messageUtilisateur => switch (code) {
        'PCA_DEJA_PASSES' => 'Les produits constatés d\'avance de cet exercice sont déjà passés.',
        'EXERCICE_DEJA_CLOTURE' => 'Cet exercice est clôturé.',
        'PERIODE_CLOTUREE' => 'Le 31 décembre est déjà dans une période clôturée.',
        'REFERENTIEL_OHADA_REQUIS' => 'Réservé aux comptabilités SYSCOHADA ou SYCEBNL.',
        'COMPTABLE_REQUIS' || 'COMPTABLE_ECRITURE_REQUIS' => 'Vous n\'avez pas les droits de comptabilité.',
        _ => 'Opération impossible pour le moment. Réessayez dans un instant.',
      };

  @override
  String toString() => 'ErreurEtatsFinanciers($code)';
}

abstract interface class EtatsFinanciersRepository {
  Future<EtatFinancier> etat(String etablissementId, String exerciceId);
  Future<ApercuPca> apercuPca(String exerciceId);
  Future<double> passerPca(String exerciceId);
}
