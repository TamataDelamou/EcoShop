import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../application/validation_marketplace_providers.dart';
import '../domain/agrement_vendeur.dart';
import '../domain/validation_marketplace_repository.dart';

/// Agrément établissement <-> vendeur (cahier §27.2 — palier 2, chaîne
/// d'agrément multi-établissements). Réservé à la Direction de
/// l'établissement concerné — ne liste que les vendeurs déjà validés par
/// GSG (palier 1), un vendeur non validé n'apparaît jamais ici.
class EcranAgrementVendeursEtablissement extends ConsumerStatefulWidget {
  const EcranAgrementVendeursEtablissement({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  ConsumerState<EcranAgrementVendeursEtablissement> createState() =>
      _EcranAgrementVendeursEtablissementState();
}

class _EcranAgrementVendeursEtablissementState extends ConsumerState<EcranAgrementVendeursEtablissement> {
  final Set<String> _enCours = {};
  String? _erreur;

  Future<void> _decider(AgrementVendeur agrement, String decision) async {
    String? motif;
    if (decision == 'refuse') {
      motif = await _demanderMotif('Refuser ${agrement.nomVendeur} pour cet établissement ?');
      if (motif == null) return;
    }
    setState(() {
      _erreur = null;
      _enCours.add(agrement.commercantId);
    });
    try {
      await ref.read(validationMarketplaceRepositoryProvider).deciderAgrement(
            commercantId: agrement.commercantId,
            etablissementId: widget.etablissementId,
            decision: decision,
            motif: motif,
          );
      ref.invalidate(agrementsEtablissementProvider(widget.etablissementId));
    } on ErreurValidationMarketplace {
      if (mounted) setState(() => _erreur = 'Impossible de mettre à jour cet agrément — réessayez.');
    } finally {
      if (mounted) setState(() => _enCours.remove(agrement.commercantId));
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
    final agrementsAsync = ref.watch(agrementsEtablissementProvider(widget.etablissementId));

    return Scaffold(
      appBar: AppBar(title: const Text('Vendeurs marketplace')),
      body: agrementsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (erreur, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Indisponible hors connexion pour le moment.'),
          ),
        ),
        data: (agrements) {
          if (agrements.isEmpty) {
            return const Center(child: Text('Aucun vendeur validé par GSG pour le moment.'));
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
                  itemCount: agrements.length,
                  itemBuilder: (context, i) {
                    final agrement = agrements[i];
                    final enCours = _enCours.contains(agrement.commercantId);
                    return ListTile(
                      title: Text(agrement.nomVendeur),
                      subtitle: Text(_libelleStatut(agrement)),
                      trailing: enCours
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (agrement.statut != 'valide')
                                  TextButton(
                                    onPressed: () => _decider(agrement, 'valide'),
                                    child: const Text('Agréer'),
                                  ),
                                if (agrement.statut != 'refuse')
                                  TextButton(
                                    onPressed: () => _decider(agrement, 'refuse'),
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

  String _libelleStatut(AgrementVendeur agrement) => switch (agrement.statut) {
        'valide' => 'Agréé pour cet établissement',
        'refuse' => 'Refusé${agrement.motifRefus != null ? " — ${agrement.motifRefus}" : ""}',
        _ => 'En attente de décision',
      };
}
