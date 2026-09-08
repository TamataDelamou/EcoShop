/// Ligne renvoyée par la RPC `grand_livre` (M14) — un mouvement (débit ou
/// crédit) d'un compte donné.
class MouvementGrandLivre {
  const MouvementGrandLivre({
    required this.dateEcriture,
    required this.libelle,
    required this.sens,
    required this.montant,
    this.pieceJustificative,
  });

  factory MouvementGrandLivre.depuisJson(Map<String, dynamic> json) => MouvementGrandLivre(
        dateEcriture: DateTime.parse(json['date_ecriture'] as String),
        libelle: json['libelle'] as String,
        sens: json['sens'] as String,
        montant: (json['montant'] as num).toDouble(),
        pieceJustificative: json['piece_justificative'] as String?,
      );

  final DateTime dateEcriture;
  final String libelle;

  /// `'debit'` ou `'credit'`.
  final String sens;
  final double montant;
  final String? pieceJustificative;

  bool get estDebit => sens == 'debit';
}
