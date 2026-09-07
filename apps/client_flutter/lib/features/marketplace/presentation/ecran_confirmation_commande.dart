import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/commande.dart';
import 'ecran_mes_commandes.dart';
import 'widgets/montant.dart';

/// Écran de confirmation affiché juste après la création d'une [Commande].
class EcranConfirmationCommande extends StatelessWidget {
  const EcranConfirmationCommande({super.key, required this.commande});

  final Commande commande;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline, size: 72, color: AppColors.vertMenthe),
                const SizedBox(height: 20),
                Text('Commande envoyée', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text('Référence ${commande.reference}', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 4),
                Text(
                  formaterMontant(commande.montantTotal, commande.devise),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: AppColors.bleuElectrique),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => EcranMesCommandes(profileId: commande.profileId)),
                    (route) => route.isFirst,
                  ),
                  child: const Text('Voir mes commandes'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
