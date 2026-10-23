import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/role_racine.dart';
import '../../../core/config/env.dart';
import '../../../core/providers.dart';
import '../../../core/widgets/page_header.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/application/telephone_profil_providers.dart';
import '../../auth/domain/profil.dart';
import '../../auth/presentation/ecran_telephone_profil.dart';
import '../../auth/presentation/ecran_telephones_a_confirmer.dart';
import '../../liaisons_comptes/presentation/ecran_liaisons_comptes.dart';
import '../../cgu/presentation/ecran_cgu.dart';
import '../../communication/presentation/ecran_notifications.dart';
import '../../push/presentation/ecouteur_push.dart';
import '../../validation_marketplace/presentation/ecran_agrement_vendeurs_etablissement.dart';
import '../../validation_marketplace/presentation/ecran_validation_vendeurs_gsg.dart';
import '../../communication/presentation/ecran_preferences_canaux.dart';
import '../../communication/presentation/ecran_tableau_bord_communication.dart';
import '../../communication/prototype/presentation/ecran_annonces_prototype.dart';
import '../../communication/prototype/presentation/ecran_cahier_liaison_prototype.dart';
import '../../chat_ia/domain/persona_ia.dart';
import '../../chat_ia/presentation/ecran_chat_ia.dart';
import '../../comptabilite/presentation/ecran_comptabilite.dart';
import '../../inscription_en_ligne/presentation/ecran_campagne_inscription.dart';
import '../../inscription_en_ligne/presentation/ecran_inscriptions_famille.dart';
import '../../pointage/presentation/ecran_credits_sms_gsg.dart';
import '../../pointage/presentation/ecran_portail.dart';
import '../../pointage/presentation/ecran_presence_jour.dart';
import '../../pointage/presentation/ecran_relances_impayes.dart';
import '../../pointage/presentation/interrupteur_avis_portail.dart';
import '../../marketplace/presentation/ecran_marketplace.dart';
import '../../parent_ia/presentation/ecran_parent_ia_activation.dart';
import '../../parent_ia/presentation/ecran_parent_ia_historique.dart';
import '../../planification/presentation/ecran_agenda_evenements.dart';
import '../../planification/presentation/ecran_choix_classe.dart';
import '../../planification/presentation/ecran_conflits_emploi.dart';
import '../../planification/presentation/ecran_emploi_du_temps.dart';
import '../../planification/presentation/ecran_planification_classe.dart';
import '../../planification/presentation/ecran_salles.dart';
import '../../rapports/presentation/ecran_rapports.dart';
import '../../rapports/presentation/ecran_tableau_bord_rapports.dart';
import '../../referentiel/presentation/ecran_pays_pedagogiques.dart';
import '../../scan_exercice/presentation/ecran_scan_exercice.dart';
import '../../rh_personnel/application/rh_providers.dart';
import '../../rh_personnel/presentation/ecran_annuaire_personnel.dart';
import '../../rh_personnel/presentation/ecran_fiche_employe.dart';
import '../../rh_personnel/presentation/ecran_tableau_bord_rh.dart';
import '../../scolarite/application/scolarite_providers.dart';
import '../../scolarite/presentation/ecran_cahier_encaissements.dart';
import '../../paiement_mobile/presentation/ecran_orange_money_etablissement.dart';
import '../../themes/presentation/ecran_identite_visuelle.dart';
import '../../creation_etablissement/presentation/ecran_demande_etablissement.dart';
import '../../creation_etablissement/presentation/ecran_validation_etablissements_gsg.dart';
import '../../themes/application/theme_providers.dart';
import '../../scolarite/presentation/ecran_creation_inscription.dart';
import '../../scolarite/presentation/ecran_parametres_financiers.dart';
import '../../scolarite/presentation/ecran_reinscription.dart';
import '../../scolarite/presentation/ecran_scolarite.dart';
import '../../scolarite/presentation/ecran_structure_etablissement.dart';
import '../../bibliotheque/presentation/ecran_bibliotheque.dart';
import '../../bibliotheque/presentation/ecran_bibliotheque_famille.dart';
import '../../reseau/presentation/ecran_mes_reseaux.dart';
import '../../reseau/presentation/ecran_reseaux_gsg.dart';
import '../../scolarite/presentation/widgets/selecteur_enfant.dart';
import '../../transport/application/transport_providers.dart';
import '../../transport/presentation/ecran_suivi_transport.dart';
import '../../transport/presentation/ecran_transport_chauffeur.dart';
import '../../transport/presentation/ecran_transport_direction.dart';
import '../../themes/presentation/ecran_preferences_apparence.dart';
import '../../vie_scolaire/presentation/ecran_alertes_decrochage.dart';
import '../application/session_logout.dart';
import '../application/sync_composition.dart';

