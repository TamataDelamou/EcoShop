import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/journal_rejets.dart';
import '../sync/sync_providers.dart';

String _dateHeure(DateTime d) {
  String deux(int v) => v.toString().padLeft(2, '0');
  return '${deux(d.day)}/${deux(d.month)} à ${d.hour}h${deux(d.minute)}';
}

/// Bandeau des écrans qui fonctionnent hors connexion : âge des données
/// affichées quand elles viennent de l'appareil, opérations en attente
/// d'envoi, opérations refusées au retour du réseau. Invisible quand tout
/// est à jour. (L'état « hors ligne » lui-même est signalé par la coquille.)
class BandeauSynchronisation extends ConsumerWidget {
  const BandeauSynchronisation({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suivi = ref.watch(suiviSyncProvider).valueOrNull;
    final fraicheur = ref.watch(fraicheurHorsLigneProvider);
    return ValueListenableBuilder<DateTime?>(
      valueListenable: fraicheur,
      builder: (context, date, _) {
        final lignes = <Widget>[];
        final schema = Theme.of(context).colorScheme;
        if (date != null) {
          lignes.add(_Ligne(
            cle: const Key('bandeau_donnees_appareil'),
            icone: Icons.cloud_off_outlined,
            texte: 'Pas de réseau : données enregistrées sur cet appareil le ${_dateHeure(date)}.',
          ));
        }
        if (suivi != null && suivi.enAttente > 0) {
          lignes.add(_Ligne(
            cle: const Key('bandeau_en_attente'),
            icone: Icons.schedule_send_outlined,
            texte: '${suivi.enAttente} opération(s) en attente d\'envoi — envoi automatique au retour du réseau.',
          ));
        }
        if (suivi != null && suivi.rejetees > 0) {
          lignes.add(_Ligne(
            cle: const Key('bandeau_rejets'),
            icone: Icons.report_outlined,
            couleur: schema.error,
            texte: '${suivi.rejetees} opération(s) refusée(s) par le serveur.',
            action: TextButton(
              onPressed: () => showModalBottomSheet<void>(context: context, builder: (_) => const _ListeRejets()),
              child: const Text('Voir'),
            ),
          ));
        }
        if (lignes.isEmpty) return const SizedBox.shrink();
        return Material(
          color: schema.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Column(mainAxisSize: MainAxisSize.min, children: lignes),
          ),
        );
      },
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({required this.cle, required this.icone, required this.texte, this.couleur, this.action});

  final Key cle;
  final IconData icone;
  final String texte;
  final Color? couleur;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final teinte = couleur ?? Theme.of(context).colorScheme.onTertiaryContainer;
    return Row(key: cle, children: [
      Icon(icone, size: 18, color: teinte),
      const SizedBox(width: 8),
      Expanded(child: Text(texte, style: TextStyle(color: teinte))),
      ?action,
    ]);
  }
}

class _ListeRejets extends ConsumerStatefulWidget {
  const _ListeRejets();

  @override
  ConsumerState<_ListeRejets> createState() => _ListeRejetsState();
}

class _ListeRejetsState extends ConsumerState<_ListeRejets> {
  late Future<List<RejetSynchronisation>> _rejets = ref.read(journalRejetsProvider).lister();

  Future<void> _retirer(String id) async {
    await ref.read(journalRejetsProvider).retirer(id);
    if (mounted) setState(() => _rejets = ref.read(journalRejetsProvider).lister());
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<List<RejetSynchronisation>>(
        future: _rejets,
        builder: (context, instantane) {
          final liste = instantane.data ?? const <RejetSynchronisation>[];
          return ListView(shrinkWrap: true, children: [
            ListTile(
              title: Text('Opérations refusées au retour du réseau', style: Theme.of(context).textTheme.titleMedium),
              subtitle: const Text('Elles n\'ont pas été enregistrées. Corrigez puis ressaisissez si besoin.'),
            ),
            for (final r in liste)
              ListTile(
                leading: Icon(Icons.report_outlined, color: Theme.of(context).colorScheme.error),
                title: Text(r.libelle),
                subtitle: Text(r.message),
                trailing: TextButton(onPressed: () => _retirer(r.id), child: const Text('Compris')),
              ),
          ]);
        },
      ),
    );
  }
}
