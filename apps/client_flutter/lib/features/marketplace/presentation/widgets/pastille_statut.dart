import 'package:flutter/material.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';

import '../../domain/enums_marketplace.dart';

/// Pastille de statut de commande — code couleur cohérent avec les autres
/// modules (vert = terminé favorablement, orange = en cours, rouge = annulé).
class PastilleStatutCommande extends StatelessWidget {
  const PastilleStatutCommande({super.key, required this.statut});

  final StatutCommande statut;

  @override
  Widget build(BuildContext context) {
    final couleur = switch (statut) {
      StatutCommande.brouillon => context.palette.encreSecondaire,
      StatutCommande.confirmee => context.palette.primaire,
      StatutCommande.payee => context.palette.succes,
      StatutCommande.expediee => context.palette.accent,
      StatutCommande.livree => context.palette.succes,
      StatutCommande.annulee => context.palette.erreur,
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
      StatutPaiement.initie => context.palette.encreSecondaire,
      StatutPaiement.enAttente => context.palette.accent,
      StatutPaiement.reussi => context.palette.succes,
      StatutPaiement.echoue => context.palette.erreur,
      StatutPaiement.rembourse => context.palette.premium,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: couleur.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
      child: Text(statut.libelle, style: TextStyle(color: couleur, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
