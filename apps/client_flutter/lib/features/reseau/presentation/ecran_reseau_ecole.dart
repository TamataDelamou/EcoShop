import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/bandeau_synchronisation.dart';
import '../application/reseau_providers.dart';
import '../domain/reseau.dart';
import 'ecran_pilotage_reseau.dart' show CarteCirculaire;
import 'elements_reseau.dart';

/// Le réseau vu par la Direction d'une école : invitation à accepter ou
/// refuser, circulaires (accusé de lecture), calendrier commun à ajouter à
/// l'agenda de l'école, demande de retrait (accord de GSG, cahier 28.4).
class EcranReseauEcole extends ConsumerWidget {
  const EcranReseauEcole({super.key, required this.reseauId, required this.nom});

  final String reseauId;
  final String nom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reseau = ref.watch(mesReseauxProvider).value?.where((r) => r.id == reseauId).firstOrNull;
    final ecole = reseau?.ecoles.firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(reseau?.nom ?? nom)),
      body: Column(
        children: [
          const BandeauSynchronisation(),
          Expanded(
            child: reseau == null || ecole == null
                ? const EtatVideReseau(icone: Icons.hub_outlined, texte: 'Ce réseau n’est plus accessible.')
                : switch (ecole.statut) {
                    'invite' => _Invitation(reseau: reseau, ecole: ecole),
                    'membre' || 'retrait_demande' => _EspaceMembre(reseau: reseau, ecole: ecole),
                    _ => EtatVideReseau(icone: Icons.hub_outlined, texte: '${ecole.nom} : ${ecole.libelleStatut}.'),
                  },
          ),
        ],
      ),
    );
  }
}

class _Invitation extends ConsumerStatefulWidget {
  const _Invitation({required this.reseau, required this.ecole});

  final MonReseau reseau;
  final EcoleDuReseau ecole;

  @override
  ConsumerState<_Invitation> createState() => _InvitationState();
}

class _InvitationState extends ConsumerState<_Invitation> {
  bool _enCours = false;

  Future<void> _repondre(bool accepter) async {
    setState(() => _enCours = true);
    try {
      final recue = await ref.read(reseauRepositoryProvider).repondreInvitation(
            reseauId: widget.reseau.id,
            etablissementId: widget.ecole.etablissementId,
            accepter: accepter,
          );
      ref.invalidate(mesReseauxProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(!recue
            ? 'Réponse gardée sur le téléphone : elle partira au retour du réseau.'
            : accepter
                ? '${widget.ecole.nom} a rejoint le réseau.'
                : 'Invitation refusée.'),
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(messageErreurReseau(e))));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Icon(Icons.mark_email_unread_outlined, size: 56, color: palette.primaire),
        const SizedBox(height: 16),
        Text(
          'Le réseau « ${widget.reseau.nom} » invite ${widget.ecole.nom} à le rejoindre.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(widget.reseau.denomination, textAlign: TextAlign.center, style: TextStyle(color: palette.encreSecondaire)),
        const SizedBox(height: 20),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'En rejoignant le réseau :\n'
              '• sa Direction Générale voit les chiffres agrégés de l’école (effectifs, présence, recouvrement, '
              'personnel) — jamais le nom d’un élève ni ses notes ;\n'
              '• vous recevez ses circulaires et son calendrier commun, que vous ajoutez ou non à votre agenda ;\n'
              '• votre école garde ses données, ses tarifs et son autonomie.\n\n'
              'Quitter le réseau plus tard demande l’accord de Global Service Groupe.',
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const Key('bouton_accepter_reseau'),
          onPressed: _enCours ? null : () => _repondre(true),
          icon: const Icon(Icons.check),
          label: const Text('Rejoindre le réseau'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _enCours ? null : () => _repondre(false), child: const Text('Refuser')),
      ],
    );
  }
}

class _EspaceMembre extends ConsumerWidget {
  const _EspaceMembre({required this.reseau, required this.ecole});

