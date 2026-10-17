/// Pièces comptables, exercices et clôtures (REG-03, lot C2).
///
/// Le serveur est l'unique autorité (migration `20260906001535`,
/// tests/rls/64) : équilibre, numérotation continue, irréversibilité,
/// contre-passation en négatif, clôtures. Le client ne fait que guider la
/// saisie.
library;

DateTime _date(Object? v) => DateTime.parse(v as String);
double _num(Object? v) => (v as num?)?.toDouble() ?? 0;

String dateIso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String dateCourte(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

class ExerciceComptable {
  const ExerciceComptable({
    required this.id,
    required this.libelle,
    required this.dateDebut,
    required this.dateFin,
    required this.cloture,
    this.clotureJusquAu,
    this.resultat,
  });

  factory ExerciceComptable.depuisJson(Map<String, dynamic> json) => ExerciceComptable(
        id: json['id'] as String,
        libelle: json['libelle'] as String,
        dateDebut: _date(json['date_debut']),
        dateFin: _date(json['date_fin']),
        cloture: json['statut'] == 'cloture',
        clotureJusquAu: json['cloture_jusqu_au'] == null ? null : _date(json['cloture_jusqu_au']),
        resultat: (json['resultat'] as num?)?.toDouble(),
      );

  final String id;
  final String libelle;
  final DateTime dateDebut;
  final DateTime dateFin;
  final bool cloture;
  final DateTime? clotureJusquAu;
  final double? resultat;

  bool contient(DateTime d) => !d.isBefore(dateDebut) && !d.isAfter(dateFin);
}

enum StatutPiece { brouillard, validee }

enum OriginePiece {
  saisie('saisie', 'Saisie'),
  automatique('automatique', 'Automatique'),
  contrepassation('contrepassation', 'Contre-passation'),
  aNouveaux('a_nouveaux', 'À-nouveaux');

  const OriginePiece(this.code, this.libelle);

  final String code;
  final String libelle;

  static OriginePiece depuisCode(String? code) =>
      OriginePiece.values.firstWhere((o) => o.code == code, orElse: () => OriginePiece.saisie);
}

class LignePiece {
  const LignePiece({
    required this.compteId,
    this.compteCode = '',
    this.compteIntitule = '',
    this.libelle,
    this.debit = 0,
    this.credit = 0,
  });

  factory LignePiece.depuisJson(Map<String, dynamic> json) => LignePiece(
        compteId: json['compte_id'] as String,
        compteCode: json['compte_code'] as String? ?? '',
        compteIntitule: json['compte_intitule'] as String? ?? '',
        libelle: json['libelle'] as String?,
        debit: _num(json['debit']),
        credit: _num(json['credit']),
      );

  final String compteId;
  final String compteCode;
  final String compteIntitule;
  final String? libelle;
  final double debit;
  final double credit;

  Map<String, dynamic> versJsonSaisie() => {
        'compte_id': compteId,
        if (debit != 0) 'debit': debit,
        if (credit != 0) 'credit': credit,
        if (libelle != null && libelle!.trim().isNotEmpty) 'libelle': libelle!.trim(),
      };
}

class PieceComptable {
  const PieceComptable({
    required this.id,
    required this.exerciceId,
    required this.journalId,
    required this.datePiece,
    required this.libelle,
    required this.statut,
    this.reference,
    this.pieceJustificative,
    this.origine = OriginePiece.saisie,
    this.annuleeParPieceId,
    this.pieceAnnuleeId,
    this.journalCode,
    this.lignes = const [],
  });

  factory PieceComptable.depuisJson(Map<String, dynamic> json) => PieceComptable(
        id: json['id'] as String,
        exerciceId: json['exercice_id'] as String,
        journalId: json['journal_id'] as String,
        datePiece: _date(json['date_piece']),
        libelle: json['libelle'] as String,
        statut: json['statut'] == 'validee' ? StatutPiece.validee : StatutPiece.brouillard,
        reference: json['reference'] as String?,
        pieceJustificative: json['piece_justificative'] as String?,
        origine: OriginePiece.depuisCode(json['origine'] as String?),
        annuleeParPieceId: json['annulee_par_piece_id'] as String?,
        pieceAnnuleeId: json['piece_annulee_id'] as String?,
        journalCode: json['journal_code'] as String?,
        lignes: [
          for (final l in (json['lignes'] as List<dynamic>? ?? const [])) LignePiece.depuisJson(l as Map<String, dynamic>),
        ],
      );

  final String id;
  final String exerciceId;
  final String journalId;
  final DateTime datePiece;
  final String libelle;
  final StatutPiece statut;
  final String? reference;
  final String? pieceJustificative;
  final OriginePiece origine;
  final String? annuleeParPieceId;
  final String? pieceAnnuleeId;
  final String? journalCode;
  final List<LignePiece> lignes;

  bool get estValidee => statut == StatutPiece.validee;
  bool get estAnnulee => annuleeParPieceId != null;
  bool get contrepassable =>
      estValidee && !estAnnulee && origine != OriginePiece.contrepassation && origine != OriginePiece.aNouveaux;

  double get totalDebit => lignes.fold(0, (s, l) => s + l.debit);
  double get totalCredit => lignes.fold(0, (s, l) => s + l.credit);
}

/// Saisie en cours (brouillard) — équilibre vérifié à l'écran ET en base.
class SaisiePiece {
  const SaisiePiece({
    this.pieceId,
    required this.etablissementId,
    required this.journalId,
    required this.datePiece,
    required this.libelle,
    this.pieceJustificative,
    required this.lignes,
  });

  final String? pieceId;
  final String etablissementId;
  final String journalId;
  final DateTime datePiece;
  final String libelle;
  final String? pieceJustificative;
  final List<LignePiece> lignes;

  double get totalDebit => lignes.fold(0, (s, l) => s + l.debit);
  double get totalCredit => lignes.fold(0, (s, l) => s + l.credit);
  bool get equilibree => lignes.length >= 2 && totalDebit > 0 && (totalDebit - totalCredit).abs() < 0.005;
}

class ResultatClotureExercice {
  const ResultatClotureExercice({required this.resultat, this.pieceANouveauxId, this.exerciceSuivantId});

  final double resultat;
  final String? pieceANouveauxId;
  final String? exerciceSuivantId;
}

class ErreurPiecesComptables implements Exception {
  const ErreurPiecesComptables(this.code);

  final String code;

  String get messageUtilisateur => switch (code) {
        'AUCUN_EXERCICE_OUVERT' => 'Aucun exercice ouvert pour cette date : ouvrez d\'abord l\'exercice.',
        'PERIODE_CLOTUREE' => 'Cette période est clôturée : plus aucune écriture n\'y est possible.',
        'PIECE_DESEQUILIBREE' => 'La pièce doit avoir au moins deux lignes et un total des débits égal au total des crédits.',
        'PIECE_VALIDEE_IMMUABLE' => 'Une pièce validée ne se modifie plus : contre-passez-la pour la corriger.',
        'COMPTE_NON_IMPUTABLE' => 'Ce compte regroupe d\'autres comptes : choisissez un compte de détail.',
        'COMPTE_INVALIDE' => 'Un des comptes n\'est pas utilisable.',
        'LIGNE_INVALIDE' => 'Chaque ligne porte un montant positif, au débit ou au crédit.',
        'LIGNES_INVALIDES' => 'Ajoutez au moins une ligne (200 au maximum).',
        'JOURNAL_INVALIDE' => 'Journal invalide.',
        'LIBELLE_REQUIS' => 'Le libellé est obligatoire.',
        'MOTIF_REQUIS' => 'Indiquez le motif de l\'annulation.',
        'PIECE_DEJA_CONTREPASSEE' => 'Cette pièce a déjà été annulée.',
        'PIECE_NON_CONTREPASSABLE' => 'Cette pièce ne peut pas être annulée.',
        'PIECE_EXERCICE_CLOTURE' =>
          'L\'exercice de cette pièce est clôturé : la correction passe par le report à nouveau (voir l\'expert-comptable).',
        'DATE_CONTREPASSATION_INVALIDE' => 'La date d\'annulation doit suivre la pièce, dans le même exercice.',
        'BROUILLARDS_EN_ATTENTE' => 'Des brouillards restent à valider ou supprimer avant la clôture.',
        'PERIODE_DEJA_CLOTUREE' => 'Cette période est déjà clôturée.',
        'EXERCICE_CHEVAUCHEMENT' => 'Cet exercice chevauche un exercice existant.',
        'EXERCICE_NON_CONTIGU' => 'Le nouvel exercice doit commencer le lendemain de la fin du précédent.',
        'EXERCICE_NON_CONFORME' =>
          'Exercice non conforme : en OHADA, douze mois du 1er janvier au 31 décembre (le premier peut commencer en cours d\'année).',
        'EXERCICE_PRECEDENT_OUVERT' => 'Clôturez d\'abord l\'exercice précédent.',
        'EXERCICE_DEJA_CLOTURE' => 'Cet exercice est déjà clôturé.',
        'COMPTE_RESULTAT_INTROUVABLE' => 'Le compte de résultat (131/139) est introuvable dans le plan.',
        'ACCES_REFUSE' => 'Seule la Direction peut clôturer un exercice.',
        'COMPTABLE_ECRITURE_REQUIS' => 'Vous n\'avez pas le droit d\'écrire en comptabilité.',
        _ => 'Opération impossible pour le moment. Réessayez dans un instant.',
      };

  @override
  String toString() => 'ErreurPiecesComptables($code)';
}

abstract interface class PiecesComptablesRepository {
  Future<List<ExerciceComptable>> exercices(String etablissementId);
  Future<String> ouvrirExercice(String etablissementId, DateTime debut, DateTime fin);
  Future<void> cloturerPeriode(String etablissementId, DateTime jusquAu);
  Future<ResultatClotureExercice> cloturerExercice(String exerciceId);

  Future<List<PieceComptable>> pieces(String etablissementId, String exerciceId);
  Future<PieceComptable> detail(String pieceId);
  Future<String> enregistrer(SaisiePiece saisie);
  Future<String> valider(String pieceId);
  Future<void> supprimerBrouillard(String pieceId);
  Future<String> contrepasser(String pieceId, String motif, DateTime date);
}

/// Montant lisible : séparateur de milliers fin, sans décimales inutiles.
String formaterMontant(double montant) {
  final negatif = montant < 0;
  final centimes = (montant.abs() * 100).round();
  final decimales = centimes % 100 != 0;
  final chiffres = (centimes ~/ 100).toString();
  final buffer = StringBuffer(negatif ? '−' : '');
  for (var i = 0; i < chiffres.length; i++) {
    if (i > 0 && (chiffres.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(chiffres[i]);
  }
  if (decimales) {
    buffer.write(',${(centimes % 100).toString().padLeft(2, '0')}');
  }
  return buffer.toString();
}