/// Onglet de la coquille applicative.
///
/// La composition dépend du rôle racine : la barre de navigation n'affiche que
/// ce que le rôle couvre. Ce filtrage est **ergonomique**, pas sécuritaire —
/// atteindre un onglet ne donne accès à aucune donnée que RLS refuse.
enum OngletCoquille {
  accueil(
    'Accueil',
    Icons.home_outlined,
    Icons.home,
    'Tableau de bord et indicateurs clés de votre établissement',
  ),
  scolarite(
    'Scolarité',
    Icons.school_outlined,
    Icons.school,
    'Inscriptions, notes, absences et suivi de la vie scolaire',
  ),
  revision(
    'Révision',
    Icons.psychology_outlined,
    Icons.psychology,
    'Quiz, profil de maîtrise et préparation aux examens',
  ),
  boutique(
    'Boutique',
    Icons.storefront_outlined,
    Icons.storefront,
    "Marketplace AssoShop et paiements de l'établissement",
  ),
  profil(
    'Profil',
    Icons.person_outline,
    Icons.person,
    'Votre compte, vos préférences et vos outils IA',
  );

  const OngletCoquille(this.libelle, this.icone, this.iconeActive, this.descriptif);

  final String libelle;
  final IconData icone;
  final IconData iconeActive;

  /// Descriptif court affiché par `PageHeader` (D1) — appliqué uniquement
  /// aux 5 onglets racine pour cette passe.
  final String descriptif;

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

    final profil = ref.watch(profilProvider).valueOrNull;
    final onglets = OngletCoquille.pourRole(profil?.roleRacine);
    // Un changement de rôle ou de rattachement peut raccourcir la liste :
    // on borne l'index plutôt que de laisser une RangeError se produire.
    final index = _index < onglets.length ? _index : 0;
    final large = MediaQuery.sizeOf(context).width >= 720;

    final corps = _CorpsOnglet(onglet: onglets[index], profil: profil);

