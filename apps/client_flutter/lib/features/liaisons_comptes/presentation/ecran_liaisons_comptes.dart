import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/liaisons_providers.dart';
import '../domain/liaison_compte.dart';

/// Comptes liés aux élèves de l'école (REG-18, partie E), pour la direction :
///
/// - liaisons parents en attente (au-delà du plafond, ou refaites après une
///   révocation) : accepter ou refuser ;
/// - comptes liés ces 30 derniers jours : révoquer une liaison suspecte ;
/// - plafond de comptes parents par élève (2 par défaut).
class EcranLiaisonsComptes extends ConsumerWidget {
  const EcranLiaisonsComptes({super.key, required this.etablissementId});

  final String etablissementId;

  Future<void> _rafraichir(WidgetRef ref) async {
    ref.invalidate(liaisonsComptesProvider(etablissementId));
    await ref.read(liaisonsComptesProvider(etablissementId).future).catchError((_) => <LiaisonCompte>[]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liaisons = ref.watch(liaisonsComptesProvider(etablissementId));

    return Scaffold(
      appBar: AppBar(title: const Text('Comptes liés aux élèves')),
      body: RefreshIndicator(
        onRefresh: () => _rafraichir(ref),
        child: liaisons.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(e is ErreurLiaisons ? e.message : 'Liste indisponible. Tirez pour réessayer.',
                  textAlign: TextAlign.center),
            ],
          ),
          data: (toutes) {
            final enAttente = [for (final l in toutes) if (l.statut == StatutLiaison.enAttente) l];
            final recentes = [for (final l in toutes) if (l.statut != StatutLiaison.enAttente) l];
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _Plafond(etablissementId: etablissementId),
                const Divider(),
                _Titre('En attente de votre accord (${enAttente.length})'),
                if (enAttente.isEmpty)
                  const _Vide('Aucune demande en attente.')
                else
                  for (final l in enAttente) _LigneLiaison(liaison: l, etablissementId: etablissementId),
                const Divider(),
                const _Titre('Comptes liés ces 30 derniers jours'),
                if (recentes.isEmpty)
                  const _Vide('Aucun compte lié récemment.')
                else
                  for (final l in recentes) _LigneLiaison(liaison: l, etablissementId: etablissementId),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Titre extends StatelessWidget {
  const _Titre(this.texte);
  final String texte;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(texte, style: Theme.of(context).textTheme.titleSmall),
      );
}

class _Vide extends StatelessWidget {
  const _Vide(this.texte);
  final String texte;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(texte, style: Theme.of(context).textTheme.bodySmall),
      );
}

class _LigneLiaison extends ConsumerStatefulWidget {
  const _LigneLiaison({required this.liaison, required this.etablissementId});

  final LiaisonCompte liaison;
  final String etablissementId;

  @override
  ConsumerState<_LigneLiaison> createState() => _LigneLiaisonState();
}

class _LigneLiaisonState extends ConsumerState<_LigneLiaison> {
  bool _enCours = false;

  Future<void> _agir(Future<void> Function() action, String reussite) async {
    setState(() => _enCours = true);
    final messager = ScaffoldMessenger.of(context);
    try {
      await action();
      ref.invalidate(liaisonsComptesProvider(widget.etablissementId));
      messager.showSnackBar(SnackBar(content: Text(reussite)));
    } on ErreurLiaisons catch (e) {
      messager.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _revoquer() async {
    final l = widget.liaison;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogue) => AlertDialog(
        title: const Text('Révoquer cette liaison ?'),
        content: Text(
          '${l.compteAffiche} n’aura plus accès à la scolarité de ${l.eleve}. '
          'S’il refait la liaison, elle attendra votre accord.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogue).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(dialogue).pop(true), child: const Text('Révoquer')),
        ],
      ),
    );
    if (ok != true) return;
    await _agir(() => ref.read(liaisonsRepositoryProvider).revoquer(l), 'Liaison révoquée.');
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.liaison;
    final theme = Theme.of(context);
    final role = l.nature == NatureLiaison.eleve ? 'Compte élève' : 'Compte parent';
    final date = l.lieeLe == null
        ? ''
        : ' · ${l.lieeLe!.day.toString().padLeft(2, '0')}/${l.lieeLe!.month.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Card(
        key: ValueKey('liaison_${l.nature.code}_${l.liaisonId}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.eleve.isEmpty ? 'Élève' : l.eleve, style: theme.textTheme.titleMedium),
              const SizedBox(height: 2),
              Text('$role : ${l.compteAffiche}'
                  '${l.identifiantEcoshop != null && l.compte.isNotEmpty ? ' (${l.identifiantEcoshop})' : ''}'),
              Text('${l.statut.libelle}$date', style: theme.textTheme.bodySmall),
              if (l.peutEtreDecidee || l.peutEtreRevoquee)
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      if (l.peutEtreDecidee) ...[
                        TextButton(
                          onPressed: _enCours
                              ? null
                              : () => _agir(
                                    () => ref.read(liaisonsRepositoryProvider).decider(l.liaisonId, accepter: false),
                                    'Demande refusée. Le parent est prévenu.',
                                  ),
                          child: const Text('Refuser'),
                        ),
                        FilledButton(
                          onPressed: _enCours
                              ? null
                              : () => _agir(
                                    () => ref.read(liaisonsRepositoryProvider).decider(l.liaisonId, accepter: true),
                                    'Liaison acceptée. Le parent est prévenu.',
                                  ),
                          child: const Text('Accepter'),
                        ),
                      ],
                      if (l.peutEtreRevoquee)
                        TextButton(
                          onPressed: _enCours ? null : _revoquer,
                          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                          child: const Text('Révoquer'),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Plafond de comptes parents par élève, réglable de 1 à 10.
class _Plafond extends ConsumerStatefulWidget {
  const _Plafond({required this.etablissementId});

  final String etablissementId;

  @override
  ConsumerState<_Plafond> createState() => _PlafondState();
}

class _PlafondState extends ConsumerState<_Plafond> {
  bool _enCours = false;

  Future<void> _changer(int valeur) async {
    setState(() => _enCours = true);
    final messager = ScaffoldMessenger.of(context);
    try {
      await ref.read(liaisonsRepositoryProvider).definirPlafond(widget.etablissementId, valeur);
      ref.invalidate(plafondParentsProvider(widget.etablissementId));
    } on ErreurLiaisons catch (e) {
      messager.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plafond = ref.watch(plafondParentsProvider(widget.etablissementId)).valueOrNull;
    return ListTile(
      key: const Key('plafond_parents'),
      leading: const Icon(Icons.family_restroom_outlined),
      title: const Text('Comptes parents par élève'),
      subtitle: const Text('Au-delà, chaque nouveau compte attend votre accord.'),
      trailing: plafond == null
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Moins',
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: _enCours || plafond <= 1 ? null : () => _changer(plafond - 1),
                ),
                Text('$plafond', key: const Key('plafond_valeur'), style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  tooltip: 'Plus',
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: _enCours || plafond >= 10 ? null : () => _changer(plafond + 1),
                ),
              ],
            ),
    );
  }
}
