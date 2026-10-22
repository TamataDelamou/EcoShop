import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/bandeau_synchronisation.dart';
import '../application/reseau_providers.dart';
import '../domain/reseau.dart';
import 'ecran_demande_reseau.dart';
import 'ecran_pilotage_reseau.dart';
import 'ecran_reseau_ecole.dart';
import 'elements_reseau.dart';

/// Point d'entrée des réseaux d'établissements : les réseaux que le compte
/// pilote (Direction Générale, adjoint, observateur), ceux auxquels son
/// école appartient ou est invitée, et sa demande de création en cours.
class EcranMesReseaux extends ConsumerWidget {
  const EcranMesReseaux({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reseaux = ref.watch(mesReseauxProvider);
    final demande = ref.watch(maDemandeReseauProvider).valueOrNull;
    final peutDemander = demande == null || !demande.enAttente;

    return Scaffold(
      appBar: AppBar(title: const Text('Réseaux d’établissements')),
      floatingActionButton: peutDemander
          ? FloatingActionButton.extended(
              key: const Key('bouton_creer_reseau'),
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute<bool>(builder: (_) => const EcranDemandeReseau()));
                ref.invalidate(mesReseauxProvider);
              },
              icon: const Icon(Icons.add),
              label: const Text('Créer un réseau'),
            )
          : null,
      body: Column(
        children: [
          const BandeauSynchronisation(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(mesReseauxProvider);
                ref.invalidate(maDemandeReseauProvider);
              },
              child: reseaux.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ListView(children: [
                  ErreurChargementReseau(erreur: e, reessayer: () => ref.invalidate(mesReseauxProvider)),
                ]),
                data: (liste) => ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [
                    if (demande != null) _CarteDemande(demande: demande),
                    if (liste.isEmpty && demande == null)
                      const EtatVideReseau(
                        icone: Icons.hub_outlined,
                        texte: 'Aucun réseau pour le moment.\n\nVotre école recevra ici les invitations des réseaux. '
                            'Vous pouvez aussi créer le réseau de votre organisation.',
                      ),
                    for (final r in liste) _CarteReseau(reseau: r),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CarteDemande extends StatelessWidget {
  const _CarteDemande({required this.demande});

  final DemandeReseau demande;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (icone, couleur, texte) = switch (demande.statut) {
      'acceptee' => (Icons.check_circle_outline, palette.succes, 'Demande acceptée : le réseau est créé.'),
      'refusee' => (
          Icons.error_outline,
          palette.erreur,
          'Demande à compléter. Motif : ${demande.motifRefus ?? 'non précisé'}. Vous pouvez en envoyer une nouvelle.',
        ),
      _ => (
          Icons.hourglass_top_rounded,
          palette.accent,
          'Demande en cours d’examen par Global Service Groupe. Les frais de création sont réglés avant la validation.',
        ),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icone, color: couleur),
        title: Text('Réseau « ${demande.nom} »'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(texte),
            if (demande.enAttenteEnvoi) const Padding(padding: EdgeInsets.only(top: 6), child: PastilleEnAttente()),
          ],
        ),
      ),
    );
  }
}

class _CarteReseau extends StatelessWidget {
  const _CarteReseau({required this.reseau});

  final MonReseau reseau;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final membres = reseau.ecoles.where((e) => e.statut == 'membre' || e.statut == 'retrait_demande').length;
    final invitations = reseau.ecoles.where((e) => e.statut == 'invite').toList();
    final sousTitre = reseau.estResponsable
        ? '${rolesReseau[reseau.monRole] ?? ''} · $membres école${membres > 1 ? 's' : ''} membre${membres > 1 ? 's' : ''}'
        : invitations.isNotEmpty
            ? 'Invitation à rejoindre ce réseau'
            : reseau.ecoles.map((e) => '${e.nom} : ${e.libelleStatut}').join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: palette.primaire.withValues(alpha: 0.12),
          child: Icon(reseau.estResponsable ? Icons.account_tree_outlined : Icons.hub_outlined, color: palette.primaire),
        ),
        title: Text(reseau.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(sousTitre),
        trailing: !reseau.estResponsable && invitations.isNotEmpty
            ? Badge(label: const Text('1'), child: Icon(Icons.mail_outline, color: palette.accent))
            : const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => reseau.estResponsable
              ? EcranPilotageReseau(reseauId: reseau.id, nom: reseau.nom)
              : EcranReseauEcole(reseauId: reseau.id, nom: reseau.nom),
        )),
      ),
    );
  }
}
