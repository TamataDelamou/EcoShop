import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/role_racine.dart';
import '../../../core/config/env.dart';
import '../../../core/providers.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/profil.dart';
import '../../referentiel/presentation/ecran_pays_pedagogiques.dart';
import '../../scolarite/presentation/ecran_scolarite.dart';
import '../../scolarite/presentation/ecran_structure_etablissement.dart';
import '../../scolarite/presentation/widgets/selecteur_enfant.dart';
import '../application/sync_composition.dart';

/// Onglet de la coquille applicative.
///
/// La composition dépend du rôle racine : la barre de navigation n'affiche que
/// ce que le rôle couvre. Ce filtrage est **ergonomique**, pas sécuritaire —
/// atteindre un onglet ne donne accès à aucune donnée que RLS refuse.
enum OngletCoquille {
  accueil('Accueil', Icons.home_outlined, Icons.home),
  scolarite('Scolarité', Icons.school_outlined, Icons.school),
  revision('Révision', Icons.psychology_outlined, Icons.psychology),
  boutique('Boutique', Icons.storefront_outlined, Icons.storefront),
  profil('Profil', Icons.person_outline, Icons.person);

  const OngletCoquille(this.libelle, this.icone, this.iconeActive);

  final String libelle;
  final IconData icone;
  final IconData iconeActive;

  /// Onglets pertinents pour un rôle racine.
  static List<OngletCoquille> pourRole(RoleRacine? role) => switch (role) {
        RoleRacine.eleve => const [accueil, scolarite, revision, boutique, profil],
        RoleRacine.parent => const [accueil, scolarite, boutique, profil],
        RoleRacine.enseignant => const [accueil, scolarite, profil],
        RoleRacine.direction => const [accueil, scolarite, boutique, profil],
        RoleRacine.vendeur => const [accueil, boutique, profil],
        _ => const [accueil, profil],
      };
}

/// Coquille applicative : navigation adaptative (barre en bas sur mobile,
/// rail latéral au-delà de 720 px de large) et bandeau hors-ligne.
class CoquilleApp extends ConsumerStatefulWidget {
  const CoquilleApp({super.key});

  @override
  ConsumerState<CoquilleApp> createState() => _CoquilleAppState();
}

class _CoquilleAppState extends ConsumerState<CoquilleApp> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Amorce une resynchronisation dès l'entrée dans l'application — les
    // écritures hors-ligne d'une session précédente ne doivent pas attendre
    // un futur changement de connectivité si le réseau est déjà disponible.
    // Gardé derrière `Env.estConfigure` : construire le moteur de sync exige
    // un client Supabase initialisé (jamais le cas en test ni en mode
    // diagnostic sans --dart-define).
    if (Env.estConfigure) {
      Future.microtask(() => ref.read(syncEngineProvider).synchroniser());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Env.estConfigure) {
      ref.listen<bool>(estEnLigneProvider, (etaitEnLigne, estEnLigne) {
        if (estEnLigne && etaitEnLigne == false) {
          ref.read(syncEngineProvider).synchroniser();
        }
      });
    }

    final profil = ref.watch(profilProvider).value;
    final onglets = OngletCoquille.pourRole(profil?.roleRacine);
    // Un changement de rôle ou de rattachement peut raccourcir la liste :
    // on borne l'index plutôt que de laisser une RangeError se produire.
    final index = _index < onglets.length ? _index : 0;
    final large = MediaQuery.sizeOf(context).width >= 720;

    final corps = _CorpsOnglet(onglet: onglets[index], profil: profil);

    return Scaffold(
      appBar: AppBar(
        title: Text(onglets[index].libelle),
        actions: const [_IndicateurEtablissement()],
      ),
      body: Column(
        children: [
          const _BandeauHorsLigne(),
          const SelecteurEnfant(),
          Expanded(
            child: large
                ? Row(
                    children: [
                      NavigationRail(
                        selectedIndex: index,
                        onDestinationSelected: (i) => setState(() => _index = i),
                        labelType: NavigationRailLabelType.all,
                        destinations: [
                          for (final o in onglets)
                            NavigationRailDestination(
                              icon: Icon(o.icone),
                              selectedIcon: Icon(o.iconeActive),
                              label: Text(o.libelle),
                            ),
                        ],
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: corps),
                    ],
                  )
                : corps,
          ),
        ],
      ),
      bottomNavigationBar: large
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (final o in onglets)
                  NavigationDestination(
                    icon: Icon(o.icone),
                    selectedIcon: Icon(o.iconeActive),
                    label: o.libelle,
                  ),
              ],
            ),
    );
  }
}

