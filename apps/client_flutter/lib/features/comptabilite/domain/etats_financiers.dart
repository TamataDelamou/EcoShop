/// États financiers (REG-03, lots C4 et C5) — calculés par le serveur
/// (`etat_financier`, `tableau_flux_tresorerie`, `notes_annexes` ;
/// migrations `20260906001537` et `20260906001541`, tests/rls/66 et 69).
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

/// Une ligne du tableau des flux de trésorerie.
class LigneFlux {
  const LigneFlux({required this.reference, required this.libelle, required this.total, required this.montant, this.montantN1});

  factory LigneFlux.depuisJson(Map<String, dynamic> json) => LigneFlux(
        reference: json['reference'] as String,
        libelle: json['libelle'] as String,
        total: json['total'] as bool? ?? false,
        montant: _num(json['montant']) ?? 0,
        montantN1: _num(json['montant_n1']),
      );

  final String reference;
  final String libelle;
  final bool total;
  final double montant;
  final double? montantN1;
}

/// Tableau des flux de trésorerie au modèle du référentiel : SYSCOHADA
/// (méthode indirecte, ZA → ZH), SYCEBNL (méthode directe, ZA → ZG) ou
/// simplifié.
class TableauFlux {
  const TableauFlux({
    required this.plan,
    required this.methode,
    required this.provisoire,
    required this.lignes,
    required this.tresorerieBilan,
    required this.ecartCloture,
    this.operationnelDirect,
  });

  factory TableauFlux.depuisJson(Map<String, dynamic> json) => TableauFlux(
        plan: json['plan'] as String? ?? 'simplifie',
        methode: json['methode'] as String? ?? 'directe',
        provisoire: json['provisoire'] as bool? ?? true,
        lignes: [for (final l in (json['lignes'] as List<dynamic>? ?? const [])) LigneFlux.depuisJson(l as Map<String, dynamic>)],
        tresorerieBilan: _num(json['tresorerie_bilan']) ?? 0,
        ecartCloture: _num(json['ecart_cloture']) ?? 0,
        operationnelDirect: _num(json['operationnel_direct']),
      );

  final String plan;
  final String methode;
  final bool provisoire;
  final List<LigneFlux> lignes;

  /// Trésorerie nette du bilan à la clôture (contrôle).
  final double tresorerieBilan;

  /// Trésorerie du bilan − trésorerie de clôture du tableau.
  final double ecartCloture;

  /// SYSCOHADA : flux opérationnels constatés pièce par pièce, pour
  /// rapprocher la méthode indirecte de la réalité.
  final double? operationnelDirect;

  bool get concordant => ecartCloture.abs() < 0.5;

  /// Lignes de détail nulles masquées (sauf totaux et N-1 non nul).
  List<LigneFlux> get visibles => [
        for (final l in lignes)
          if (l.total || l.montant != 0 || (l.montantN1 ?? 0) != 0) l,
      ];
}

/// Une note annexe : tableau calculé ou texte (généré ou rédigé).
class NoteAnnexe {
  const NoteAnnexe({
    required this.code,
    required this.titre,
    required this.genre,
    this.texte,
    this.colonnes = const [],
    this.lignes = const [],
    this.modifiable,
  });

  factory NoteAnnexe.depuisJson(Map<String, dynamic> json) => NoteAnnexe(
        code: json['code'] as String,
        titre: json['titre'] as String,
        genre: json['genre'] as String? ?? 'texte',
        texte: json['texte'] as String?,
        colonnes: [for (final c in (json['colonnes'] as List<dynamic>? ?? const [])) '$c'],
        lignes: [
          for (final l in (json['lignes'] as List<dynamic>? ?? const [])) [for (final v in l as List<dynamic>) v],
        ],
        modifiable: json['modifiable'] as String?,
      );

  final String code;
  final String titre;

  /// « tableau » ou « texte ».
  final String genre;
  final String? texte;
  final List<String> colonnes;
  final List<List<Object?>> lignes;

  /// Clé de la note rédigée par l'école (null : note calculée).
  final String? modifiable;

  bool get estTableau => genre == 'tableau';
  bool get vide => estTableau ? lignes.isEmpty : (texte == null || texte!.trim().isEmpty);
}

class NotesAnnexes {
  const NotesAnnexes({required this.plan, required this.cloture, required this.devise, required this.notes});

  factory NotesAnnexes.depuisJson(Map<String, dynamic> json) => NotesAnnexes(
        plan: json['plan'] as String? ?? 'simplifie',
        cloture: (json['exercice'] as Map<String, dynamic>?)?['cloture'] as bool? ?? false,
        devise: json['devise'] as String? ?? 'GNF',
        notes: [for (final n in (json['notes'] as List<dynamic>? ?? const [])) NoteAnnexe.depuisJson(n as Map<String, dynamic>)],
      );

  final String plan;
  final bool cloture;
  final String devise;
  final List<NoteAnnexe> notes;
}

class ErreurEtatsFinanciers implements Exception {
  const ErreurEtatsFinanciers(this.code);

  final String code;

  String get messageUtilisateur => switch (code) {
        'PCA_DEJA_PASSES' => 'Les produits constatés d\'avance de cet exercice sont déjà passés.',
        'EXERCICE_DEJA_CLOTURE' => 'Cet exercice est clôturé.',
        'PERIODE_CLOTUREE' => 'Le 31 décembre est déjà dans une période clôturée.',
        'REFERENTIEL_OHADA_REQUIS' => 'Réservé aux comptabilités SYSCOHADA ou SYCEBNL.',
        'NOTE_INVALIDE' => 'Note trop longue (8 000 caractères au plus).',
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
  Future<TableauFlux> fluxTresorerie(String etablissementId, String exerciceId);
  Future<NotesAnnexes> notesAnnexes(String etablissementId, String exerciceId);

  /// Texte vide : la note rédigée est retirée.
  Future<void> enregistrerNote(String exerciceId, String cle, String texte);
}
