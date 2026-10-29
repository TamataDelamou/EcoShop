import '../../accueil/presentation/profil_allege.dart';
import '../../accueil/application/accueil_providers.dart';
import '../../accueil/presentation/ecran_accueil.dart';
import '../../accueil/presentation/ecrans_destinations.dart';
import '../../appareil/presentation/surveillance_appareils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/role_racine.dart';
import '../../../core/config/env.dart';
import '../../../core/providers.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/application/session_locale.dart';
import '../../auth/domain/profil.dart';
import '../../auth/presentation/avatar_profil.dart';
import '../../communication/presentation/ecran_notifications.dart';
import '../../push/presentation/ecouteur_push.dart';
import '../../validation_marketplace/presentation/ecran_validation_vendeurs_gsg.dart';
import '../../annonces/presentation/ecran_annonces.dart';
import '../../marketplace/presentation/ecran_marketplace.dart';
import '../../rapports/presentation/ecran_tableau_bord_rapports.dart';
import '../../referentiel/presentation/ecran_pays_pedagogiques.dart';
import '../../ecoles_gsg/presentation/ecran_ecoles_gsg.dart';
import '../../scolarite/presentation/ecran_scolarite.dart';
import '../../reseau/presentation/ecran_mes_reseaux.dart';
import '../../reseau/presentation/ecran_reseaux_gsg.dart';
import '../../themes/presentation/bouton_apparence.dart';
import '../application/sync_composition.dart';
import 'entete_utilisateur.dart';
import '../../auth/application/espace_providers.dart';

/// Destination de la barre du bas (REG-21).
///
/// Quatre destinations au plus par rôle (Material 3 : 3 à 5, libellés
/// visibles). Le profil n'y figure plus : il s'ouvre par l'avatar, en haut à
/// droite. Ce filtrage est **ergonomique**, pas sécuritaire — atteindre une
/// destination ne donne accès à aucune donnée que RLS refuse.
enum OngletCoquille {
  accueil('Accueil', Icons.home_outlined, Icons.home),
  messages('Messages', Icons.forum_outlined, Icons.forum),
  annonces('Annonces', Icons.campaign_outlined, Icons.campaign),
  agenda('Agenda', Icons.event_outlined, Icons.event),
  paiements('Paiements', Icons.payments_outlined, Icons.payments),
  mesNotes('Mes notes', Icons.grade_outlined, Icons.grade),
  classes('Classes', Icons.class_outlined, Icons.class_),
  tableauDeBord('Tableau de bord', Icons.insights_outlined, Icons.insights),
  boutique('Boutique', Icons.storefront_outlined, Icons.storefront),
  reseau('Réseau', Icons.hub_outlined, Icons.hub),
  ecolesGsg('Écoles', Icons.add_business_outlined, Icons.add_business),
  reseauxGsg('Réseaux', Icons.hub_outlined, Icons.hub),
  vendeursGsg('Vendeurs', Icons.verified_user_outlined, Icons.verified_user),
  referentiel('Référentiel', Icons.public_outlined, Icons.public),
  notifications('Notifications', Icons.notifications_outlined, Icons.notifications);

  const OngletCoquille(this.libelle, this.icone, this.iconeActive);

  final String libelle;
  final IconData icone;
  final IconData iconeActive;

  /// Destinations d'un rôle. Rôles absents de la proposition : les trois
  /// destinations les plus utilisées après Accueil (voir le registre).
  static List<OngletCoquille> pourRole(RoleRacine? role) => switch (role) {
    RoleRacine.parent => const [accueil, messages, agenda, paiements],
    RoleRacine.eleve => const [accueil, annonces, agenda, mesNotes],
    RoleRacine.enseignant => const [accueil, messages, agenda, classes],
    RoleRacine.direction => const [accueil, messages, agenda, tableauDeBord],
    // Ses outils dépendent de son poste : ils sont sur l'accueil.
    RoleRacine.personnel => const [accueil, messages, agenda],
    RoleRacine.vendeur => const [accueil, boutique, messages],
    RoleRacine.fondateurReseau => const [accueil, reseau, messages, agenda],
    RoleRacine.adminGsg => const [accueil, ecolesGsg, reseauxGsg, vendeursGsg],
    RoleRacine.adminContenu => const [accueil, referentiel, notifications],
    null => const [accueil, messages, agenda],
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

    // Espace utilisé (REG-27) : barre du bas et accueil de cet espace.
    final profil = ref.watch(profilAfficheProvider);
    final onglets = OngletCoquille.pourRole(profil?.roleRacine);
    // Un changement de rôle ou de rattachement peut raccourcir la liste :
    // on borne l'index plutôt que de laisser une RangeError se produire.
    final index = _index < onglets.length ? _index : 0;
    final onglet = onglets[index];
    final large = MediaQuery.sizeOf(context).width >= 720;

    // Toujours montés, quelle que soit la destination.
    final veilleurs = <Widget>[
      const _BandeauHorsLigne(),
      // Code du compte (REG-22) : autorisations d'appareils, récupération en cours.
      if (Env.estConfigure && profil != null) SurveillanceAppareils(key: ValueKey('appareils_${profil.id}')),
      // Notifications push : rattachement du téléphone, bandeau, ouverture.
      if (Env.estConfigure && profil != null) EcouteurPush(key: ValueKey(profil.id), profilId: profil.id),
    ];

    // Accueil : barre du haut de l'application. Autres destinations : écran
    // complet avec sa propre barre de titre (convention Material 3).
    final Widget contenu = onglet == OngletCoquille.accueil
        ? Scaffold(
            appBar: AppBar(
              title: const Text('EcoShop'),
              actions: [
                if (profil != null)
                  IconButton(
                    tooltip: 'Notifications',
                    icon: const Icon(Icons.notifications_outlined),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => EcranNotifications(profileId: profil.id)),
                    ),
                  ),
                // Disposition des pastilles (REG-25) : bouton « Personnaliser
                // l'accueil » sous les pastilles et dans Profil > Préférences —
                // 3 icônes au plus ici (REG-28).
                // Convention Google : le profil tout à droite.
                const BoutonApparence(),
                if (profil != null)
                  _RaccourciAvatar(
                    profil: profil,
                    onOuvrirProfil: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => EcranMonProfil(profil: profil)),
                    ),
                  ),
              ],
            ),
            body: Column(
              children: [
                // En-tête : nom, rôle utilisé, établissement actif ; enfants du parent.
                const EnteteUtilisateur(),
                Expanded(child: _CorpsOnglet(onglet: onglet, profil: profil)),
              ],
            ),
          )
        : _CorpsOnglet(onglet: onglet, profil: profil);

    final barre = large
        ? null
        : NavigationBar(
            key: const Key('barre_navigation'),
            selectedIndex: index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              for (final o in onglets)
                NavigationDestination(icon: Icon(o.icone), selectedIcon: Icon(o.iconeActive), label: o.libelle),
            ],
          );

    return Scaffold(
      body: Column(
        children: [
          SafeArea(bottom: false, child: Column(mainAxisSize: MainAxisSize.min, children: veilleurs)),
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
                      Expanded(child: contenu),
                    ],
                  )
                : contenu,
          ),
        ],
      ),
      bottomNavigationBar: barre,
    );
  }
}

