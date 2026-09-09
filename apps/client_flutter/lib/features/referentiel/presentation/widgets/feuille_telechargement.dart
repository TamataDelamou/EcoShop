import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../application/referentiel_providers.dart';
import '../../domain/paquet_referentiel.dart';
import '../../domain/pays_pedagogique.dart';
import '../../domain/referentiel_repository.dart';

/// Ouvre la feuille de téléchargement hors-ligne pour [pays].
Future<void> afficherFeuilleTelechargement(
  BuildContext context,
  PaysPedagogique pays,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _FeuilleTelechargement(pays: pays),
  );
}

/// Liste les [PaquetReferentiel] publiés d'un pays et permet de les
/// télécharger avec vérification d'empreinte SHA-256 (contrat M04 §5).
class _FeuilleTelechargement extends ConsumerWidget {
  const _FeuilleTelechargement({required this.pays});

  final PaysPedagogique pays;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paquets = ref.watch(paquetsDisponiblesProvider(pays.codeIso));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.download_for_offline_outlined,
                    color: context.palette.primaire),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Paquets hors-ligne — ${pays.nom}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              "L'empreinte SHA-256 de chaque paquet est vérifiée avant toute "
              'mise en cache locale.',
              style: TextStyle(color: context.palette.encreSecondaire, fontSize: 13),
            ),
            const SizedBox(height: 16),
            paquets.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (erreur, _) => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Connexion requise pour lister les paquets disponibles.'),
              ),
              data: (liste) => liste.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Aucun paquet publié pour ce pays.'),
                    )
                  : Column(
                      children: [
                        for (final paquet in liste)
                          _LignePaquet(paquet: paquet),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LignePaquet extends ConsumerStatefulWidget {
  const _LignePaquet({required this.paquet});

  final PaquetReferentiel paquet;

  @override
  ConsumerState<_LignePaquet> createState() => _LignePaquetState();
}

enum _EtatTelechargement { repos, enCours, reussi, echec }

class _LignePaquetState extends ConsumerState<_LignePaquet> {
  _EtatTelechargement _etat = _EtatTelechargement.repos;
  String? _messageErreur;

  Future<void> _telecharger() async {
    setState(() {
      _etat = _EtatTelechargement.enCours;
      _messageErreur = null;
    });

    try {
      await ref
          .read(telechargementPaquetServiceProvider)
          .telecharger(widget.paquet);
      if (!mounted) return;
      setState(() => _etat = _EtatTelechargement.reussi);
    } on ErreurReferentiel catch (e) {
      if (!mounted) return;
      setState(() {
        _etat = _EtatTelechargement.echec;
        _messageErreur = switch (e.code) {
          'PAQUET_INTEGRITE_INVALIDE' =>
            "Empreinte invalide : le fichier téléchargé a été rejeté.",
          'PAQUET_SANS_URL' => 'Ce paquet ne fournit pas encore de fichier.',
          _ => 'Échec du téléchargement — réessayez plus tard.',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final taille = (widget.paquet.tailleOctets / (1024 * 1024)).toStringAsFixed(1);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.inventory_2_outlined, color: context.palette.primaire),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Version ${widget.paquet.version}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('$taille Mo', style: TextStyle(
                        color: context.palette.encreSecondaire,
                        fontSize: 12,
                      )),
                  if (_messageErreur != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _messageErreur!,
                        style: TextStyle(color: context.palette.erreur, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            _BoutonEtat(etat: _etat, onAppui: _telecharger),
          ],
        ),
      ),
    );
  }
}

class _BoutonEtat extends StatelessWidget {
  const _BoutonEtat({required this.etat, required this.onAppui});

  final _EtatTelechargement etat;
  final VoidCallback onAppui;

  @override
  Widget build(BuildContext context) {
    return switch (etat) {
      _EtatTelechargement.enCours => const SizedBox(
          height: 24,
          width: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      _EtatTelechargement.reussi =>
        Icon(Icons.check_circle, color: context.palette.succes),
      _EtatTelechargement.echec => IconButton(
          icon: Icon(Icons.refresh, color: context.palette.erreur),
          onPressed: onAppui,
        ),
      _EtatTelechargement.repos => FilledButton(
          onPressed: onAppui,
          child: const Text('Télécharger'),
        ),
    };
  }
}
