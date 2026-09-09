import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/scolarite_providers.dart';
import '../domain/frais_scolarite_config.dart';
import '../domain/palier_paiement_config.dart';
import '../domain/scolarite_repository.dart';

/// Paramètres financiers de l'établissement (M15quater) — écart signalé par
/// l'audit (`docs/AUDIT_ECOSHOP_FLUTTER.md`, M4/M5 point 7) : tarif par
/// défaut de l'établissement et paliers de paiement.
///
/// Limite assumée pour cette première version : seul le **tarif par défaut**
/// de l'établissement (`niveau_id` null) est géré ici — le schéma serveur
/// (`frais_scolarite_config`) autorise déjà un tarif par niveau spécifique,
/// mais le sélecteur de niveau (référentiel M4) n'est pas encore branché sur
/// cet écran ; voir `docs/contrats/M15quater_inscription_encaissement.md` §6.
class EcranParametresFinanciers extends ConsumerStatefulWidget {
  const EcranParametresFinanciers({super.key, required this.etablissementId, required this.anneeScolaireId});

  final String etablissementId;
  final String anneeScolaireId;

  @override
  ConsumerState<EcranParametresFinanciers> createState() => _EcranParametresFinanciersState();
}

class _EcranParametresFinanciersState extends ConsumerState<EcranParametresFinanciers> {
  final _montantAnnuelCtrl = TextEditingController();
  final _fraisInscriptionCtrl = TextEditingController();
  bool _enCoursTarif = false;
  String? _erreurTarif;

  ({String etablissementId, String anneeScolaireId}) get _params =>
      (etablissementId: widget.etablissementId, anneeScolaireId: widget.anneeScolaireId);

  @override
  void dispose() {
    _montantAnnuelCtrl.dispose();
    _fraisInscriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _enregistrerTarif({FraisScolariteConfig? existant}) async {
    final montant = double.tryParse(_montantAnnuelCtrl.text.replaceAll(',', '.'));
    if (montant == null || montant < 0) {
      setState(() => _erreurTarif = 'Saisissez un montant annuel valide.');
      return;
    }
    final fraisInscription = double.tryParse(_fraisInscriptionCtrl.text.replaceAll(',', '.')) ?? 0;

    setState(() {
      _enCoursTarif = true;
      _erreurTarif = null;
    });

    try {
      final config = FraisScolariteConfig(
        id: existant?.id ?? '',
        etablissementId: widget.etablissementId,
        anneeScolaireId: widget.anneeScolaireId,
        montantAnnuel: montant,
        fraisInscription: fraisInscription,
      );
      await ref.read(scolariteRepositoryProvider).enregistrerFraisScolariteConfig(config);
      if (!mounted) return;
      ref.invalidate(fraisScolariteConfigProvider(_params));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tarif enregistré.')));
    } on ErreurScolarite {
      setState(() => _erreurTarif = 'Enregistrement impossible pour le moment.');
    } finally {
      if (mounted) setState(() => _enCoursTarif = false);
    }
  }

  Future<void> _ajouterPalier(List<PalierPaiementConfig> existants) async {
    final nomCtrl = TextEditingController();
    final pourcentageCtrl = TextEditingController();
    final ajout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nouveau palier'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nomCtrl, decoration: const InputDecoration(labelText: 'Nom (ex. Tranche 1)')),
            const SizedBox(height: 12),
            TextField(
              controller: pourcentageCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Pourcentage'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Ajouter')),
        ],
      ),
    );
    if (ajout != true || !mounted) return;

    final pourcentage = double.tryParse(pourcentageCtrl.text.replaceAll(',', '.'));
    if (nomCtrl.text.trim().isEmpty || pourcentage == null || pourcentage <= 0) return;

    try {
      final palier = PalierPaiementConfig(
        id: '',
        etablissementId: widget.etablissementId,
        anneeScolaireId: widget.anneeScolaireId,
        nom: nomCtrl.text.trim(),
        pourcentage: pourcentage,
        ordre: existants.length + 1,
      );
      await ref.read(scolariteRepositoryProvider).enregistrerPalierPaiement(palier);
      if (!mounted) return;
      ref.invalidate(paliersPaiementConfigProvider(_params));
    } on ErreurScolarite {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible d'ajouter ce palier (la somme dépasserait 100 %).")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final frais = ref.watch(fraisScolariteConfigProvider(_params));
    final paliers = ref.watch(paliersPaiementConfigProvider(_params));

    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres financiers')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Tarif par défaut', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          frais.when(
            loading: () => const ShimmerCarteListe(),
            error: (e, _) => const Text('Tarifs indisponibles hors connexion pour le moment.'),
            data: (liste) {
              FraisScolariteConfig? defaut;
              for (final f in liste) {
                if (f.estTarifParDefaut) defaut = f;
              }
              if (defaut != null && _montantAnnuelCtrl.text.isEmpty) {
                _montantAnnuelCtrl.text = defaut.montantAnnuel.toStringAsFixed(0);
                _fraisInscriptionCtrl.text = defaut.fraisInscription.toStringAsFixed(0);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _montantAnnuelCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Montant annuel'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _fraisInscriptionCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Frais d\'inscription'),
                  ),
                  if (_erreurTarif != null) ...[
                    const SizedBox(height: 8),
                    Text(_erreurTarif!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _enCoursTarif ? null : () => _enregistrerTarif(existant: defaut),
                    child: _enCoursTarif
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Enregistrer le tarif'),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Paliers de paiement', style: Theme.of(context).textTheme.titleMedium),
              paliers.maybeWhen(
                data: (liste) => TextButton.icon(
                  onPressed: () => _ajouterPalier(liste),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter'),
                ),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          paliers.when(
            loading: () => const ShimmerCarteListe(),
            error: (e, _) => const Text('Paliers indisponibles hors connexion pour le moment.'),
            data: (liste) {
              if (liste.isEmpty) return const Text('Aucun palier configuré (paiement en une fois).');
              final somme = liste.fold<double>(0, (s, p) => s + p.pourcentage);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final p in liste)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(p.nom),
                        trailing: Text('${p.pourcentage.toStringAsFixed(0)} %'),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'Total : ${somme.toStringAsFixed(0)} %',
                    style: TextStyle(
                      color: somme >= 100 ? context.palette.succes : context.palette.encreSecondaire,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