    return Scaffold(
      appBar: AppBar(
        // TopBar enrichi (D1) : le titre dynamique de l'onglet vit
        // désormais dans `PageHeader` (voir `_CorpsOnglet`), pour ne pas le
        // répéter à l'identique deux fois à l'écran — l'AppBar porte
        // uniquement l'identité de l'app + les raccourcis globaux.
        title: const Text('EcoShop'),
        actions: [
          const _IndicateurEtablissement(),
          if (profil != null)
            IconButton(
              tooltip: 'Notifications',
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EcranNotifications(profileId: profil.id),
                ),
              ),
            ),
          if (profil != null)
            _RaccourciAvatar(
              profil: profil,
              onOuvrirProfil: () {
                final i = onglets.indexOf(OngletCoquille.profil);
                if (i >= 0) setState(() => _index = i);
              },
            ),
        ],
      ),
      body: Column(
        children: [
          const _BandeauHorsLigne(),
          // Notifications push : rattachement du téléphone, bandeau, ouverture.
          if (Env.estConfigure && profil != null) EcouteurPush(key: ValueKey(profil.id), profilId: profil.id),
          const SelecteurEnfant(),
          Expanded(
            child: large
                ? Row(
                    children: [
                      NavigationRail(
                        selectedIndex: index,
                        onDestinationSelected: (i) =>
                            setState(() => _index = i),
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
    // Logo de l'établissement (REG-07 B), à côté de son nom.
    final logoUrl = ref.watch(identiteEtablissementProvider).logoUrl;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (logoUrl != null) ...[
              CircleAvatar(
                radius: 14,
                backgroundColor: Colors.transparent,
                backgroundImage: NetworkImage(logoUrl),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              etablissement.nom,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
        ),
      ),
    );
  }
}

/// Raccourci avatar (TopBar enrichi, D1) : ouvre directement « Mon profil ».
/// La déconnexion se trouve seulement en bas de cette liste : pas de
/// déconnexion d'un geste depuis la barre du haut. Pas de photo de profil
/// dans `Profil` : avatar à initiales, dérivé de `nomAffiche` (déjà robuste
/// au repli sur l'identifiant canonique si aucun nom n'est renseigné).
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
      icon: CircleAvatar(
        radius: 16,
        child: Text(
          _initiales(profil.nomAffiche),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  static String _initiales(String nomAffiche) {
    final mots = nomAffiche.trim().split(RegExp(r'\s+')).where((m) => m.isNotEmpty).toList();
    if (mots.isEmpty) return '?';
    if (mots.length == 1) return mots.first.substring(0, 1).toUpperCase();
    return (mots.first.substring(0, 1) + mots[1].substring(0, 1)).toUpperCase();
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
    // PageHeader (D1) : titre + descriptif, appliqué aux 5 onglets racine —
    // SAUF quand le contenu délégué possède déjà son propre AppBar
    // (`_delegueSonAppBar`), pour ne jamais superposer deux barres de titre.
    if (_delegueSonAppBar) return _contenu(context);
    return Column(
      children: [
        PageHeader(titre: onglet.libelle, descriptif: onglet.descriptif),
        Expanded(child: _contenu(context)),
      ],
    );
  }

  /// `true` si l'écran rendu par [_contenu] pour ce couple onglet/rôle a déjà
  /// son propre `Scaffold`+`AppBar` — l'empilement visuel avec `PageHeader`
  /// serait sinon un défaut visible dès l'ouverture de l'onglet :
  /// - Boutique → `EcranMarketplace` (AppBar « Marketplace »), pour tous les
  ///   rôles qui y accèdent.
  /// - Scolarité → `EcranFicheEleve` (AppBar = nom de la fiche) pour parent
  ///   et élève, `EcranStructureEtablissement` (AppBar « Structures &
  ///   annuaire ») pour la direction. Ne s'applique PAS à l'enseignant :
  ///   `_VueEnseignant` n'a aucun AppBar propre et dépend de `PageHeader`
  ///   pour son titre.
  bool get _delegueSonAppBar => switch (onglet) {
    OngletCoquille.boutique => true,
    OngletCoquille.scolarite => switch (profil?.roleRacine) {
      RoleRacine.direction || RoleRacine.parent || RoleRacine.eleve => true,
      _ => false,
    },
    _ => false,
  };

  Widget _contenu(BuildContext context) {
    if (onglet == OngletCoquille.profil) {
      return _VueProfil(profil: profil);
    }
    if (onglet == OngletCoquille.scolarite) {
      return EcranScolarite(profil: profil);
    }
    if (onglet == OngletCoquille.boutique) {
      return EcranMarketplace(profil: profil);
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(onglet.iconeActive, size: 56),
            const SizedBox(height: 16),
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
        // Identifiant EcoShop (REG-18) : utile au guichet de l'école et pour
        // se connecter sans retaper son adresse. Pas un secret.
        if (p.identifiantEcoshop != null)
          ListTile(
            key: const Key('profil_identifiant_ecoshop'),
            leading: const Icon(Icons.qr_code_2_outlined),
            title: Text(p.identifiantEcoshop!),
            subtitle: const Text('Mon identifiant EcoShop'),
            trailing: IconButton(
              tooltip: 'Copier',
              icon: const Icon(Icons.copy_outlined),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: p.identifiantEcoshop!));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Identifiant copié')),
                  );
                }
              },
            ),
          ),
        // Téléphone (REG-16) : déclaré par la personne, confirmé à l'école.
        Consumer(
          builder: (context, ref, _) {
            final tel = ref.watch(telephoneProfilProvider).valueOrNull;
            return ListTile(
              key: const Key('profil_telephone'),
              leading: Icon(tel?.verifie == true ? Icons.verified_outlined : Icons.phone_outlined),
              title: Text(tel == null ? 'Ajouter mon numéro de téléphone' : tel.lisible),
              subtitle: Text(tel == null ? 'Pour que l’école puisse vous joindre' : tel.statut),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EcranTelephoneProfil(modification: true, actuel: tel),
                ),
              ),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.badge_outlined),
          title: const Text('Rôle'),
          subtitle: Text(p.roleRacine?.code ?? 'non défini'),
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
        ListTile(
          leading: const Icon(Icons.dark_mode_outlined),
          title: const Text('Apparence'),
          subtitle: const Text('Clair, sombre, système'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const EcranPreferencesApparence(),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.gavel_outlined),
          title: const Text('Conditions générales d\'utilisation'),
          subtitle: const Text('Accessibles à tout moment (§34.10)'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const EcranCgu()),
          ),
        ),
        if (PersonaIa.depuisRoleRacine(p.roleRacine) != null)
          Consumer(
            builder: (context, ref, _) {
              final etablissement = ref.watch(etablissementActifProvider);
              final persona = PersonaIa.depuisRoleRacine(p.roleRacine)!;
              if (etablissement == null) return const SizedBox.shrink();
              return ListTile(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: Text(persona.libelle),
                subtitle: const Text(
                  'Assistant IA — signal, pas une décision automatisée',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EcranChatIa(
                      etablissementId: etablissement.id,
                      persona: persona,
                    ),
                  ),
                ),
              );
            },
          ),
        if (p.roleRacine == RoleRacine.eleve)
          Consumer(
            builder: (context, ref, _) {
              final fiche = ref.watch(maFicheProvider).value;
              final etablissement = ref.watch(etablissementActifProvider);
              return ListTile(
                leading: const Icon(Icons.document_scanner_outlined),
                title: const Text('Scan-Exercice'),
                subtitle: const Text('Photographiez un exercice, résolvez-le pas à pas'),
                trailing: const Icon(Icons.chevron_right),
                onTap: fiche == null || etablissement == null
                    ? () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Lie d\'abord ton compte à ta fiche élève.'),
                        ),
                      )
                    : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => EcranScanExercice(
                            etablissementId: etablissement.id,
                            ficheEleveId: fiche.id,
                          ),
                        ),
                      ),
              );
            },
          ),
        if (p.roleRacine == RoleRacine.eleve)
          Consumer(
            builder: (context, ref, _) {
              final fiche = ref.watch(maFicheProvider).value;
              return ListTile(
                leading: const Icon(Icons.phonelink_lock_outlined),
                title: const Text('PARENT IA'),
                subtitle: const Text(
                  'Autolimitation numérique — activable par toi seul(e)',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: fiche == null
                    ? () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Lie d\'abord ton compte à ta fiche élève.',
                          ),
                        ),
                      )
                    : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              EcranParentIaActivation(ficheEleveId: fiche.id),
                        ),
                      ),
              );
            },
          ),
        if (p.roleRacine == RoleRacine.parent)
          Consumer(
            builder: (context, ref, _) {
              final enfant = ref.watch(enfantActifProvider);
              return ListTile(
                leading: const Icon(Icons.phonelink_lock_outlined),
                title: const Text('PARENT IA'),
                subtitle: const Text(
                  'Historique des restrictions — lecture seule',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: enfant == null
                    ? () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Lie d\'abord un enfant à ton compte.'),
                        ),
                      )
                    : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => EcranParentIaHistorique(
                            ficheEleveId: enfant.id,
                            nomEleve: enfant.nomComplet,
                          ),
                        ),
                      ),
              );
            },
          ),
        // Inscriptions et réinscriptions en ligne (REG-08) : parents, et
        // élèves (qui se réinscrivent eux-mêmes dès le collège).
        if (p.roleRacine == RoleRacine.parent || p.roleRacine == RoleRacine.eleve)
          ListTile(
            key: const Key('menu_inscriptions_famille'),
            leading: const Icon(Icons.how_to_reg_outlined),
            title: const Text('Inscriptions et réinscriptions'),
            subtitle: const Text('Réinscrire, inscrire un nouvel élève, suivre ses dossiers'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EcranInscriptionsFamille()),
            ),
          ),
        // Avis du portail (REG-09) : le parent ou l'élève choisit.
        if (p.roleRacine == RoleRacine.parent || p.roleRacine == RoleRacine.eleve)
          const InterrupteurAvisPortail(),
        // Présence au portail (REG-09) : Direction (tableau, réglages,
        // cartes, crédits SMS) ; le portail lui-même aussi pour le
        // personnel habilité (le serveur vérifie le droit).
        if (p.roleRacine == RoleRacine.direction || p.roleRacine == RoleRacine.enseignant)
          Consumer(
            builder: (context, ref, _) {
              final etablissement = ref.watch(etablissementActifProvider);
              if (etablissement == null) return const SizedBox.shrink();
              return Column(
                children: [
                  if (p.roleRacine == RoleRacine.direction)
                    ListTile(
                      key: const Key('menu_presence_jour'),
                      leading: const Icon(Icons.fact_check_outlined),
                      title: const Text('Présence au portail'),
                      subtitle: const Text('Arrivées, absents, retards, alertes aux familles, cartes'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => EcranPresenceJour(etablissement: etablissement)),
                      ),
                    ),
                  ListTile(
                    key: const Key('menu_portail'),
                    leading: const Icon(Icons.qr_code_scanner),
                    title: const Text('Portail : scanner les cartes'),
                    subtitle: const Text('Téléphone ou douchette à l\'entrée — fonctionne sans réseau'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => EcranPortail(etablissementId: etablissement.id)),
                    ),
                  ),
                  if (p.roleRacine == RoleRacine.direction)
                    ListTile(
                      leading: const Icon(Icons.campaign_outlined),
                      title: const Text('Relancer les impayés'),
                      subtitle: const Text('Familles en retard sur les tranches échues (push, SMS)'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => EcranRelancesImpayes(
                            etablissementId: etablissement.id,
                            devise: etablissement.deviseCode,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        // Bibliothèque physique (M17, cahier ch. 25) : gestion par la
        // direction ; catalogue et emprunts pour l'élève et ses parents
        // (gratuit, jamais premium — 25.1).
        if (p.roleRacine == RoleRacine.direction)
          Consumer(
            builder: (context, ref, _) {
              final etablissement = ref.watch(etablissementActifProvider);
              if (etablissement == null) return const SizedBox.shrink();
              return ListTile(
                key: const Key('menu_bibliotheque'),
                leading: const Icon(Icons.local_library_outlined),
                title: const Text('Bibliothèque'),
                subtitle: const Text('Prêts et retours (sans réseau), catalogue, étiquettes, retards, inventaire'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => EcranBibliotheque(etablissement: etablissement)),
                ),
              );
            },
          ),
        if (p.roleRacine == RoleRacine.parent || p.roleRacine == RoleRacine.eleve)
          Consumer(
            builder: (context, ref, _) {
              final fiche = p.roleRacine == RoleRacine.parent
                  ? ref.watch(enfantActifProvider)
                  : ref.watch(maFicheProvider).valueOrNull;
              if (fiche == null) return const SizedBox.shrink();
              return ListTile(
                key: const Key('menu_bibliotheque_famille'),
                leading: const Icon(Icons.local_library_outlined),
                title: const Text('Bibliothèque'),
                subtitle: Text(p.roleRacine == RoleRacine.parent
                    ? 'Livres empruntés par ${fiche.prenom}, catalogue, réservation'
                    : 'Mes emprunts, catalogue, réservation'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EcranBibliothequeFamille(
                      etablissementId: fiche.etablissementId,
                      ficheEleveId: fiche.id,
                      prenom: fiche.prenom,
                    ),
                  ),
                ),
              );
            },
          ),
        // Numéros à confirmer (REG-16) : en présence de la personne, sans SMS.
        if (p.roleRacine == RoleRacine.direction)
          Consumer(
            builder: (context, ref, _) {
              final etablissement = ref.watch(etablissementActifProvider);
              if (etablissement == null) return const SizedBox.shrink();
              return ListTile(
                key: const Key('menu_telephones_a_confirmer'),
                leading: const Icon(Icons.verified_user_outlined),
                title: const Text('Numéros à confirmer'),
                subtitle: const Text('Parents et personnel, à leur passage'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EcranTelephonesAConfirmer(etablissementId: etablissement.id),
                  ),
                ),
              );
            },
          ),
        // Comptes liés aux élèves (REG-18) : prévenue de chaque liaison, la
        // direction accepte, refuse ou révoque.
        if (p.roleRacine == RoleRacine.direction)
          Consumer(
            builder: (context, ref, _) {
              final etablissement = ref.watch(etablissementActifProvider);
              if (etablissement == null) return const SizedBox.shrink();
              return ListTile(
                key: const Key('menu_liaisons_comptes'),
                leading: const Icon(Icons.link_outlined),
                title: const Text('Comptes liés aux élèves'),
                subtitle: const Text('Demandes en attente, liaisons récentes'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EcranLiaisonsComptes(etablissementId: etablissement.id),
                  ),
                ),
              );
            },
          ),
        // Transport scolaire (M18, cahier ch. 24) : gestion par la direction,
        // suivi du bus par la famille (enfant actif), trajets du chauffeur.
        if (p.roleRacine == RoleRacine.direction)
          Consumer(
            builder: (context, ref, _) {
              final etablissement = ref.watch(etablissementActifProvider);
              if (etablissement == null) return const SizedBox.shrink();
              return ListTile(
                key: const Key('menu_transport_direction'),
                leading: const Icon(Icons.directions_bus_outlined),
                title: const Text('Transport scolaire'),
                subtitle: const Text('Circuits, arrêts, élèves, chauffeurs, paiements'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EcranTransportDirection(
                      etablissementId: etablissement.id,
                      devise: etablissement.deviseCode,
                    ),
                  ),
                ),
              );
            },
          ),
        if (p.roleRacine == RoleRacine.parent)
          Consumer(
            builder: (context, ref, _) {
              final enfant = ref.watch(enfantActifProvider);
              if (enfant == null) return const SizedBox.shrink();
              return ListTile(
                key: const Key('menu_suivi_transport'),
                leading: const Icon(Icons.directions_bus_outlined),
                title: Text('Bus de ${enfant.prenom}'),
                subtitle: const Text('Où est le bus, montée et descente'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EcranSuiviTransport(ficheEleveId: enfant.id, prenom: enfant.prenom),
                  ),
                ),
              );
            },
          ),
        if (p.roleRacine != RoleRacine.eleve && p.roleRacine != RoleRacine.adminGsg)
          Consumer(
            builder: (context, ref, _) {
              final circuits = ref.watch(mesCircuitsChauffeurProvider).valueOrNull ?? const [];
              if (circuits.isEmpty) return const SizedBox.shrink();
              return ListTile(
                key: const Key('menu_chauffeur'),
                leading: const Icon(Icons.airport_shuttle_outlined),
                title: const Text('Conduire mon circuit'),
                subtitle: const Text('Démarrer un trajet, scanner les élèves — fonctionne sans réseau'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EcranTransportChauffeur()),
                ),
              );
            },
          ),
        // Réseaux d'établissements (M19, cahier ch. 28) : Direction Générale
        // d'un réseau, direction d'une école invitée ou membre, ou fondateur
        // qui souhaite créer le réseau de son organisation.
        if (p.roleRacine != RoleRacine.eleve && p.roleRacine != RoleRacine.adminGsg)
          ListTile(
            key: const Key('menu_reseaux'),
            leading: const Icon(Icons.hub_outlined),
            title: const Text("Réseau d'établissements"),
            subtitle: const Text('Piloter un réseau, invitations, circulaires, calendrier commun'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EcranMesReseaux()),
            ),
          ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: const Text('Notifications'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EcranNotifications(profileId: p.id),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.tune_outlined),
          title: const Text('Préférences de notification'),
          subtitle: const Text('Canaux, horaires, fréquence'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EcranPreferencesCanaux(profileId: p.id),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.campaign_outlined),
          title: const Text('Annonces'),
          subtitle: const Text('Prototype local — non synchronisé'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EcranAnnonces(
                profileId: p.id,
                profileNom: p.nomAffiche,
                peutPublier: p.roleRacine == RoleRacine.direction,
              ),
            ),
          ),
        ),
        if (p.roleRacine == RoleRacine.parent ||
            p.roleRacine == RoleRacine.enseignant)
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('Cahier de liaison'),
            subtitle: const Text('Prototype local — non synchronisé'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EcranCahierLiaison(
                  profileId: p.id,
                  profileNom: p.nomAffiche,
                ),
              ),
            ),
          ),
        if (p.roleRacine == RoleRacine.direction)
          Consumer(
            builder: (context, ref, _) {
              final etablissement = ref.watch(etablissementActifProvider);
              if (etablissement == null) return const SizedBox.shrink();
              return ListTile(
                leading: const Icon(Icons.insights_outlined),
                title: const Text('Tableau de bord communication'),
                subtitle: const Text('Taux de lecture, modèles de messages'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EcranTableauBordCommunication(
                      etablissementId: etablissement.id,
                    ),
                  ),
                ),
              );
            },
          ),
        if (p.roleRacine == RoleRacine.enseignant ||
            p.roleRacine == RoleRacine.direction)
          Consumer(
            builder: (context, ref, _) {
              final etablissement = ref.watch(etablissementActifProvider);
              if (etablissement == null) return const SizedBox.shrink();
              return ListTile(
                leading: const Icon(Icons.query_stats_outlined),
                title: const Text('Rapports & statistiques'),
                subtitle: const Text('Indicateurs, anomalies, recommandations'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EcranTableauBordRapports(
                      etablissementId: etablissement.id,
                    ),
                  ),
                ),
              );
            },
          ),
        if (p.roleRacine == RoleRacine.enseignant)
          Consumer(
            builder: (context, ref, _) {
              final etablissement = ref.watch(etablissementActifProvider);
              final structure = ref
                  .watch(structureEtablissementProvider(null))
                  .value;
              final anneeId = structure?.anneeCourante?.id;
              if (etablissement == null || anneeId == null) {
                return const SizedBox.shrink();
              }
              return ListTile(
                leading: const Icon(Icons.calendar_view_week_outlined),
                title: const Text('Mon emploi du temps'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EcranEmploiEnseignant(
                      enseignantProfileId: p.id,
                      etablissementId: etablissement.id,
                      anneeId: anneeId,
                    ),
                  ),
                ),
              );
            },
          ),
        if (p.roleRacine == RoleRacine.enseignant ||
            p.roleRacine == RoleRacine.direction)
          Consumer(
            builder: (context, ref, _) {
              final etablissement = ref.watch(etablissementActifProvider);
              final structure = ref
                  .watch(structureEtablissementProvider(null))
                  .value;
              final anneeId = structure?.anneeCourante?.id;
              if (etablissement == null || anneeId == null) {
                return const SizedBox.shrink();
              }
              return ListTile(
                leading: const Icon(Icons.class_outlined),
                title: const Text('Classes — emploi du temps & progression'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EcranChoixClasse(
                      titre: 'Choisir une classe',
                      onSelectionner: (context, classe) =>
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => EcranPlanificationClasse(
                                classeId: classe.id,
                                anneeId: anneeId,
                                titre: classe.nom,
                                etablissementId: etablissement.id,
                                peutVoirProgression: true,
                              ),
                            ),
                          ),
                    ),
                  ),
                ),
              );
            },
          ),
        if (p.roleRacine == RoleRacine.enseignant ||
            p.roleRacine == RoleRacine.direction)
          Consumer(
            builder: (context, ref, _) {
              final etablissement = ref.watch(etablissementActifProvider);
              final structure = ref
                  .watch(structureEtablissementProvider(null))
                  .value;
              final anneeId = structure?.anneeCourante?.id;
              if (etablissement == null || anneeId == null) {
                return const SizedBox.shrink();
              }
              return Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.meeting_room_outlined),
                    title: const Text('Salles'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EcranSalles(
                          etablissementId: etablissement.id,
                          anneeId: anneeId,
                        ),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.event_outlined),
                    title: const Text('Agenda de l\'établissement'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EcranAgendaEvenements(
                          etablissementId: etablissement.id,
                          anneeId: anneeId,
                          peutCreer: p.roleRacine == RoleRacine.direction,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        if (p.roleRacine == RoleRacine.direction)
          Consumer(
            builder: (context, ref, _) {
              final etablissement = ref.watch(etablissementActifProvider);
              final structure = ref
                  .watch(structureEtablissementProvider(null))
                  .value;
              final anneeId = structure?.anneeCourante?.id;
              if (etablissement == null || anneeId == null) {
                return const SizedBox.shrink();
              }
              return ListTile(
                leading: const Icon(Icons.rule_outlined),
                title: const Text('Conflits d\'occupation'),
                subtitle: const Text('Signal IA — à arbitrer'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EcranConflitsEmploi(
                      etablissementId: etablissement.id,
                      anneeId: anneeId,
                    ),
                  ),
                ),
              );
            },
          ),
        if (p.roleRacine == RoleRacine.parent)
          Consumer(
            builder: (context, ref, _) {
              final enfant = ref.watch(enfantActifProvider);
              return ListTile(
                leading: const Icon(Icons.calendar_view_week_outlined),
                title: const Text('Emploi du temps de mon enfant'),
                trailing: const Icon(Icons.chevron_right),
                onTap: enfant == null
                    ? null
                    : () async {
                        final inscriptions = await ref.read(
                          inscriptionsDeFicheProvider(enfant.id).future,
                        );
                        if (inscriptions.isEmpty || !context.mounted) return;
                        final inscription = inscriptions.first;
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => EcranPlanificationClasse(
                              classeId: inscription.classeId,
                              anneeId: inscription.anneeScolaireId,
                              titre: enfant.nomComplet,
                            ),
                          ),
                        );
                      },
              );
            },
          ),
        if (p.roleRacine == RoleRacine.eleve)
          Consumer(
            builder: (context, ref, _) {
              final fiche = ref.watch(maFicheProvider).value;
              return ListTile(
                leading: const Icon(Icons.calendar_view_week_outlined),
                title: const Text('Mon emploi du temps'),
                trailing: const Icon(Icons.chevron_right),
                onTap: fiche == null
                    ? null
                    : () async {
                        final inscriptions = await ref.read(
                          inscriptionsDeFicheProvider(fiche.id).future,
                        );
                        if (inscriptions.isEmpty || !context.mounted) return;
                        final inscription = inscriptions.first;
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => EcranPlanificationClasse(
                              classeId: inscription.classeId,
                              anneeId: inscription.anneeScolaireId,
                              titre: fiche.nomComplet,
                            ),
                          ),
                        );
                      },
              );
            },
          ),
        if (p.roleRacine == RoleRacine.parent)
          Consumer(
            builder: (context, ref, _) {
              final enfant = ref.watch(enfantActifProvider);
              return ListTile(
                leading: const Icon(Icons.summarize_outlined),
                title: const Text('Rapports de mon enfant'),
                subtitle: const Text('Bulletins, relevés de notes'),
                trailing: const Icon(Icons.chevron_right),
                onTap: enfant == null
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              EcranMesRapports(ficheEleveId: enfant.id),
                        ),
                      ),
              );
            },
          ),
        if (p.roleRacine == RoleRacine.eleve)
          Consumer(
            builder: (context, ref, _) {
              final fiche = ref.watch(maFicheProvider).value;
              return ListTile(
                leading: const Icon(Icons.summarize_outlined),
                title: const Text('Mes rapports'),
                subtitle: const Text('Bulletins, relevés de notes'),
                trailing: const Icon(Icons.chevron_right),
                onTap: fiche == null
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              EcranMesRapports(ficheEleveId: fiche.id),
                        ),
                      ),
              );
            },
          ),
        if (p.roleRacine == RoleRacine.enseignant ||
            p.roleRacine == RoleRacine.direction)
          ListTile(
            leading: const Icon(Icons.apartment_outlined),
            title: const Text('Structures & annuaire'),
            subtitle: const Text('Campus, années, périodes, classes'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const EcranStructureEtablissement(),
              ),
            ),
          ),
        if (p.roleRacine == RoleRacine.direction)
          Consumer(
            builder: (context, ref, _) {
              final etablissement = ref.watch(etablissementActifProvider);
              if (etablissement == null) return const SizedBox.shrink();
              return ListTile(
                leading: const Icon(Icons.warning_amber_outlined),
                title: const Text('Alertes de décrochage'),
                subtitle: const Text('Signal IA — validation humaine'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EcranAlertesDecrochage(
                      etablissementId: etablissement.id,
                    ),
                  ),
                ),
              );
            },
          ),
        if (p.roleRacine == RoleRacine.direction)
          Consumer(
            builder: (context, ref, _) {
              final etablissement = ref.watch(etablissementActifProvider);
              if (etablissement == null) return const SizedBox.shrink();
              return Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: const Text('Personnel & RH'),
                    subtitle: const Text(
                      'Annuaire, contrats, congés, absences',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EcranAnnuairePersonnel(
                          etablissementId: etablissement.id,
                        ),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.insights_outlined),
                    title: const Text('Tableau de bord RH'),
                    subtitle: const Text(
                      'Effectifs et remplacements — signal IA',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EcranTableauBordRh(
                          etablissementId: etablissement.id,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        if (p.roleRacine == RoleRacine.enseignant ||
            p.roleRacine == RoleRacine.direction)
          Consumer(
            builder: (context, ref, _) {
              return ListTile(
                leading: const Icon(Icons.folder_shared_outlined),
                title: const Text('Mon dossier RH'),
                subtitle: const Text('Contrat, congés, absences, paie'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final employe = await ref.read(
                    monEmployeProvider(p.id).future,
                  );
                  if (!context.mounted) return;
                  if (employe == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Aucun dossier RH associé à ce compte.'),
                      ),
                    );
                    return;
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => EcranFicheEmploye(employe: employe),
                    ),
                  );
                },
              );
            },
          ),
        if (p.roleRacine == RoleRacine.direction)
          Consumer(
            builder: (context, ref, _) {
              final etablissement = ref.watch(etablissementActifProvider);
              if (etablissement == null) return const SizedBox.shrink();
              return ListTile(
                leading: const Icon(Icons.calculate_outlined),
                title: const Text('Comptabilité'),
                subtitle: const Text(
                  'Journal, grand livre, balance — supervision IA',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        EcranComptabilite(etablissementId: etablissement.id, devise: etablissement.deviseCode),
                  ),
                ),
              );
            },
          ),
        if (p.roleRacine == RoleRacine.direction)
          Consumer(
            builder: (context, ref, _) {
              final etablissement = ref.watch(etablissementActifProvider);
              if (etablissement == null) return const SizedBox.shrink();
              return ListTile(
                key: const Key('menu_campagne_inscription'),
                leading: const Icon(Icons.how_to_reg_outlined),
                title: const Text('Inscriptions en ligne'),
                subtitle: const Text('Campagne, dossiers des familles, places, liste d\'attente'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EcranCampagneInscription(
                      etablissementId: etablissement.id,
                      devise: etablissement.deviseCode,
                    ),
                  ),
                ),
              );
            },
          ),
        if (p.roleRacine == RoleRacine.direction)
          ListTile(
            leading: const Icon(Icons.person_add_alt_1_outlined),
            title: const Text('Nouvelle inscription'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const EcranCreationInscription(),
              ),
            ),
          ),
        if (p.roleRacine == RoleRacine.direction)
          ListTile(
            leading: const Icon(Icons.autorenew_outlined),
            title: const Text('Réinscription'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EcranReinscription()),
            ),
          ),
        if (p.roleRacine == RoleRacine.direction)
          Consumer(
            builder: (context, ref, _) {
              final etablissement = ref.watch(etablissementActifProvider);
              final structure = ref
                  .watch(structureEtablissementProvider(null))
                  .value;
              final anneeId = structure?.anneeCourante?.id;
              if (etablissement == null || anneeId == null) {
                return const SizedBox.shrink();
              }
              return Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.request_quote_outlined),
                    title: const Text('Paramètres financiers'),
                    subtitle: const Text('Tarifs, paliers de paiement'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EcranParametresFinanciers(
                          etablissementId: etablissement.id,
                          anneeScolaireId: anneeId,
                        ),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: const Text('Cahier des encaissements'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EcranCahierEncaissements(
                          etablissementId: etablissement.id,
                        ),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.add_business_outlined),
                    title: const Text('Ouvrir un nouvel établissement'),
                    subtitle: const Text('Demande validée par Global Service Groupe'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const EcranDemandeEtablissement()),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.palette_outlined),
                    title: const Text('Identité visuelle'),
                    subtitle: const Text("Couleur et logo de l'établissement"),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EcranIdentiteVisuelle(etablissement: etablissement),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.phone_iphone_rounded, color: Color(0xFFFF7900)),
                    title: const Text('Paiement Orange Money'),
                    subtitle: const Text('Activation et suivi des paiements en ligne'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EcranOrangeMoneyEtablissement(
                          etablissementId: etablissement.id,
                          devise: etablissement.deviseCode,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        // Agrément établissement <-> vendeur (cahier §27.2, palier 2) —
        // réservé à la Direction, même garde que les entrées ci-dessus.
        if (p.roleRacine == RoleRacine.direction)
          Consumer(
            builder: (context, ref, _) {
              final etablissement = ref.watch(etablissementActifProvider);
              if (etablissement == null) return const SizedBox.shrink();
              return ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: const Text('Vendeurs marketplace'),
                subtitle: const Text('Agrément des vendeurs déjà validés par GSG'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EcranAgrementVendeursEtablissement(
                      etablissementId: etablissement.id,
                    ),
                  ),
                ),
              );
            },
          ),
        // Validation GSG des comptes Vendeur (cahier §27.2/§30.2, palier 1)
        // — réservée à l'Administrateur GSG, seul rôle qui en a le droit.
        // Validation GSG des demandes de création d'établissement (REG-04,
        // cahier §30.1) — même garde que la validation des vendeurs.
        if (p.roleRacine == RoleRacine.adminGsg)
          ListTile(
            leading: const Icon(Icons.add_business_outlined),
            title: const Text("Demandes d'établissement"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EcranValidationEtablissementsGsg()),
            ),
          ),
        // Réseaux d'établissements (M19, cahier §30.1/§30.3) : demandes de
        // création, vue d'ensemble, retraits d'écoles à autoriser.
        if (p.roleRacine == RoleRacine.adminGsg)
          ListTile(
            key: const Key('menu_reseaux_gsg'),
            leading: const Icon(Icons.hub_outlined),
            title: const Text("Réseaux d'établissements"),
            subtitle: const Text('Demandes de création, réseaux, retraits à autoriser'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EcranReseauxGsg()),
            ),
          ),
        if (p.roleRacine == RoleRacine.adminGsg)
          ListTile(
            leading: const Icon(Icons.sms_outlined),
            title: const Text('Crédits SMS des écoles'),
            subtitle: const Text('Prix des packs, crédit après paiement'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EcranCreditsSmsGsg()),
            ),
          ),
        if (p.roleRacine == RoleRacine.adminGsg)
          ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: const Text('Validation des vendeurs'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EcranValidationVendeursGsg()),
            ),
          ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Se déconnecter'),
          onTap: () => ref.deconnecterEtPurgerDonneesLocales(),
        ),
      ],
    );
  }
}