/// Bandeau affiché dès que la connectivité est perdue.
///
/// Les écritures continuent d'être acceptées et journalisées dans la file
/// outbox ; le bandeau signale simplement que la synchronisation est différée
/// (ch. 34-35).
class _BandeauHorsLigne extends ConsumerWidget {
  const _BandeauHorsLigne();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(estEnLigneProvider)) return const SizedBox.shrink();

    final schema = Theme.of(context).colorScheme;
    return Material(
      color: schema.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.cloud_off, size: 18, color: schema.onTertiaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Hors ligne — vos saisies seront synchronisées au retour du réseau.',
                style: TextStyle(color: schema.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rappel de l'établissement actif dans la barre d'application.
class _IndicateurEtablissement extends ConsumerWidget {
  const _IndicateurEtablissement();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etablissement = ref.watch(etablissementActifProvider);
    if (etablissement == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Center(
        child: Text(
          etablissement.nom,
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ),
    );
  }
}

/// Contenu de l'onglet courant.
///
/// Chaque onglet est un point d'ancrage : les verticaux (scolarité M5-M9,
/// révision M10-M12, boutique M13-M14) viendront s'y brancher.
class _CorpsOnglet extends ConsumerWidget {
  const _CorpsOnglet({required this.onglet, required this.profil});

  final OngletCoquille onglet;
  final Profil? profil;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (onglet == OngletCoquille.profil) {
      return _VueProfil(profil: profil);
    }
    if (onglet == OngletCoquille.scolarite) {
      return EcranScolarite(profil: profil);
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(onglet.iconeActive, size: 56),
            const SizedBox(height: 16),
            Text(onglet.libelle, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              _moduleAttendu(onglet),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  static String _moduleAttendu(OngletCoquille onglet) => switch (onglet) {
        OngletCoquille.accueil =>
          'Tableau de bord — livré avec le module M20 (Reporting).',
        OngletCoquille.scolarite =>
          'Scolarité, notes et vie scolaire — modules M5 à M9.',
        OngletCoquille.revision =>
          'Quiz, profil de maîtrise et préparation aux examens — modules M10 à M12.',
        OngletCoquille.boutique =>
          'Marketplace AssoShop et paiements — modules M13 et M14.',
        OngletCoquille.profil => '',
      };
}

/// Vue Profil — état civil, rôle, identité fédérée et déconnexion.
class _VueProfil extends ConsumerWidget {
  const _VueProfil({required this.profil});

  final Profil? profil;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = profil;
    if (p == null) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(p.nomAffiche),
          subtitle: Text(p.identifiantCanonique),
        ),
        ListTile(
          leading: const Icon(Icons.badge_outlined),
          title: const Text('Rôle'),
          subtitle: Text(p.roleRacine?.code ?? 'non défini'),
        ),
        ListTile(
          leading: const Icon(Icons.hub_outlined),
          title: const Text('Identité GSG ID'),
          subtitle: Text(p.gsgId ?? 'non fédérée'),
        ),
        ListTile(
          leading: const Icon(Icons.public_outlined),
          title: const Text('Référentiel pédagogique CEDEAO'),
          subtitle: const Text('Consultable hors connexion'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const EcranPaysPedagogiques()),
          ),
        ),
        if (p.roleRacine == RoleRacine.enseignant || p.roleRacine == RoleRacine.direction)
          ListTile(
            leading: const Icon(Icons.apartment_outlined),
            title: const Text('Structures & annuaire'),
            subtitle: const Text('Campus, années, périodes, classes'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EcranStructureEtablissement()),
            ),
          ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Se déconnecter'),
          onTap: () async {
            await ref.read(authRepositoryProvider).deconnecter();
            if (context.mounted) ref.rafraichirSession();
          },
        ),
      ],
    );
  }
}
