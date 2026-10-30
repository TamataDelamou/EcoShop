import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/role_racine.dart';
import '../../../core/liens_legaux.dart';
import '../../../core/widgets/choisir_date.dart';
import '../../appareil/presentation/ecran_mes_appareils.dart';
import '../../appareil/presentation/ecran_securite.dart';
import '../../auth/application/telephone_profil_providers.dart';
import '../../auth/domain/profil.dart';
import '../../auth/presentation/avatar_profil.dart';
import '../../auth/presentation/ecran_telephone_profil.dart';
import '../../cgu/presentation/ecran_cgu.dart';
import '../../communication/presentation/ecran_preferences_canaux.dart';
import '../../coquille/application/session_logout.dart';
import '../../coquille/application/verrou_controller.dart';
import '../../invitations/application/invitations_providers.dart';
import '../../invitations/presentation/ecran_invitations.dart';
import '../../pointage/presentation/interrupteur_avis_portail.dart';
import '../../scolarite/presentation/widgets/ajouter_enfant_sheet.dart';
import '../../suppression_compte/application/suppression_compte_providers.dart';
import '../../suppression_compte/presentation/ecran_suppression_compte.dart';
import '../../themes/presentation/ecran_preferences_apparence.dart';
import 'pastille.dart';
import 'reglages_affichage_accueil.dart';

/// « Mon profil » allégé (REG-21) : seulement ce qui est personnel. Tout le
/// travail quotidien est sur l'accueil, en pastilles.
class VueProfilAllegee extends ConsumerWidget {
  const VueProfilAllegee({super.key, required this.profil});

  final Profil profil;

  static String initiales(String nom) {
    final mots = nom.trim().split(RegExp(r'\s+')).where((m) => m.isNotEmpty).toList();
    if (mots.isEmpty) return '?';
    if (mots.length == 1) return mots.first.substring(0, 1).toUpperCase();
    return (mots.first.substring(0, 1) + mots[1].substring(0, 1)).toUpperCase();
  }

