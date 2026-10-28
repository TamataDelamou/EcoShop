import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../coquille/application/session_logout.dart';
import '../../creation_etablissement/application/creation_etablissement_providers.dart';
import '../../creation_etablissement/presentation/carte_demande_etablissement.dart';
import '../../reseau/presentation/ecran_mes_reseaux.dart';
import '../application/auth_providers.dart';
import '../application/connexion_controller.dart';
import '../application/inscription_providers.dart';
import '../domain/auth_repository.dart';
import '../domain/inscription_en_cours.dart';
import '../domain/profil.dart';
import 'ecran_creation_compte.dart';
import '../../invitations/presentation/saisie_code_invitation.dart';

/// Fin de la création du compte, après la vérification de l'adresse
/// (REG-18, partie B ; cahier ch. 5.2).
///
/// - Saisies faites avant la vérification (« Créer un compte ») : appliquées
///   tout de suite (`finaliser_inscription`), sans rien redemander.
/// - Nom fourni par Google, ou compte ouvert par « Se connecter » avec une
///   adresse inconnue : espace et nom demandés ici, pré-remplis depuis Google.
/// - « Je représente un établissement » : aucun rôle choisi ; demande
///   d'ouverture (REG-04) et réseau d'écoles, en attendant la validation de
///   Global Service Groupe qui attribue le rôle Direction.
///
/// Seuls Élève et Parent sont des rôles choisis ici : le serveur refuse tout
/// autre rôle, l'écran ne fait que refléter cette règle.
class EcranChoixRole extends ConsumerStatefulWidget {
  const EcranChoixRole({super.key});

  @override
  ConsumerState<EcranChoixRole> createState() => _EcranChoixRoleState();
}

class _EcranChoixRoleState extends ConsumerState<EcranChoixRole> {
  final _prenom = TextEditingController();
  final _nom = TextEditingController();
  final _formulaire = GlobalKey<FormState>();

  EspaceInscription? _espace;
  bool _initialise = false;
  bool _enCours = false;
  bool _vueEtablissement = false;
  String? _codeErreur;

  @override
  void dispose() {
    _prenom.dispose();
    _nom.dispose();
    super.dispose();
  }

