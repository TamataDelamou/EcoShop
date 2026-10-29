import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/liens_legaux.dart';
import '../../../core/providers.dart';
import '../../../core/securite/gardien_actions_sensibles.dart';
import '../../../core/widgets/choisir_date.dart';
import '../application/suppression_compte_providers.dart';
import '../domain/suppression_compte.dart';

/// Mon profil › Supprimer mon compte (REG-31, règle Google Play).
///
/// Dit simplement ce qui est effacé, ce qui est gardé et pourquoi, puis
/// programme la suppression à 7 jours ; tant que le délai court, le même
/// écran propose « Garder mon compte ».
class EcranSuppressionCompte extends ConsumerStatefulWidget {
  const EcranSuppressionCompte({super.key});

  @override
  ConsumerState<EcranSuppressionCompte> createState() => _EcranSuppressionCompteState();
}

class _EcranSuppressionCompteState extends ConsumerState<EcranSuppressionCompte> {
  final _motif = TextEditingController();
  bool _compris = false;
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _motif.dispose();
    super.dispose();
  }

  Future<void> _demander() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final reponse = await ref.read(suppressionCompteRepositoryProvider).demander(
            motif: _motif.text.trim().isEmpty ? null : _motif.text.trim(),
          );
      if (!mounted) return;
      switch (reponse) {
        case SuppressionProgrammee(:final effectiveLe):
          ref.invalidate(etatSuppressionCompteProvider);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('C’est noté. Votre compte sera supprimé le ${formaterDate(effectiveLe)}.'),
          ));
        case DirectionSeule(:final ecoles):
          setState(() => _erreur =
              'Vous êtes la seule personne à la direction de ${ecoles.join(', ')}. Invitez d’abord une autre '
              'personne à la direction (Configuration de l’école › Personnel et enseignants), pour que l’école '
              'ne se retrouve pas sans responsable.');
      }
    } on ActionSensibleAnnulee {
      // Code non confirmé : rien n'a été demandé.
    } catch (_) {
      if (mounted) setState(() => _erreur = 'La demande n’a pas pu être envoyée. Vérifiez la connexion et réessayez.');
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _garder() async {
    setState(() => _enCours = true);
    try {
      await ref.read(suppressionCompteRepositoryProvider).annuler();
      ref.invalidate(etatSuppressionCompteProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Votre compte est conservé. Content de vous garder !')),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _erreur = 'L’annulation n’a pas pu être envoyée. Vérifiez la connexion et réessayez.');
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final enLigne = ref.watch(estEnLigneProvider);
    final etat = ref.watch(etatSuppressionCompteProvider);
    final demande = etat.valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Supprimer mon compte')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          if (demande != null && demande.demandee) ...[
            Card(
              key: const Key('suppression_programmee'),
              color: palette.erreur.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Suppression prévue le ${formaterDate(demande.effectiveLe ?? DateTime.now())}',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text('Vous pouvez encore changer d’avis : touchez « Garder mon compte » et tout reste comme avant.'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const Key('bouton_garder_compte'),
                      onPressed: _enCours || !enLigne ? null : _garder,
                      icon: const Icon(Icons.favorite_outline),
                      label: const Text('Garder mon compte'),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Text('Vous voulez partir ?', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'C’est votre droit, et vous n’avez pas à vous justifier. Avant de confirmer, voici ce qui va se passer.',
            ),
          ],
          const SizedBox(height: 20),
          _Bloc(
            icone: Icons.delete_outline,
            couleur: palette.erreur,
            titre: 'Ce qui sera effacé',
            lignes: const [
              'Votre nom, votre adresse e-mail, votre téléphone et votre photo',
              'Votre accès : appareils connectés, code secret, notifications',
              'Vos réglages',
              'Vos liens avec vos enfants et vos accès aux écoles',
            ],
          ),
          const SizedBox(height: 12),
          _Bloc(
            icone: Icons.inventory_2_outlined,
            couleur: palette.primaire,
            titre: 'Ce qui sera gardé, et pourquoi',
            lignes: const [
              'Le dossier scolaire d’un élève (notes, bulletins, absences) : il appartient à son école',
              'Les reçus de paiement : 10 ans, comme l’exige la loi comptable (OHADA), sans lien vers votre compte',
            ],
          ),
          const SizedBox(height: 12),
          _Bloc(
            icone: Icons.schedule,
            couleur: palette.encreSecondaire,
            titre: '7 jours pour changer d’avis',
            lignes: const [
              'Votre compte reste utilisable pendant 7 jours',
              'Pour annuler, revenez ici et touchez « Garder mon compte »',
              'Passé ce délai, la suppression est définitive',
            ],
          ),
          if (demande == null || !demande.demandee) ...[
            const SizedBox(height: 20),
            TextField(
              key: const Key('champ_motif_suppression'),
              controller: _motif,
              maxLength: 500,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(
                labelText: 'Un mot pour nous aider à nous améliorer (facultatif)',
                border: OutlineInputBorder(),
              ),
            ),
            CheckboxListTile(
              key: const Key('case_compris_suppression'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _compris,
              onChanged: (v) => setState(() => _compris = v ?? false),
              title: const Text('J’ai compris ce qui sera effacé et ce qui sera gardé.'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('bouton_confirmer_suppression'),
              style: FilledButton.styleFrom(
                backgroundColor: palette.erreur,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: !_compris || _enCours || !enLigne ? null : _demander,
              icon: _enCours
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.delete_forever_outlined),
              label: const Text('Supprimer mon compte'),
            ),
          ],
          if (!enLigne) ...[
            const SizedBox(height: 12),
            Text(
              'Connectez-vous à Internet pour continuer : la demande doit arriver jusqu’à nos serveurs.',
              style: TextStyle(color: palette.encreSecondaire),
            ),
          ],
          if (_erreur != null) ...[
            const SizedBox(height: 12),
            Text(_erreur!, key: const Key('erreur_suppression'), style: TextStyle(color: palette.erreur)),
          ],
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: () => ouvrirLienLegal(context, LiensLegaux.confidentialite.replace(fragment: 'suppression')),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('En savoir plus sur vos données'),
          ),
        ],
      ),
    );
  }
}

class _Bloc extends StatelessWidget {
  const _Bloc({required this.icone, required this.couleur, required this.titre, required this.lignes});

  final IconData icone;
  final Color couleur;
  final String titre;
  final List<String> lignes;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icone, color: couleur),
              const SizedBox(width: 10),
              Expanded(child: Text(titre, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            ]),
            const SizedBox(height: 8),
            for (final l in lignes)
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 34),
                child: Text('• $l'),
              ),
          ],
        ),
      ),
    );
  }
}