  void _aller(BuildContext context, Widget ecran) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ecran));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = profil;
    final theme = Theme.of(context);
    final invitations = ref.watch(mesInvitationsProvider).valueOrNull?.length ?? 0;
    final verrou = ref.watch(verrouControllerProvider);
    final verrouActif = verrou.phase != PhaseVerrou.inactif;
    final suppression = ref.watch(etatSuppressionCompteProvider).valueOrNull;
    final dateSuppression = suppression != null && suppression.demandee ? suppression.effectiveLe : null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Row(
          children: [
            // Photo de profil (REG-23) : toucher pour la changer.
            AvatarProfilModifiable(profil: p),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.nomAffiche, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  if (p.identifiantEcoshop != null)
                    Row(
                      key: const Key('profil_identifiant_ecoshop'),
                      children: [
                        Flexible(child: Text('Identifiant ${p.identifiantEcoshop!}')),
                        IconButton(
                          tooltip: 'Copier l’identifiant',
                          icon: const Icon(Icons.copy_outlined, size: 20),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: p.identifiantEcoshop!));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Identifiant copié')));
                            }
                          },
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
        const TitreSection('Mon compte'),
        _Groupe(children: [
          _Ligne(
            cle: 'profil_mes_informations',
            icone: Icons.person_outline,
            titre: 'Mes informations',
            sousTitre: 'Nom, téléphone, e-mail',
            onTap: () => _aller(context, EcranMesInformations(profil: p)),
          ),
          _Ligne(
            cle: 'profil_mes_invitations',
            icone: Icons.mail_outline,
            titre: 'Mes invitations',
            sousTitre: invitations == 0
                ? 'Aucune invitation en attente'
                : invitations == 1 ? '1 invitation en attente' : '$invitations invitations en attente',
            badge: invitations,
            onTap: () => _aller(context, const EcranInvitations(depuisProfil: true)),
          ),
          // REG-32 : tout adulte peut être parent, dans son école ou une
          // autre — l'espace parent de cette école apparaît une fois l'enfant lié.
          if (p.roleRacine != null && p.roleRacine != RoleRacine.eleve)
            _Ligne(
              cle: 'profil_relier_enfant',
              icone: Icons.family_restroom_outlined,
              titre: 'Relier mon enfant',
              sousTitre: 'Avec son matricule et sa date de naissance',
              onTap: () => afficherAjouterEnfant(context, ref),
            ),
        ]),
        const TitreSection('Sécurité'),
        _Groupe(children: [
          _Ligne(
            cle: 'menu_code_secret',
            icone: Icons.pin_outlined,
            titre: 'Code secret',
            sousTitre: 'Changer mon code à 6 chiffres',
            onTap: () => _aller(context, const EcranChangerCodeCompte()),
          ),
          if (verrouActif)
            SwitchListTile(
              key: const Key('interrupteur_empreinte'),
              secondary: const Icon(Icons.fingerprint),
              title: const Text('Empreinte digitale', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Ouvrir EcoShop d’un toucher'),
              value: verrou.biometrieActivee,
              onChanged: (v) async {
                final c = ref.read(verrouControllerProvider.notifier);
                if (v) {
                  final ok = await c.activerBiometrie();
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Empreinte non activée sur ce téléphone.')));
                  }
                } else {
                  await c.desactiverBiometrie();
                }
              },
            ),
          _Ligne(
            cle: 'menu_mes_appareils',
            icone: Icons.devices_outlined,
            titre: 'Mes appareils',
            sousTitre: 'Où votre compte est ouvert ; déconnecter un appareil perdu',
            onTap: () => _aller(context, const EcranMesAppareils()),
          ),
          _Ligne(
            cle: 'menu_securite',
            icone: Icons.shield_outlined,
            titre: 'Sécurité du compte',
            sousTitre: 'Blocages, code du compte',
            onTap: () => _aller(context, const EcranSecurite()),
          ),
        ]),
        const TitreSection('Préférences'),
        _Groupe(children: [
          _Ligne(
            cle: 'menu_notifications_preferences',
            icone: Icons.notifications_outlined,
            titre: 'Notifications',
            sousTitre: 'Choisir ce que je reçois',
            onTap: () => _aller(context, EcranPreferencesCanaux(profileId: p.id)),
          ),
          // Avis du portail (REG-09) : le parent ou l'élève choisit.
          if (p.roleRacine == RoleRacine.parent || p.roleRacine == RoleRacine.eleve) const InterrupteurAvisPortail(),
          _Ligne(
            cle: 'menu_affichage_accueil',
            icone: Icons.dashboard_customize_outlined,
            titre: 'Affichage de l’accueil',
            sousTitre: 'Défilant ou fixe, 2 ou 3 pastilles par ligne',
            onTap: () => afficherReglagesAccueil(context),
          ),
          _Ligne(
            cle: 'menu_langue_affichage',
            icone: Icons.translate_outlined,
            titre: 'Langue et affichage',
            sousTitre: 'Langue, taille du texte, accessibilité',
            onTap: () => _aller(context, const EcranPreferencesApparence()),
          ),
        ]),
        // Vos données (REG-31) : conditions, confidentialité, suppression.
        const TitreSection('Vos données'),
        _Groupe(children: [
          _Ligne(
            cle: 'menu_cgu',
            icone: Icons.gavel_outlined,
            titre: 'Conditions d’utilisation',
            sousTitre: 'Relire les conditions acceptées',
            onTap: () => _aller(context, const EcranCgu()),
          ),
          _Ligne(
            cle: 'menu_confidentialite',
            icone: Icons.privacy_tip_outlined,
            titre: 'Confidentialité',
            sousTitre: 'Ce que nous savons de vous, et vos droits',
            onTap: () => ouvrirLienLegal(context, LiensLegaux.confidentialite),
          ),
        ]),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          key: const Key('bouton_deconnexion'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: () => ref.deconnecterEtPurgerDonneesLocales(),
          icon: const Icon(Icons.logout),
          label: const Text('Se déconnecter'),
        ),
        // Appareil partagé ou prêté (REG-35) : efface aussi les données de ce
        // compte. Sans cela, elles restent sur l'appareil, chiffrées pour ce
        // seul compte.
        TextButton(
          key: const Key('bouton_deconnexion_effacer'),
          onPressed: () => _deconnecterEtEffacer(context, ref),
          child: const Text('Appareil partagé ? Se déconnecter et effacer mes données'),
        ),
        const SizedBox(height: 12),
        // Exigé par Google Play : facile à trouver, tout en bas du profil.
        Center(
          child: TextButton.icon(
            key: const Key('bouton_supprimer_compte'),
            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
            onPressed: () => _aller(context, const EcranSuppressionCompte()),
            icon: const Icon(Icons.delete_outline),
            label: Text(dateSuppression != null
                ? 'Suppression prévue le ${formaterDate(dateSuppression)}'
                : 'Supprimer mon compte'),
          ),
        ),
      ],
    );
  }
}

