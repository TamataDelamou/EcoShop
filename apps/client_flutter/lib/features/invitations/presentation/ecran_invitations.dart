import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../application/invitations_providers.dart';
import '../domain/invitation.dart';

/// Invitations reçues (personnel, vendeurs), présentées après la connexion
/// et depuis « Mon profil › Mes invitations ».
///
/// Accepter rattache le compte à l'école avec le rôle et le poste prévus ;
/// refuser prévient la personne qui a invité. Une invitation envoyée à un
/// numéro seulement déclaré est visible mais ne peut recevoir de réponse
/// qu'après la confirmation du numéro par l'école (règle REG-16).
class EcranInvitations extends ConsumerWidget {
  const EcranInvitations({super.key, this.depuisProfil = false});

  /// Ouvert depuis « Mon profil » : pas de « Plus tard », retour normal.
  final bool depuisProfil;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invitations = depuisProfil ? ref.watch(mesInvitationsProvider) : ref.watch(invitationsAPresenterProvider);
    final sansRole = ref.watch(profilProvider).valueOrNull?.roleDefini == false;
    final theme = Theme.of(context);
    final liste = invitations.valueOrNull ?? const <InvitationRecue>[];

    void remettre() {
      ref.read(invitationsRemisesProvider.notifier).state = {
        ...ref.read(invitationsRemisesProvider),
        for (final i in liste) i.id,
      };
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(liste.length > 1 ? 'Vos invitations' : 'Votre invitation'),
        automaticallyImplyLeading: depuisProfil,
      ),
      body: SafeArea(
        // Rechargement : la liste reste affichée (pas d'écran d'attente).
        child: invitations.isLoading && !invitations.hasValue
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (liste.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Aucune invitation en attente.', textAlign: TextAlign.center),
                    ),
                  for (final i in liste) _CarteInvitation(invitation: i),
                  if (!depuisProfil && liste.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      key: const Key('invitations_plus_tard'),
                      onPressed: remettre,
                      child: Text(sansRole ? 'Continuer sans invitation' : 'Plus tard'),
                    ),
                    Text(
                      sansRole
                          ? 'Vous pourrez créer votre espace élève ou parent à la place.'
                          : 'Vous les retrouverez dans « Mon profil › Mes invitations ».',
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _CarteInvitation extends ConsumerStatefulWidget {
  const _CarteInvitation({required this.invitation});

  final InvitationRecue invitation;

  @override
  ConsumerState<_CarteInvitation> createState() => _CarteInvitationState();
}

class _CarteInvitationState extends ConsumerState<_CarteInvitation> {
  bool _enCours = false;
  String? _erreur;

  Future<void> _repondre(bool accepter) async {
    final i = widget.invitation;
    if (!accepter) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Refuser l’invitation ?'),
          content: Text('${i.etablissement} sera prévenu de votre refus.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Refuser')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    final messager = ScaffoldMessenger.maybeOf(context);
    try {
      await ref.read(invitationsRepositoryProvider).repondre(i.id, accepter: accepter);
      ref.invalidate(mesInvitationsProvider);
      // Rôle et établissements viennent de changer côté serveur.
      if (accepter) ref.rafraichirSession();
      messager?.showSnackBar(SnackBar(
        content: Text(accepter ? 'Bienvenue : vous avez rejoint ${i.etablissement}.' : 'Invitation refusée.'),
      ));
    } on ErreurInvitations catch (e) {
      if (e.code == 'INVITATION_DEJA_TRAITEE' || e.code == 'INVITATION_EXPIREE' || e.code == 'INVITATION_INTROUVABLE') {
        // L'invitation va disparaître de la liste : message hors de la carte.
        messager?.showSnackBar(SnackBar(content: Text(e.message)));
        ref.invalidate(mesInvitationsProvider);
      } else if (mounted) {
        setState(() => _erreur = e.message);
      }
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.invitation;
    final theme = Theme.of(context);
    final role = libelleRoleInvitation(i.roleCible);
    final date = i.expireLe == null
        ? null
        : '${i.expireLe!.day.toString().padLeft(2, '0')}/${i.expireLe!.month.toString().padLeft(2, '0')}/${i.expireLe!.year}';

    return Card(
      key: ValueKey('invitation_${i.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.mail_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(i.etablissement, style: theme.textTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: 8),
            Text('${i.invitePar != null ? '${i.invitePar} vous invite' : 'Vous êtes invité(e)'} '
                'comme $role${i.poste != null ? ' (${i.poste})' : ''}.'),
            const SizedBox(height: 4),
            Text(
              'Envoyée à ${i.identifiant}${date != null ? ' · valable jusqu’au $date' : ''}',
              style: theme.textTheme.bodySmall,
            ),
            if (!i.verifie) ...[
              const SizedBox(height: 12),
              Container(
                key: const Key('invitation_numero_non_confirme'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Invitation envoyée à votre numéro de téléphone. Pour y répondre, faites d’abord confirmer ce numéro '
                  'par l’école, en sa présence (menu « Numéros à confirmer » de la direction).',
                ),
              ),
            ],
            if (_erreur != null) ...[
              const SizedBox(height: 8),
              Text(_erreur!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (i.verifie)
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      key: Key('refuser_${i.id}'),
                      onPressed: _enCours ? null : () => _repondre(false),
                      child: const Text('Refuser'),
                    ),
                    FilledButton(
                      key: Key('accepter_${i.id}'),
                      onPressed: _enCours ? null : () => _repondre(true),
                      child: const Text('Accepter'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
