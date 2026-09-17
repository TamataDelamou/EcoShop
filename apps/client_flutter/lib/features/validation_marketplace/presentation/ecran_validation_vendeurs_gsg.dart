import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../application/validation_marketplace_providers.dart';
import '../domain/validation_marketplace_repository.dart';
import '../domain/vendeur_validation.dart';

/// Validation GSG des comptes Vendeur avant activation marketplace (cahier
/// §27.2, §30.2 — palier 1, global). Réservé à l'Administrateur GSG — la
/// véritable autorité reste la RPC serveur `valider_vendeur`.
class EcranValidationVendeursGsg extends ConsumerStatefulWidget {
  const EcranValidationVendeursGsg({super.key});

  @override
  ConsumerState<EcranValidationVendeursGsg> createState() => _EcranValidationVendeursGsgState();
}

class _EcranValidationVendeursGsgState extends ConsumerState<EcranValidationVendeursGsg> {
  final Set<String> _enCours = {};
  String? _erreur;

  Future<void> _decider(VendeurValidation vendeur, String decision) async {
    String? motif;
    if (decision == 'refuse') {
      motif = await _demanderMotif('Refuser ${vendeur.nom} ?');
      if (motif == null) return;
    }
    setState(() {
      _erreur = null;
      _enCours.add(vendeur.commercantId);
    });
    try {
      await ref.read(validationMarketplaceRepositoryProvider).validerVendeur(
            commercantId: vendeur.commercantId,
            decision: decision,
            motif: motif,
          );
      ref.invalidate(vendeursValidationProvider);
    } on ErreurValidationMarketplace {
      if (mounted) setState(() => _erreur = 'Impossible de mettre à jour ce vendeur — réessayez.');
    } finally {
      if (mounted) setState(() => _enCours.remove(vendeur.commercantId));
    }
  }

  Future<String?> _demanderMotif(String titre) async {
    final controleur = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(titre),
        content: TextField(
          controller: controleur,
          decoration: const InputDecoration(labelText: 'Motif du refus'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controleur.text.trim()),
            child: const Text('Refuser'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final vendeursAsync = ref.watch(vendeursValidationProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Validation des vendeurs')),
      body: vendeursAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (erreur, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Indisponible hors connexion pour le moment.'),
          ),
        ),
        data: (vendeurs) {
          if (vendeurs.isEmpty) {
            return const Center(child: Text('Aucun vendeur enregistré.'));
          }
          return Column(
            children: [
              if (_erreur != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_erreur!, style: TextStyle(color: palette.erreur)),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: vendeurs.length,
                  itemBuilder: (context, i) {
                    final vendeur = vendeurs[i];
                    final enCours = _enCours.contains(vendeur.commercantId);
                    return ListTile(
                      title: Text(vendeur.nom),
                      subtitle: Text(_libelleStatut(vendeur)),
                      trailing: enCours
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (vendeur.statutValidation != 'valide')
                                  TextButton(
                                    onPressed: () => _decider(vendeur, 'valide'),
                                    child: const Text('Valider'),
                                  ),
                                if (vendeur.statutValidation != 'refuse')
                                  TextButton(
                                    onPressed: () => _decider(vendeur, 'refuse'),
                                    child: const Text('Refuser'),
                                  ),
                              ],
                            ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _libelleStatut(VendeurValidation vendeur) => switch (vendeur.statutValidation) {
        'valide' => 'Validé',
        'refuse' => 'Refusé${vendeur.motifRefus != null ? " — ${vendeur.motifRefus}" : ""}',
        _ => 'En attente',
      };
}
