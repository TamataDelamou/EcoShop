import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/offline/lecture_hors_ligne.dart';
import '../application/auth_providers.dart';
import '../application/connexion_controller.dart' show messageErreurAuth;
import '../application/telephone_profil_providers.dart';
import '../domain/auth_repository.dart';
import '../domain/telephone_profil.dart';

/// Numéros à confirmer (REG-16) : parents et personnel qui ont saisi leur
/// numéro dans l'application. Quand la personne est devant l'agent, il
/// appelle le numéro (le téléphone de la personne sonne) puis confirme.
/// Gratuit, sans SMS ; un numéro confirmé ouvre les invitations adressées
/// à ce numéro et ne peut plus être pris par un autre compte.
class EcranTelephonesAConfirmer extends ConsumerWidget {
  const EcranTelephonesAConfirmer({super.key, required this.etablissementId});

  final String etablissementId;

  Future<void> _confirmer(BuildContext context, WidgetRef ref, TelephoneAConfirmer t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirmer le numéro de ${t.nomAffiche} ?'),
        content: Text(
          'Appelez le ${t.telephoneLisible} devant la personne : confirmez seulement si son téléphone sonne.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Son téléphone a sonné')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messager = ScaffoldMessenger.of(context);
    try {
      await ref.read(authRepositoryProvider).confirmerTelephone(
            etablissementId: etablissementId,
            profilId: t.profilId,
            telephone: t.telephone,
          );
      ref.invalidate(telephonesAConfirmerProvider(etablissementId));
      messager.showSnackBar(SnackBar(content: Text('Numéro de ${t.nomAffiche} confirmé.')));
    } on ErreurAuth catch (e) {
      messager.showSnackBar(SnackBar(content: Text(messageErreurAuth(e.code))));
    } catch (e) {
      messager.showSnackBar(SnackBar(
        content: Text(estErreurReseau(e)
            ? 'Sans connexion : la confirmation demande le réseau. Réessayez une fois connecté.'
            : 'Confirmation impossible pour le moment.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liste = ref.watch(telephonesAConfirmerProvider(etablissementId));
    return Scaffold(
      appBar: AppBar(title: const Text('Numéros à confirmer')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(telephonesAConfirmerProvider(etablissementId).future),
        child: liste.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(estErreurReseau(e)
                  ? 'Sans connexion : la liste s’affiche quand le réseau revient.'
                  : 'Liste indisponible pour le moment.'),
            ],
          ),
          data: (personnes) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Quand la personne est devant vous, appelez son numéro : s’il sonne sur son téléphone, '
                'confirmez. Aucun SMS n’est envoyé.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (personnes.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Text('Tous les numéros sont confirmés.', textAlign: TextAlign.center),
                ),
              for (final t in personnes)
                Card(
                  child: ListTile(
                    title: Text(t.nomAffiche),
                    subtitle: Text([
                      t.telephoneLisible,
                      if (t.enfants != null) 'Enfants : ${t.enfants}',
                    ].join('\n')),
                    isThreeLine: t.enfants != null,
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'Appeler',
                          icon: const Icon(Icons.call_outlined),
                          onPressed: () => launchUrl(Uri(scheme: 'tel', path: t.telephone)),
                        ),
                        IconButton(
                          tooltip: 'Confirmer',
                          icon: const Icon(Icons.verified_outlined),
                          onPressed: () => _confirmer(context, ref, t),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
