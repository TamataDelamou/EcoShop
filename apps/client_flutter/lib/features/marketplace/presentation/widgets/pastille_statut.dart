import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/enums_marketplace.dart';

/// Pastille de statut de commande — code couleur cohérent avec les autres
/// modules (vert = terminé favorablement, orange = en cours, rouge = annulé).
class PastilleStatutCommande extends StatelessWidget {
  const PastilleStatutCommande({super.key, required this.statut});

  final StatutCommande statut;

  @override
  Widget build(BuildContext context) {
    final couleur = switch (statut) {
      StatutCommande.brouillon => AppColors.encreSecondaire,
      StatutCommande.confirmee => AppColors.bleuElectrique,
      StatutCommande.payee => AppColors.vertMenthe,
      StatutCommande.expediee => AppColors.orangePop,
      StatutCommande.livree => AppColors.vertMenthe,
      StatutCommande.annulee => AppColors.erreur,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: couleur.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
      child: Text(statut.libelle, style: TextStyle(color: couleur, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// Pastille de statut de paiement.
class PastilleStatutPaiement extends StatelessWidget {
  const PastilleStatutPaiement({super.key, required this.statut});

  final StatutPaiement statut;

  @override
  Widget build(BuildContext context) {
    final couleur = switch (statut) {
      StatutPaiement.initie => AppColors.encreSecondaire,
      StatutPaiement.enAttente => AppColors.orangePop,
      StatutPaiement.reussi => AppColors.vertMenthe,
      StatutPaiement.echoue => AppColors.erreur,
      StatutPaiement.rembourse => AppColors.dore,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: couleur.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
      child: Text(statut.libelle, style: TextStyle(color: couleur, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
