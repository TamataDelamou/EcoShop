import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/role_racine.dart';
import '../application/auth_providers.dart';
import '../application/inscription_providers.dart';

/// Dernière étape de la création d'un compte (REG-18, partie B) :
/// bienvenue, identifiant EcoShop, prochaine étape. Affiché une fois.
class EcranRecapitulatif extends ConsumerWidget {
  const EcranRecapitulatif({super.key});

  static String prochaineEtape(RoleRacine? role) => switch (role) {
        RoleRacine.parent => 'Liez la fiche de votre enfant : Scolarité › Ajouter un enfant, avec son matricule '
            'et sa date de naissance (donnés par l’école). Sans enfant inscrit, la boutique vous est ouverte.',
        RoleRacine.eleve => 'Votre fiche est liée : vos notes, votre emploi du temps et la révision vous attendent.',
        _ => 'Votre espace est prêt.',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profil = ref.watch(profilProvider).valueOrNull;
    final theme = Theme.of(context);
    final identifiant = profil?.identifiantEcoshop;
    final prenom = (profil?.prenom ?? '').trim();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.celebration_outlined, size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    prenom.isEmpty ? 'Bienvenue sur EcoShop' : 'Bienvenue, $prenom',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (identifiant != null)
                    Card(
                      child: ListTile(
                        key: const Key('recap_identifiant'),
                        leading: const Icon(Icons.qr_code_2_outlined),
                        title: Text(identifiant, style: theme.textTheme.titleLarge),
                        subtitle: const Text(
                          'Votre identifiant EcoShop. Donnez-le au guichet de l’école ; '
                          'il permet aussi de vous connecter (un code est envoyé à votre adresse).',
                        ),
                        trailing: IconButton(
                          tooltip: 'Copier',
                          icon: const Icon(Icons.copy_outlined),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: identifiant));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(const SnackBar(content: Text('Identifiant copié')));
                            }
                          },
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text('Prochaine étape', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(prochaineEtape(profil?.roleRacine), key: const Key('recap_prochaine_etape')),
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('bouton_commencer'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: () => ref.read(recapitulatifAMontrerProvider.notifier).vu(),
                    child: const Text('Commencer'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
