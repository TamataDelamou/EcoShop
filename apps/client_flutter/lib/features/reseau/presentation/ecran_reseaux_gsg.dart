import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../application/reseau_providers.dart';
import '../domain/reseau.dart';
import 'elements_reseau.dart';

/// Backoffice GSG des réseaux (cahier 30.1 et 30.3) : demandes de création
/// à valider (frais de création réglés) ou refuser (motif), vue d'ensemble
/// en lecture seule, retraits d'écoles à autoriser (règle 28.4).
class EcranReseauxGsg extends StatelessWidget {
  const EcranReseauxGsg({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Réseaux d’établissements'),
          bottom: const TabBar(tabs: [Tab(text: 'Demandes'), Tab(text: 'Réseaux')]),
        ),
        body: const TabBarView(children: [_Demandes(), _VueEnsemble()]),
      ),
    );
  }
}

class _Demandes extends ConsumerWidget {
  const _Demandes();

  Future<void> _traiter(BuildContext context, WidgetRef ref, DemandeReseau d, bool accepter) async {
    final motif = TextEditingController();
    var frais = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: Text(accepter ? 'Accepter « ${d.nom} »' : 'Refuser « ${d.nom} »'),
          content: accepter
              ? CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: frais,
                  onChanged: (v) => setState(() => frais = v ?? false),
                  title: const Text('Les frais de création du réseau ont été réglés'),
                )
              : TextField(
                  controller: motif,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Motif (envoyé au demandeur)', border: OutlineInputBorder()),
                ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
            FilledButton(
              onPressed: accepter && !frais ? null : () => Navigator.pop(c, true),
              child: Text(accepter ? 'Créer le réseau' : 'Refuser'),
            ),
          ],
        ),
      ),
    );
    // Pas de dispose() : la boîte se referme encore (animation).
    final texte = motif.text.trim();
    if (ok != true) return;
    try {
      await ref.read(reseauRepositoryProvider).traiterDemande(
            demandeId: d.id,
            accepter: accepter,
            motif: accepter ? null : texte,
            fraisRegles: frais,
          );
      ref.invalidate(demandesReseauGsgProvider);
      ref.invalidate(reseauxGsgProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(accepter ? 'Réseau créé, courriel envoyé au demandeur.' : 'Demande refusée, motif envoyé.'),
        ));
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(messageErreurReseau(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final demandes = ref.watch(demandesReseauGsgProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(demandesReseauGsgProvider),
      child: demandes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [
          ErreurChargementReseau(erreur: e, reessayer: () => ref.invalidate(demandesReseauGsgProvider)),
        ]),
        data: (liste) => liste.isEmpty
            ? ListView(children: const [EtatVideReseau(icone: Icons.inbox_outlined, texte: 'Aucune demande.')])
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final d in liste)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(d.nom, style: const TextStyle(fontWeight: FontWeight.w600))),
                                StatutEcole(
                                  statut: d.enAttente ? 'invite' : (d.statut == 'acceptee' ? 'membre' : 'refuse'),
                                  libelle: switch (d.statut) {
                                    'acceptee' => 'Acceptée',
                                    'refusee' => 'Refusée',
                                    _ => 'À traiter',
                                  },
                                ),
                              ],
                            ),
                            Text(d.denomination),
                            const SizedBox(height: 6),
                            Text(
                              [
                                typesReseau[d.typeReseau] ?? d.typeReseau,
                                if (d.paysCode != null) d.paysCode!,
                                if (d.premierResponsable != null) 'Responsable : ${d.premierResponsable}',
                                if (d.telephone != null) d.telephone!,
                                if (d.courriel != null) d.courriel!,
                                if (d.adresse != null) d.adresse!,
                                'Reçue le ${dateCourte(d.creeLe)}',
                              ].join(' · '),
                              style: TextStyle(color: palette.encreSecondaire, fontSize: 13),
                            ),
                            if (d.message != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('« ${d.message} »')),
                            if (d.motifRefus != null) Text('Motif : ${d.motifRefus}', style: TextStyle(color: palette.erreur)),
                            if (d.enAttente)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(onPressed: () => _traiter(context, ref, d, false), child: const Text('Refuser')),
                                    const SizedBox(width: 8),
                                    FilledButton(onPressed: () => _traiter(context, ref, d, true), child: const Text('Accepter')),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _VueEnsemble extends ConsumerWidget {
  const _VueEnsemble();

  Future<void> _decider(BuildContext context, WidgetRef ref, String reseauId, RetraitADecider r, bool accorder) async {
    try {
      await ref.read(reseauRepositoryProvider).deciderRetrait(
            reseauId: reseauId,
            etablissementId: r.etablissementId,
            accorder: accorder,
          );
      ref.invalidate(reseauxGsgProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(accorder ? '${r.nom} a quitté le réseau.' : 'Retrait refusé : ${r.nom} reste membre.'),
        ));
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(messageErreurReseau(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final reseaux = ref.watch(reseauxGsgProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(reseauxGsgProvider),
      child: reseaux.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [ErreurChargementReseau(erreur: e, reessayer: () => ref.invalidate(reseauxGsgProvider))]),
        data: (liste) => liste.isEmpty
            ? ListView(children: const [EtatVideReseau(icone: Icons.hub_outlined, texte: 'Aucun réseau créé.')])
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final r in liste)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(r.denomination, style: TextStyle(color: palette.encreSecondaire)),
                            const SizedBox(height: 6),
                            Text(r.statut == 'dissous'
                                ? 'Dissous'
                                : '${r.membres} école(s) membre(s) · ${r.invitations} invitation(s) en cours'),
                            for (final retrait in r.retraits)
                              Container(
                                margin: const EdgeInsets.only(top: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: palette.premium.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${retrait.nom} demande à quitter le réseau',
                                        style: const TextStyle(fontWeight: FontWeight.w600)),
                                    if (retrait.motif != null) Text('Motif : ${retrait.motif}'),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton(
                                          onPressed: () => _decider(context, ref, r.id, retrait, false),
                                          child: const Text('Refuser'),
                                        ),
                                        FilledButton(
                                          onPressed: () => _decider(context, ref, r.id, retrait, true),
                                          child: const Text('Autoriser le retrait'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
