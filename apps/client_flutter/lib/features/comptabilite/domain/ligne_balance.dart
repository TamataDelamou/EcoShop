/// Ligne renvoyée par la RPC `balance_comptable` (M14) — soldes débit/crédit
/// d'un compte à une date donnée (calcul à la volée, non persisté).
class LigneBalance {
  const LigneBalance({
    required this.compteId,
    required this.code,
    required this.intitule,
    required this.totalDebit,
    required this.totalCredit,
    required this.soldeDebit,
    required this.soldeCredit,
  });

  factory LigneBalance.depuisJson(Map<String, dynamic> json) => LigneBalance(
        compteId: json['compte_id'] as String,
        code: json['code'] as String,
        intitule: json['intitule'] as String,
        totalDebit: (json['total_debit'] as num).toDouble(),
        totalCredit: (json['total_credit'] as num).toDouble(),
        soldeDebit: (json['solde_debit'] as num).toDouble(),
        soldeCredit: (json['solde_credit'] as num).toDouble(),
      );

  final String compteId;
  final String code;
  final String intitule;
  final double totalDebit;
  final double totalCredit;
  final double soldeDebit;
  final double soldeCredit;
}

/// Projection cliente de `public.balances` (M14) — snapshot persisté par
/// `generer_balance`, pas de `deleted_at` (recalculée, jamais soft-supprimée).
class Balance {
  const Balance({
    required this.id,
    required this.etablissementId,
    required this.compteId,
    required this.dateBalance,
    required this.soldeDebit,
    required this.soldeCredit,
  });

  factory Balance.depuisJson(Map<String, dynamic> json) => Balance(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        compteId: json['compte_id'] as String,
        dateBalance: DateTime.parse(json['date_balance'] as String),
        soldeDebit: (json['solde_debit'] as num).toDouble(),
        soldeCredit: (json['solde_credit'] as num).toDouble(),
      );

  final String id;
  final String etablissementId;
  final String compteId;
  final DateTime dateBalance;
  final double soldeDebit;
  final double soldeCredit;
}
