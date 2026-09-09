import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';

import '../application/marketplace_providers.dart';
import '../domain/enums_marketplace.dart';
import '../domain/ligne_commande.dart';
import '../domain/sous_compte_marchand.dart';
import 'ecran_confirmation_commande.dart';
import 'ligne_achat.dart';
import 'widgets/montant.dart';

/// Choix du mode de paiement (M13) — port agnostique : cet écran crée la
/// commande, son snapshot de lignes et initie un [Paiement] (`statut:
/// initie`) ; l'exécution réelle (appel CinetPay/Mobile Money) est un
/// adaptateur Edge Function différé au module M14, hors périmètre ici.
class EcranChoixPaiement extends ConsumerStatefulWidget {
  const EcranChoixPaiement({
    super.key,
    required this.etablissementId,
    required this.commercantId,
    required this.profileId,
    required this.panierId,
    required this.lignes,
  });

  final String etablissementId;
  final String commercantId;
  final String profileId;
  final String panierId;
  final List<LigneAchat> lignes;

  @override
  ConsumerState<EcranChoixPaiement> createState() => _EcranChoixPaiementState();
}

class _EcranChoixPaiementState extends ConsumerState<EcranChoixPaiement> {
  SousCompteMarchand? _selection;
  bool _enCours = false;

  double get _total => widget.lignes.fold(0, (a, l) => a + l.prix * l.quantite);

  Future<void> _confirmer() async {
    final sousCompte = _selection;
    if (sousCompte == null) return;
    setState(() => _enCours = true);

    final depot = ref.read(marketplaceRepositoryProvider);
    try {
      final commande = construireCommande(
        etablissementId: widget.etablissementId,
        commercantId: widget.commercantId,
        profileId: widget.profileId,
        panierId: widget.panierId,
        montantTotal: _total,
      );
      final creee = await depot.creerCommande(commande);
      await depot.enregistrerLignesCommande(widget.lignes
          .map((l) => LigneCommande(
                id: '${creee.id}-${l.catalogueProduitId}',
                commandeId: creee.id,
                catalogueProduitId: l.catalogueProduitId,
                quantite: l.quantite,
                prixUnitaire: l.prix,
                montantLigne: l.prix * l.quantite,
              ))
          .toList());
      await depot.initierPaiement(construirePaiement(
        etablissementId: widget.etablissementId,
        commandeId: creee.id,
        sousCompteId: sousCompte.id,
        fournisseur: sousCompte.fournisseur,
        montant: _total,
      ));

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => EcranConfirmationCommande(commande: creee)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Commande impossible pour le moment — réessayez une fois connecté.')),
      );
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sousComptesAsync = ref.watch(sousComptesEtablissementProvider(widget.etablissementId));

    return Scaffold(
      appBar: AppBar(title: const Text('Paiement')),
      body: sousComptesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text("Aucun mode de paiement configuré pour cet établissement, ou établissement introuvable."),
          ),
        ),
        data: (sousComptes) {
          if (sousComptes.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text("Cet établissement n'a configuré aucun moyen de paiement pour le moment."),
              ),
            );
          }
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('Total à régler', style: Theme.of(context).textTheme.bodyMedium),
                    Text(
                      formaterMontant(_total, 'XOF'),
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: context.palette.primaire),
                    ),
                    const SizedBox(height: 20),
                    Text('Mode de paiement', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    RadioGroup<SousCompteMarchand>(
                      groupValue: _selection,
                      onChanged: _enCours ? (_) {} : (v) => setState(() => _selection = v),
                      child: Column(
                        children: [
                          for (final sc in sousComptes)
                            RadioListTile<SousCompteMarchand>(
                              value: sc,
                              title: Text(sc.libelle),
                              subtitle: Text(_libelleFournisseur(sc.fournisseur)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                minimum: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _selection == null || _enCours ? null : _confirmer,
                  child: _enCours
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Confirmer la commande'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _libelleFournisseur(TypeFournisseurPaiement f) => f.libelle;
}
