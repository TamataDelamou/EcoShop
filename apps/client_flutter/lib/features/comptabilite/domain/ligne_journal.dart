/// Ligne renvoyée par la RPC `journal_comptable` (M14) — vue chronologique
/// d'un journal, codes de comptes déjà résolus côté serveur.
class LigneJournal {
  const LigneJournal({
    required this.dateEcriture,
    required this.libelle,
    required this.compteDebit,
    required this.compteCredit,
    required this.montant,
    this.pieceJustificative,
  });

  factory LigneJournal.depuisJson(Map<String, dynamic> json) => LigneJournal(
        dateEcriture: DateTime.parse(json['date_ecriture'] as String),
        libelle: json['libelle'] as String,
        compteDebit: json['compte_debit'] as String,
        compteCredit: json['compte_credit'] as String,
        montant: (json['montant'] as num).toDouble(),
        pieceJustificative: json['piece_justificative'] as String?,
      );

  final DateTime dateEcriture;
  final String libelle;
  final String compteDebit;
  final String compteCredit;
  final double montant;
  final String? pieceJustificative;
}
