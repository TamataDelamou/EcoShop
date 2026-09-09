/// Résultat de la RPC `solde_scolarite` (M15quater) — calcul **toujours**
/// côté serveur (tarif applicable moins encaissements validés), jamais
/// recalculé côté client (ch. 34 : le serveur fait foi).
class SoldeScolarite {
  const SoldeScolarite({
    required this.montantDu,
    required this.montantPaye,
    required this.solde,
  });

  factory SoldeScolarite.depuisJson(Map<String, dynamic> json) {
    return SoldeScolarite(
      montantDu: (json['montant_du'] as num).toDouble(),
      montantPaye: (json['montant_paye'] as num).toDouble(),
      solde: (json['solde'] as num).toDouble(),
    );
  }

  final double montantDu;
  final double montantPaye;
  final double solde;

  bool get estSolde => solde <= 0;
}
