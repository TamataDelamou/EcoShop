import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/role_racine.dart';
import '../application/invitations_providers.dart';
import '../domain/invitation.dart';

/// Invitations du personnel et des vendeurs, pour la direction : inviter
/// (e-mail de préférence), suivre les réponses, retirer une invitation en
/// attente.
class EcranInvitationsEtablissement extends ConsumerWidget {
  const EcranInvitationsEtablissement({super.key, required this.etablissementId});

  final String etablissementId;

  Future<void> _inviter(BuildContext context) async {
    final envoyee = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormulaireInvitation(etablissementId: etablissementId),
    );
    if (envoyee == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invitation envoyée.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invitations = ref.watch(invitationsEtablissementProvider(etablissementId));
    return Scaffold(
      appBar: AppBar(title: const Text('Invitations du personnel')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('bouton_inviter'),
        onPressed: () => _inviter(context),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Inviter'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(invitationsEtablissementProvider(etablissementId)),
        child: invitations.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(padding: const EdgeInsets.all(24), children: [
            Text(e is ErreurInvitations ? e.message : 'Liste indisponible. Tirez pour réessayer.',
                textAlign: TextAlign.center),
          ]),
          data: (liste) => ListView(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 4, 8, 12),
                child: Text(
                  'Invitez de préférence par e-mail : un courriel part aussitôt. Par téléphone, aucun SMS n’est '
                  'envoyé, et la personne doit faire confirmer son numéro à l’école avant de répondre.',
                ),
              ),
              if (liste.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Aucune invitation pour le moment.', textAlign: TextAlign.center),
                ),
              for (final i in liste) _LigneInvitation(invitation: i, etablissementId: etablissementId),
            ],
          ),
        ),
      ),
    );
  }
}

class _LigneInvitation extends ConsumerWidget {
  const _LigneInvitation({required this.invitation, required this.etablissementId});

  final InvitationEnvoyee invitation;
  final String etablissementId;

  Future<void> _retirer(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Retirer l’invitation ?'),
        content: Text('${invitation.identifiant} ne pourra plus l’accepter.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Retirer')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messager = ScaffoldMessenger.of(context);
    try {
      await ref.read(invitationsRepositoryProvider).revoquer(invitation.id);
      ref.invalidate(invitationsEtablissementProvider(etablissementId));
    } on ErreurInvitations catch (e) {
      messager.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i = invitation;
    final parTelephone = !i.identifiant.contains('@');
    return Card(
      key: ValueKey('invitation_envoyee_${i.id}'),
      child: ListTile(
        leading: Icon(parTelephone ? Icons.phone_outlined : Icons.alternate_email),
        title: Text(i.identifiant),
        subtitle: Text([
          libelleRoleInvitation(i.roleCible) + (i.poste != null ? ' · ${i.poste}' : ''),
          i.statut.libelle + (i.membre != null ? ' par ${i.membre}' : ''),
        ].join('\n')),
        isThreeLine: true,
        trailing: i.statut == StatutInvitation.enAttente
            ? IconButton(
                key: Key('retirer_${i.id}'),
                tooltip: 'Retirer',
                icon: const Icon(Icons.cancel_outlined),
                onPressed: () => _retirer(context, ref),
              )
            : null,
      ),
    );
  }
}

class _FormulaireInvitation extends ConsumerStatefulWidget {
  const _FormulaireInvitation({required this.etablissementId});

  final String etablissementId;

  @override
  ConsumerState<_FormulaireInvitation> createState() => _FormulaireInvitationState();
}

class _FormulaireInvitationState extends ConsumerState<_FormulaireInvitation> {
  final _identifiant = TextEditingController();
  final _formulaire = GlobalKey<FormState>();
  RoleRacine _role = RoleRacine.enseignant;
  String? _posteId;
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _identifiant.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    if (!(_formulaire.currentState?.validate() ?? false)) return;
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      await ref.read(invitationsRepositoryProvider).inviter(
            etablissementId: widget.etablissementId,
            identifiant: normaliserIdentifiantInvitation(_identifiant.text)!,
            role: _role,
            posteId: _posteId,
          );
      ref.invalidate(invitationsEtablissementProvider(widget.etablissementId));
      if (mounted) Navigator.of(context).pop(true);
    } on ErreurInvitations catch (e) {
      if (mounted) setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final postes = ref.watch(postesInvitablesProvider(widget.etablissementId)).valueOrNull ?? const [];
    final theme = Theme.of(context);
    final parTelephone = _identifiant.text.trim().startsWith('+');

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formulaire,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Inviter une personne', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('champ_identifiant_invite'),
              controller: _identifiant,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Adresse e-mail (ou numéro +224…)',
                hintText: 'prenom.nom@exemple.com',
              ),
              onChanged: (_) => setState(() {}),
              validator: (v) => normaliserIdentifiantInvitation(v ?? '') == null
                  ? 'Une adresse e-mail, ou un numéro avec l’indicatif (+224…).'
                  : null,
            ),
            if (parTelephone)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Aucun SMS n’est envoyé : prévenez la personne. Elle devra faire confirmer ce numéro à l’école '
                  '(« Numéros à confirmer ») avant de pouvoir accepter.',
                  key: const Key('avertissement_telephone'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 16),
            DropdownButtonFormField<RoleRacine>(
              key: const Key('choix_role_invite'),
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Rôle'),
              items: [
                for (final r in rolesInvitables)
                  DropdownMenuItem(value: r, child: Text(libelleRoleInvitation(r.code))),
              ],
              onChanged: (r) => setState(() => _role = r ?? _role),
            ),
            if (postes.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: const Key('choix_poste_invite'),
                initialValue: _posteId,
                decoration: const InputDecoration(labelText: 'Poste (facultatif)'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Aucun')),
                  for (final p in postes) DropdownMenuItem<String?>(value: p.id, child: Text(p.nom)),
                ],
                onChanged: (v) => setState(() => _posteId = v),
              ),
            ],
            if (_erreur != null) ...[
              const SizedBox(height: 12),
              Text(_erreur!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('bouton_envoyer_invitation'),
              onPressed: _enCours ? null : _envoyer,
              child: const Text('Envoyer l’invitation'),
            ),
          ],
        ),
      ),
    );
  }
}