  void _initialiser(InscriptionEnCours? inscription, Profil? profil) {
    if (_initialise) return;
    _initialise = true;
    final google = ref.read(nomsGoogleProvider);
    _espace = inscription?.espace;
    _prenom.text = _premier([inscription?.prenom, profil?.prenom, google.prenom]);
    _nom.text = _premier([inscription?.nom, profil?.nom, google.nom]);

    // Tout a été saisi avant la vérification : rien à redemander.
    if (inscription != null && inscription.nomComplet) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _valider(automatique: true);
      });
    }
  }

  static String _premier(List<String?> valeurs) =>
      valeurs.firstWhere((v) => v != null && v.trim().isNotEmpty, orElse: () => '') ?? '';

  Future<void> _valider({bool automatique = false}) async {
    final espace = _espace;
    if (espace == null) return;
    final nomsValides = verifierNom(_prenom.text) == null && verifierNom(_nom.text) == null;
    if (!automatique) _formulaire.currentState?.validate();
    if (!nomsValides) return;

    setState(() {
      _enCours = true;
      _codeErreur = null;
    });
    final repo = ref.read(authRepositoryProvider);
    final prenom = _prenom.text.trim();
    final nom = _nom.text.trim();
    try {
      final role = espace.role;
      if (role == null) {
        // Représentant d'un établissement : nom seulement, aucun rôle.
        final profil = ref.read(profilProvider).valueOrNull;
        if (profil == null || profil.prenom != prenom || profil.nom != nom) {
          await repo.definirMonNom(prenom: prenom, nom: nom);
          ref.invalidate(profilProvider);
        }
        await ref.read(inscriptionEnCoursProvider.notifier).enregistrer(espace: espace, prenom: prenom, nom: nom);
        if (mounted) setState(() => _vueEtablissement = true);
        return;
      }

      final applique = await repo.finaliserInscription(espace: role, prenom: prenom, nom: nom);
      if (!applique) {
        // Compte d'avant REG-18 resté sans rôle : ancien choix du rôle.
        try {
          await repo.choisirRole(role);
        } on ErreurAuth catch (e) {
          if (e.code != 'ROLE_DEJA_DEFINI') rethrow;
        }
      }
      final profilId = ref.read(profilProvider).valueOrNull?.id;
      if (applique && profilId != null) {
        await ref.read(recapitulatifAMontrerProvider.notifier).aMontrer(profilId);
      }
      await ref.read(inscriptionEnCoursProvider.notifier).effacer();
      // L'espace vient d'être fixé côté serveur : la garde relit le profil.
      ref.rafraichirSession();
    } on ErreurAuth catch (e) {
      if (mounted) setState(() => _codeErreur = e.code);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inscription = ref.watch(inscriptionEnCoursProvider);
    final profil = ref.watch(profilProvider).valueOrNull;
    if (inscription.isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    _initialiser(inscription.valueOrNull, profil);

    // Une demande d'ouverture déjà faite : on revient à son suivi.
    final demande = ref.watch(maDemandeEtablissementProvider).valueOrNull;
    final vueEtablissement = _vueEtablissement || (demande != null && _espace == null);

    final automatique = inscription.valueOrNull?.nomComplet == true && _enCours && _codeErreur == null;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(vueEtablissement ? 'Votre établissement' : 'Votre espace')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: automatique
                  ? const _Patienter()
                  : vueEtablissement
                      ? _EspaceEtablissement(
                          surAutreEspace: () => setState(() {
                            _vueEtablissement = false;
                            _espace = null;
                          }),
                        )
                      : _formulaireEspace(theme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _formulaireEspace(ThemeData theme) {
    return Form(
      key: _formulaire,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Encore une étape', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Votre adresse est vérifiée. Choisissez votre espace et confirmez votre nom. '
            'Le choix Élève ou Parent est définitif.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          ChoixEspaceInscription(valeur: _espace, surChoix: (e) => setState(() => _espace = e)),
          const SizedBox(height: 8),
          TextFormField(
            key: const Key('champ_prenom'),
            controller: _prenom,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Prénom(s)'),
            validator: verifierNom,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('champ_nom'),
            controller: _nom,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nom'),
            validator: verifierNom,
          ),
          if (_codeErreur != null) ...[
            const SizedBox(height: 12),
            Text(messageErreurAuth(_codeErreur!), style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('bouton_continuer_espace'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _espace == null || _enCours ? null : _valider,
            child: _enCours
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Continuer'),
          ),
          const SizedBox(height: 16),
          // Enseignant, personnel, vendeur : code remis par l'école (REG-27).
          const BoutonCodeInvitation(),
          const SizedBox(height: 8),
          const _SeDeconnecter(),
        ],
      ),
    );
  }
}

class _Patienter extends StatelessWidget {
  const _Patienter();

  @override
  Widget build(BuildContext context) => const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Création de votre espace…'),
        ],
      );
}

/// Représentant d'un établissement, en attendant la validation de Global
/// Service Groupe : demande d'ouverture (REG-04) et réseau d'écoles (M19).
class _EspaceEtablissement extends StatelessWidget {
  const _EspaceEtablissement({required this.surAutreEspace});

  final VoidCallback surAutreEspace;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Demande d'ouverture et son suivi jusqu'à la validation.
        const CarteDemandeEtablissement(),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            key: const Key('espace_reseau'),
            leading: const Icon(Icons.hub_outlined),
            title: const Text('Réseau d’établissements'),
            subtitle: const Text('Vous fondez ou dirigez un réseau d’écoles : demande de création, pilotage.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EcranMesReseaux())),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          key: const Key('autre_espace'),
          onPressed: surAutreEspace,
          child: const Text('Je suis plutôt élève ou parent'),
        ),
        const _SeDeconnecter(),
      ],
    );
  }
}

/// Quitter ce compte sans aller plus loin (mauvaise adresse, téléphone prêté).
class _SeDeconnecter extends ConsumerWidget {
  const _SeDeconnecter();

  @override
  Widget build(BuildContext context, WidgetRef ref) => TextButton(
        key: const Key('deconnexion_inscription'),
        onPressed: () => ref.deconnecterEtPurgerDonneesLocales(),
        child: const Text('Se déconnecter'),
      );
}
