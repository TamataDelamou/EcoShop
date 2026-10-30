import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/role_racine.dart';
import '../../annonces/presentation/ecran_annonces.dart';
import '../../annonces/presentation/ecran_annonces_direction.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/profil.dart';
import '../../cahier_liaison/presentation/ecran_eleves_liaison.dart';
import '../../groupes_classe/presentation/ecran_groupes_classe.dart';
import '../../planification/presentation/ecran_agenda_evenements.dart';
import '../../planification/presentation/ecran_emploi_du_temps.dart';
import '../../planification/presentation/ecran_planification_classe.dart';
import '../../postes/application/postes_providers.dart';
import '../../scolarite/application/scolarite_providers.dart';

/// Une ligne d'une page d'entrée : grande zone de toucher, badge lu par
/// TalkBack (« Annonces, 3 nouvelles »).
class LigneEntree extends StatelessWidget {
  const LigneEntree({
    super.key,
    required this.icone,
    required this.titre,
    required this.sousTitre,
    required this.onTap,
    this.badge = 0,
    this.libelleBadge = 'nouveau',
  });

  final IconData icone;
  final String titre;
  final String sousTitre;
  final VoidCallback? onTap;
  final int badge;
  final String libelleBadge;

  @override
  Widget build(BuildContext context) {
    final schema = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: badge > 0 ? '$titre, $badge $libelleBadge${badge > 1 ? 's' : ''}' : titre,
      excludeSemantics: true,
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          minVerticalPadding: 14,
          leading: Icon(icone, color: schema.primary),
          title: Text(titre, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(sousTitre),
          trailing: badge > 0
              ? Badge(label: Text('$badge'), backgroundColor: const Color(0xFFB9480F))
              : const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
}

/// Destination « Messages » : annonces, cahier de liaison (parents ↔ école)
/// et groupes de classe (élèves et enseignants, REG-34 ; jamais les parents).
class EcranMessages extends ConsumerWidget {
  const EcranMessages({super.key, required this.profil, this.badges = const {}});

  final Profil profil;
  final Map<String, int> badges;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etablissement = ref.watch(etablissementActifProvider);
    final droits = profil.roleRacine == RoleRacine.personnel
        ? ref.watch(mesPermissionsProvider).valueOrNull ?? const <String>{}
        : const <String>{};
    final role = profil.roleRacine;
    final direction = role == RoleRacine.direction;
    final ecritCahier = role == RoleRacine.enseignant || direction || droits.contains('scolarite.liaison.ecrire');
    final groupes = role == RoleRacine.eleve || role == RoleRacine.enseignant || direction ||
        droits.contains('communication.groupe.moderer');
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          LigneEntree(
            key: const Key('messages_annonces'),
            icone: Icons.campaign_outlined,
            titre: 'Annonces',
            sousTitre: direction ? 'Publiez une annonce, voyez qui l’a lue' : 'Les annonces de l’école',
            badge: badges['annonces_non_lues'] ?? 0,
            libelleBadge: 'nouvelle',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => direction && etablissement != null
                  ? EcranAnnoncesDirection(etablissementId: etablissement.id)
                  : const EcranAnnonces(),
            )),
          ),
          if (role == RoleRacine.parent || (ecritCahier && etablissement != null))
            LigneEntree(
              key: const Key('messages_cahier'),
              icone: Icons.menu_book_outlined,
              titre: 'Cahier de liaison',
              sousTitre: role == RoleRacine.parent
                  ? 'Les mots de l’école ; écrire à un enseignant'
                  : 'Écrivez aux parents au sujet d’un élève',
              badge: badges['cahier_non_lu'] ?? 0,
              libelleBadge: 'nouveau mot',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => role == RoleRacine.parent
                    ? const EcranElevesLiaison()
                    : EcranElevesLiaison(etablissementId: etablissement!.id, direction: direction),
              )),
            ),
          if (groupes && etablissement != null)
            LigneEntree(
              key: const Key('messages_groupes'),
              icone: Icons.forum_outlined,
              titre: role == RoleRacine.eleve ? 'Ma classe' : 'Groupes de classe',
              sousTitre: role == RoleRacine.eleve
                  ? 'Échanger avec ta classe et tes enseignants'
                  : 'Les élèves et enseignants de vos classes',
              badge: badges['groupes_non_lus'] ?? 0,
              libelleBadge: 'nouveau message',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => EcranGroupesClasse(
                  etablissementId: etablissement.id,
                  eleve: role == RoleRacine.eleve,
                  direction: direction,
                ),
              )),
            ),
        ],
      ),
    );
  }
}

/// Destination « Agenda » : emploi du temps et agenda de l'école.
class EcranAgenda extends ConsumerWidget {
  const EcranAgenda({super.key, required this.profil, this.aujourdhui});

  final Profil profil;

  /// Cours du jour (accueil, REG-21), affichés en tête s'ils sont connus.
  final Widget? aujourdhui;

  Future<void> _emploiFamille(BuildContext context, WidgetRef ref, String ficheId, String titre) async {
    final inscriptions = await ref.read(inscriptionsDeFicheProvider(ficheId).future);
    if (inscriptions.isEmpty || !context.mounted) return;
    final i = inscriptions.first;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EcranPlanificationClasse(classeId: i.classeId, anneeId: i.anneeScolaireId, titre: titre),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = profil.roleRacine;
    final etablissement = ref.watch(etablissementActifProvider);
    final anneeId = ref.watch(structureEtablissementProvider(null)).valueOrNull?.anneeCourante?.id;
    final enfant = role == RoleRacine.parent ? ref.watch(enfantActifProvider) : null;
    final maFiche = role == RoleRacine.eleve ? ref.watch(maFicheProvider).valueOrNull : null;
    final personnel = role == RoleRacine.direction || role == RoleRacine.enseignant || role == RoleRacine.personnel;
    return Scaffold(
      appBar: AppBar(title: const Text('Agenda')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ?aujourdhui,
          if (role == RoleRacine.enseignant && etablissement != null && anneeId != null)
            LigneEntree(
              key: const Key('agenda_mon_emploi'),
              icone: Icons.calendar_view_week_outlined,
              titre: 'Mon emploi du temps',
              sousTitre: 'Vos cours de la semaine',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => EcranEmploiEnseignant(
                    enseignantProfileId: profil.id, etablissementId: etablissement.id, anneeId: anneeId),
              )),
            ),
          if (enfant != null)
            LigneEntree(
              key: const Key('agenda_emploi_enfant'),
              icone: Icons.calendar_view_week_outlined,
              titre: 'Emploi du temps de ${enfant.prenom}',
              sousTitre: 'Les cours de la semaine',
              onTap: () => _emploiFamille(context, ref, enfant.id, enfant.nomComplet),
            ),
          if (maFiche != null)
            LigneEntree(
              key: const Key('agenda_mon_emploi_eleve'),
              icone: Icons.calendar_view_week_outlined,
              titre: 'Mon emploi du temps',
              sousTitre: 'Mes cours de la semaine',
              onTap: () => _emploiFamille(context, ref, maFiche.id, maFiche.nomComplet),
            ),
          if (personnel && etablissement != null && anneeId != null)
            LigneEntree(
              key: const Key('agenda_ecole'),
              icone: Icons.event_outlined,
              titre: 'Agenda de l’école',
              sousTitre: 'Réunions, examens, congés, sorties',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => EcranAgendaEvenements(
                  etablissementId: etablissement.id,
                  anneeId: anneeId,
                  peutCreer: role == RoleRacine.direction,
                ),
              )),
            ),
        ],
      ),
    );
  }
}