/// Mon profil, ouvert par l'avatar (REG-21).
class EcranMonProfil extends StatelessWidget {
  const EcranMonProfil({super.key, required this.profil});

  final Profil profil;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil')),
      body: VueProfilAllegee(profil: profil),
    );
  }
}

/// Bandeau affiché sans connexion : plus de connectivité (mode avion,
/// données coupées) ou serveur qui ne répond pas (Wi-Fi ou réseau mobile
/// sans Internet — le téléphone se croit connecté).
///
/// Les écritures continuent d'être acceptées et journalisées dans la file
/// outbox ; le bandeau signale simplement que la synchronisation est différée
/// (ch. 34-35).
class _BandeauHorsLigne extends ConsumerWidget {
  const _BandeauHorsLigne();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serveurMuet = ref.watch(donneesSessionPerimeesProvider);
    if (ref.watch(estEnLigneProvider) && !serveurMuet) return const SizedBox.shrink();

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
                'Hors connexion — affichage des données enregistrées',
                key: const Key('bandeau_hors_connexion'),
                style: TextStyle(color: schema.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Raccourci avatar (TopBar enrichi, D1) : ouvre directement « Mon profil ».
/// La déconnexion se trouve seulement en bas de cette liste : pas de
/// déconnexion d'un geste depuis la barre du haut. Photo de profil (REG-23),
/// ou initiales dérivées de `nomAffiche` tant qu'il n'y en a pas.
class _RaccourciAvatar extends StatelessWidget {
  const _RaccourciAvatar({required this.profil, required this.onOuvrirProfil});

  final Profil profil;
  final VoidCallback onOuvrirProfil;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('raccourci_profil'),
      tooltip: 'Mon profil',
      onPressed: onOuvrirProfil,
      // Photo de profil (REG-23), initiales à défaut.
      icon: AvatarProfil.duProfil(profil, rayon: 16),
    );
  }
}

/// Contenu d'une destination de la barre du bas.
class _CorpsOnglet extends ConsumerWidget {
  const _CorpsOnglet({required this.onglet, required this.profil});

  final OngletCoquille onglet;
  final Profil? profil;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = profil;
    if (p == null) return const Center(child: CircularProgressIndicator());
    final etablissement = ref.watch(etablissementActifProvider);
    Widget page(String titre, Widget corps) => Scaffold(appBar: AppBar(title: Text(titre)), body: corps);
    return switch (onglet) {
      OngletCoquille.accueil => const EcranAccueil(),
      OngletCoquille.messages => EcranMessages(profil: p, badges: ref.watch(resumeAccueilProvider).valueOrNull ?? const {}),
      OngletCoquille.annonces => const EcranAnnonces(),
      OngletCoquille.agenda => EcranAgenda(profil: p),
      // Parent : la fiche de l'enfant actif (solde, paiements, Orange Money,
      // notes, vie scolaire). Élève : sa fiche, notes et bulletins en tête.
      OngletCoquille.paiements || OngletCoquille.mesNotes => EcranScolarite(profil: p),
      OngletCoquille.classes => page('Mes classes', EcranScolarite(profil: p)),
      OngletCoquille.tableauDeBord => etablissement == null
          ? page('Tableau de bord', const Center(child: Text('Choisissez d’abord un établissement.')))
          : EcranTableauBordRapports(etablissementId: etablissement.id),
      OngletCoquille.boutique => EcranMarketplace(profil: p),
      OngletCoquille.reseau => const EcranMesReseaux(),
      // Écoles confirmées, tableau de bord par école ; demandes en haut (REG-23).
      OngletCoquille.ecolesGsg => const EcranEcolesGsg(),
      OngletCoquille.reseauxGsg => const EcranReseauxGsg(),
      OngletCoquille.vendeursGsg => const EcranValidationVendeursGsg(),
      OngletCoquille.referentiel => const EcranPaysPedagogiques(),
      OngletCoquille.notifications => EcranNotifications(profileId: p.id),
    };
  }
}