class _Groupe extends StatelessWidget {
  const _Groupe({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final sombre = Theme.of(context).brightness == Brightness.dark;
    final schema = Theme.of(context).colorScheme;
    return Material(
      color: sombre ? schema.surfaceContainerHigh : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: sombre ? schema.outlineVariant : const Color(0xFFE3E7E2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          children[i],
        ],
      ]),
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({
    required this.cle,
    required this.icone,
    required this.titre,
    required this.sousTitre,
    required this.onTap,
    this.badge = 0,
  });

  final String cle;
  final IconData icone;
  final String titre;
  final String sousTitre;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key(cle),
      minVerticalPadding: 10,
      leading: Icon(icone),
      title: Text(titre, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(sousTitre),
      trailing: badge > 0 ? Badge(label: Text('$badge'), backgroundColor: const Color(0xFFB9480F)) : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// Mon compte › Mes informations : nom, identifiant, téléphone, rôle.
class EcranMesInformations extends ConsumerWidget {
  const EcranMesInformations({super.key, required this.profil});

  final Profil profil;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tel = ref.watch(telephoneProfilProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Mes informations')),
      body: ListView(
        children: [
          ListTile(leading: const Icon(Icons.person_outline), title: Text(profil.nomAffiche), subtitle: const Text('Nom')),
          ListTile(
            leading: const Icon(Icons.alternate_email),
            title: Text(profil.identifiantCanonique),
            subtitle: const Text('Adresse de connexion'),
          ),
          ListTile(
            key: const Key('profil_telephone'),
            leading: Icon(tel?.verifie == true ? Icons.verified_outlined : Icons.phone_outlined),
            title: Text(tel == null ? 'Ajouter mon numéro de téléphone' : tel.lisible),
            subtitle: Text(tel == null ? 'Pour que l’école puisse vous joindre' : tel.statut),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EcranTelephoneProfil(modification: true, actuel: tel)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: Text(profil.roleRacine?.libelle ?? 'Non défini'),
            subtitle: const Text('Rôle'),
          ),
        ],
      ),
    );
  }
}

/// Confirmation, puis déconnexion avec effacement (REG-35).
Future<void> _deconnecterEtEffacer(BuildContext context, WidgetRef ref) async {
  final confirme = await showDialog<bool>(
    context: context,
    builder: (contexte) => AlertDialog(
      title: const Text('Effacer mes données de cet appareil ?'),
      content: const Text(
        'À choisir sur un téléphone prêté ou partagé. Vos données gardées pour le hors connexion '
        'seront effacées de cet appareil ; elles restent sur le serveur et reviendront à votre '
        'prochaine connexion. Sans cela, elles restent ici, chiffrées : aucun autre compte ne peut les lire.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(contexte).pop(false), child: const Text('Annuler')),
        FilledButton(
          key: const Key('confirmer_deconnexion_effacer'),
          onPressed: () => Navigator.of(contexte).pop(true),
          child: const Text('Effacer et se déconnecter'),
        ),
      ],
    ),
  );
  if (confirme != true) return;
  final enAttente = await ref.deconnecterEtEffacerMesDonnees();
  if (enAttente > 0 && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$enAttente saisie(s) attendent encore d\'être envoyées : reconnectez-vous au réseau, '
          'puis recommencez. Rien n\'a été effacé.'),
    ));
  }
}
