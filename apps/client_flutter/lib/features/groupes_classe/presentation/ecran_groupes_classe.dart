import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/groupes_classe_providers.dart';
import '../domain/groupe_classe.dart';
import 'ecran_fil_groupe.dart';
import 'ecran_heures_messagerie.dart';

String _quand(DateTime d, DateTime maintenant) {
  final memeJour = d.year == maintenant.year && d.month == maintenant.month && d.day == maintenant.day;
  return memeJour
      ? '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

/// Groupes de classe (REG-34) : le groupe de sa classe pour l'élève ; les
/// groupes de ses classes pour l'enseignant, qui ouvre ceux qui manquent ;
/// tous les groupes pour la direction, qui règle aussi les heures de
/// messagerie de l'école.
class EcranGroupesClasse extends ConsumerWidget {
  const EcranGroupesClasse({super.key, required this.etablissementId, this.eleve = false, this.direction = false});

  final String etablissementId;
  final bool eleve;
  final bool direction;

  Future<void> _ouvrir(BuildContext context, WidgetRef ref, GroupeClasse g) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EcranFilGroupe(groupe: g, etablissementId: etablissementId),
    ));
    ref.invalidate(mesGroupesProvider(etablissementId));
  }

  Future<void> _creer(BuildContext context, WidgetRef ref, ClasseSansGroupe c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Ouvrir le groupe de ${c.classe} ?'),
        content: const Text(
          'Les élèves de la classe et leurs enseignants y échangeront, en texte seulement, pendant les heures '
          'de l’école. Vous pourrez le réserver aux annonces, retirer un message ou le suspendre. '
          'Les parents n’y ont pas accès : ils vous écrivent dans le cahier de liaison.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Ouvrir')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(groupesClasseRepositoryProvider).creer(c.classeId);
      ref.invalidate(mesGroupesProvider(etablissementId));
    } on ErreurGroupe catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupes = ref.watch(mesGroupesProvider(etablissementId));
    final heures = ref.watch(heuresMessagerieProvider(etablissementId)).valueOrNull;
    final maintenant = DateTime.now();
    final schema = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(eleve ? 'Ma classe' : 'Groupes de classe')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(mesGroupesProvider(etablissementId));
          ref.invalidate(heuresMessagerieProvider(etablissementId));
        },
        child: groupes.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(padding: const EdgeInsets.all(24), children: [
            Text(e is ErreurGroupe ? e.message : 'Groupes indisponibles. Tirez pour réessayer.', textAlign: TextAlign.center),
          ]),
          data: (mes) => ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              if (heures != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    key: const Key('heures_groupes'),
                    'Les groupes sont ouverts ${heures.libelle}.'
                    '${eleve ? '' : ' En dehors, les élèves lisent sans écrire et personne n’est réveillé par une notification.'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (direction)
                ListTile(
                  key: const Key('regler_heures'),
                  leading: const Icon(Icons.schedule),
                  title: const Text('Heures de messagerie de l’école'),
                  subtitle: Text(heures?.libelle ?? 'À régler'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => EcranHeuresMessagerie(etablissementId: etablissementId, actuelles: heures),
                    ));
                    ref.invalidate(heuresMessagerieProvider(etablissementId));
                  },
                ),
              if (mes.groupes.isEmpty && mes.classesSansGroupe.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    eleve
                        ? 'Le groupe de ta classe n’est pas encore ouvert. Ton enseignant l’ouvrira.'
                        : 'Aucune classe pour l’année en cours.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final g in mes.groupes)
                ListTile(
                  key: ValueKey('groupe_${g.id}'),
                  leading: CircleAvatar(
                    backgroundColor: schema.primaryContainer,
                    child: Icon(g.elevesPeuventEcrire ? Icons.forum_outlined : Icons.campaign_outlined,
                        color: schema.onPrimaryContainer),
                  ),
                  title: Text(g.nom),
                  subtitle: Text(
                    [
                      if (!g.actif) 'Suspendu',
                      if (!g.elevesPeuventEcrire) 'Annonces seulement',
                      if (g.dernierLe != null)
                        '${g.dernierAuteur ?? ''} : ${g.dernierExtrait ?? 'message retiré'}'
                      else
                        'Aucun message',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (g.dernierLe != null) Text(_quand(g.dernierLe!, maintenant), style: Theme.of(context).textTheme.bodySmall),
                      if (g.signalements > 0)
                        Badge(
                          key: Key('signalements_${g.id}'),
                          backgroundColor: schema.error,
                          label: Text('${g.signalements} signalé${g.signalements > 1 ? 's' : ''}'),
                        )
                      else if (g.nonLus > 0)
                        Badge(key: Key('non_lus_${g.id}'), label: Text('${g.nonLus}')),
                    ],
                  ),
                  onTap: () => _ouvrir(context, ref, g),
                ),
              if (mes.classesSansGroupe.isNotEmpty) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text('Classes sans groupe', style: Theme.of(context).textTheme.titleSmall),
                ),
                for (final c in mes.classesSansGroupe)
                  ListTile(
                    key: ValueKey('ouvrir_groupe_${c.classeId}'),
                    leading: const Icon(Icons.add_comment_outlined),
                    title: Text(c.classe),
                    subtitle: const Text('Ouvrir le groupe de la classe'),
                    onTap: () => _creer(context, ref, c),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