  final MonReseau reseau;
  final EcoleDuReseau ecole;

  Future<void> _demanderRetrait(BuildContext context, WidgetRef ref) async {
    final motif = await doubleConfirmation(
      context,
      titre: 'Quitter le réseau',
      explication: '${ecole.nom} demande à quitter le réseau « ${reseau.nom} ». Le retrait ne sera effectif qu’après '
          'l’accord de Global Service Groupe ; d’ici là, l’école reste membre.',
      consigne: 'Indiquez le motif du retrait :',
      attendu: '',
      libelleAction: 'Demander le retrait',
      motifLibre: true,
    );
    if (motif == null) return;
    try {
      await ref.read(reseauRepositoryProvider).demanderRetrait(
            reseauId: reseau.id,
            etablissementId: ecole.etablissementId,
            motif: motif,
          );
      ref.invalidate(mesReseauxProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Demande de retrait transmise à Global Service Groupe.')),
        );
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(messageErreurReseau(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final circulaires = ref.watch(circulairesReseauProvider(reseau.id));
    final ({String reseauId, String? etablissementId}) cle = (reseauId: reseau.id, etablissementId: ecole.etablissementId);
    final evenements = ref.watch(evenementsReseauProvider(cle));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(circulairesReseauProvider(reseau.id));
        ref.invalidate(evenementsReseauProvider(cle));
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (ecole.statut == 'retrait_demande')
            Card(
              color: palette.premium.withValues(alpha: 0.1),
              child: const ListTile(
                leading: Icon(Icons.hourglass_top_rounded),
                title: Text('Retrait demandé'),
                subtitle: Text('En attente de la décision de Global Service Groupe.'),
              ),
            ),
          Text('Circulaires', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...circulaires.when<List<Widget>>(
            loading: () => [const LinearProgressIndicator()],
            error: (e, _) => [Text(messageErreurReseau(e))],
            data: (liste) => liste.isEmpty
                ? [Text('Aucune circulaire.', style: TextStyle(color: palette.encreSecondaire))]
                : [
                    for (final c in liste)
                      CarteCirculaire(
                        circulaire: c,
                        surOuverture: c.lue
                            ? null
                            : () async {
                                await ref.read(reseauRepositoryProvider).marquerLue(c.id);
                                ref.invalidate(circulairesReseauProvider(reseau.id));
                              },
                      ),
                  ],
          ),
          const SizedBox(height: 20),
          Text('Calendrier commun', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...evenements.when<List<Widget>>(
            loading: () => [const LinearProgressIndicator()],
            error: (e, _) => [Text(messageErreurReseau(e))],
            data: (liste) => liste.isEmpty
                ? [Text('Aucune date commune.', style: TextStyle(color: palette.encreSecondaire))]
                : [
                    for (final e in liste)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.event_outlined),
                          title: Text(e.titre),
                          subtitle: Text('${e.libelleType} · ${periode(e.debut, e.fin)}'),
                          trailing: e.importe
                              ? Icon(Icons.event_available, color: palette.succes)
                              : TextButton(
                                  onPressed: () async {
                                    try {
                                      await ref.read(reseauRepositoryProvider).importerEvenement(e.id, ecole.etablissementId);
                                      ref.invalidate(evenementsReseauProvider(cle));
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('« ${e.titre} » ajouté à l’agenda de l’école.')),
                                        );
                                      }
                                    } catch (err) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(content: Text(messageErreurReseau(err))));
                                      }
                                    }
                                  },
                                  child: const Text('Ajouter à l’agenda'),
                                ),
                        ),
                      ),
                  ],
          ),
          if (ecole.statut == 'membre') ...[
            const SizedBox(height: 32),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: palette.erreur),
              onPressed: () => _demanderRetrait(context, ref),
              icon: const Icon(Icons.logout),
              label: const Text('Quitter le réseau'),
            ),
          ],
        ],
      ),
    );
  }
}
