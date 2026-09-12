import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/shimmer.dart';
import '../../scolarite/application/scolarite_providers.dart';
import '../../scolarite/domain/fiche_eleve.dart';
import '../application/vie_scolaire_providers.dart';
import '../domain/presence.dart';
import '../domain/retard.dart';
import 'ecran_sanctions.dart';
import 'widgets/badge_signal_ia.dart';
import 'widgets/pastille_statut_presence.dart';

/// Suivi de vie scolaire d'un élève (M7, mode élève/parent/direction) :
/// registre de présences/retards, indicateurs synthétiques et sanctions.
///
/// Réactif au sélecteur d'enfant : appelé avec la fiche de l'enfant actif,
/// se reconstruit entièrement dès que `enfantActifProvider` change (M5).
class EcranSuiviVieScolaire extends ConsumerWidget {
  const EcranSuiviVieScolaire({super.key, required this.fiche});

  final FicheEleve fiche;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inscriptions = ref.watch(inscriptionsDeFicheProvider(fiche.id));

    return Scaffold(
      appBar: AppBar(
        title: Text('Vie scolaire — ${fiche.prenom}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.gavel_outlined),
            tooltip: 'Sanctions',
            onPressed: () async {
              final inscriptions = await ref.read(inscriptionsDeFicheProvider(fiche.id).future);
              if (!context.mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EcranSanctions(
                    fiche: fiche,
                    anneeScolaireId: inscriptions.isEmpty ? null : inscriptions.first.anneeScolaireId,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: inscriptions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (erreur, _) => const Center(child: Text('Impossible de déterminer l\'année scolaire.')),
        data: (liste) {
          final anneeId = liste.isEmpty ? null : liste.first.anneeScolaireId;
          return _Contenu(fiche: fiche, anneeScolaireId: anneeId);
        },
      ),
    );
  }
}

class _Contenu extends ConsumerWidget {
  const _Contenu({required this.fiche, required this.anneeScolaireId});

  final FicheEleve fiche;
  final String? anneeScolaireId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presences = ref.watch(presencesDeFicheProvider(fiche.id));
    final retards = ref.watch(retardsDeFicheProvider(fiche.id));
    final alertes = ref.watch(alertesDeFicheProvider(fiche.id));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(presencesDeFicheProvider(fiche.id));
        ref.invalidate(retardsDeFicheProvider(fiche.id));
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (anneeScolaireId != null) _CarteIndicateurs(ficheId: fiche.id, anneeScolaireId: anneeScolaireId!),
          const SizedBox(height: 16),
          presences.when(
            loading: () => const ShimmerCarteListe(),
            error: (erreur, _) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Registre indisponible hors connexion pour le moment.'),
            ),
            data: (liste) => _CarteTauxPresence(presences: liste),
          ),
          const SizedBox(height: 20),
          alertes.when(
            loading: () => const SizedBox.shrink(),
            error: (erreur, _) => const SizedBox.shrink(),
            data: (liste) => liste.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Alertes de suivi', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        for (final alerte in liste)
                          Card(
                            color: context.palette.premium.withValues(alpha: 0.06),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const BadgeSignalIa(texte: 'Alerte de suivi — à examiner avec l\'établissement'),
                                  const SizedBox(height: 6),
                                  Text('Score : ${(alerte.score * 100).toStringAsFixed(0)} %'),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          Text('Présences', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          presences.when(
            loading: () => ListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: List.generate(3, (_) => const ShimmerCarteListe()),
            ),
            error: (erreur, _) => const Text('Indisponible hors connexion pour le moment.'),
            data: (liste) => liste.isEmpty
                ? const Text('Aucune absence ni retard enregistré.')
                : Column(
                    children: [
                      for (var i = 0; i < liste.length; i++)
                        EntreeAnimee(index: i, enfant: _CartePresence(presence: liste[i])),
                    ],
                  ),
          ),
          const SizedBox(height: 20),
          Text('Retards', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          retards.when(
            loading: () => const SizedBox.shrink(),
            error: (erreur, _) => const Text('Indisponible hors connexion pour le moment.'),
            data: (liste) => liste.isEmpty
                ? const Text('Aucun retard enregistré.')
                : Column(children: [for (final r in liste) _CarteRetard(retard: r)]),
          ),
        ],
      ),
    );
  }
}

class _CarteIndicateurs extends ConsumerWidget {
  const _CarteIndicateurs({required this.ficheId, required this.anneeScolaireId});

  final String ficheId;
  final String anneeScolaireId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyse = ref.watch(analyseComportementProvider((ficheId: ficheId, anneeId: anneeScolaireId)));

    return analyse.when(
      loading: () => const ShimmerCarteListe(),
      error: (erreur, _) => const SizedBox.shrink(),
      data: (donnees) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 20,
            runSpacing: 12,
            children: [
              _Indicateur(
                libelle: 'Absences injustifiées',
                valeur: '${donnees['absences_non_justifiees'] ?? 0}',
                couleur: context.palette.erreur,
              ),
              _Indicateur(
                libelle: 'Absences justifiées',
                valeur: '${donnees['absences_justifiees'] ?? 0}',
                couleur: context.palette.encreSecondaire,
              ),
              _Indicateur(
                libelle: 'Retards injustifiés',
                valeur: '${donnees['retards_non_justifies'] ?? 0}',
                couleur: context.palette.accent,
              ),
              _Indicateur(
                libelle: 'Retard moyen',
                valeur: '${donnees['retard_moyen_minutes'] ?? 0} min',
                couleur: context.palette.primaire,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Indicateur extends StatelessWidget {
  const _Indicateur({required this.libelle, required this.valeur, required this.couleur});

  final String libelle;
  final String valeur;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(valeur, style: TextStyle(color: couleur, fontSize: 22, fontWeight: FontWeight.w700)),
          Text(libelle, style: TextStyle(color: context.palette.encreSecondaire, fontSize: 12)),
        ],
      ),
    );
  }
}

/// Taux de présence : simple décompte d'affichage sur les lignes déjà lues
/// (présents / total pointé) — aucune moyenne pédagogique, donc hors du
/// périmètre des RPC `calculer_moyenne_*`/`analyse_comportement` (contrat
/// M07 §5 ne l'interdit pas : seules les moyennes de notes sont concernées).
class _CarteTauxPresence extends StatelessWidget {
  const _CarteTauxPresence({required this.presences});

  final List<Presence> presences;

  @override
  Widget build(BuildContext context) {
    if (presences.isEmpty) return const SizedBox.shrink();

    final presents = presences.where((p) => p.statut.code == 'present').length;
    final taux = presents / presences.length;
    final couleur = taux >= 0.9 ? context.palette.succes : context.palette.accent;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Taux de présence', style: TextStyle(fontWeight: FontWeight.w600)),
            Text(
              '${(taux * 100).toStringAsFixed(0)} %',
              style: TextStyle(color: couleur, fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartePresence extends ConsumerWidget {
  const _CartePresence({required this.presence});

  final Presence presence;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peutJustifier = presence.statut.code == 'absent' && !presence.justifie;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        title: Text(_formatDate(presence.datePresence)),
        subtitle: presence.motif != null ? Text(presence.motif!) : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PastilleStatutPresence(statut: presence.statut),
            if (peutJustifier)
              IconButton(
                icon: const Icon(Icons.note_add_outlined, size: 18),
                tooltip: 'Justifier cette absence',
                onPressed: () => _afficherJustification(context),
              ),
          ],
        ),
      ),
    );
  }

  void _afficherJustification(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Justifier une absence'),
        content: const Text(
          "Le dépôt direct d'un justificatif par un parent n'est pas encore "
          "ouvert côté serveur (aucune RPC ni règle d'accès ne l'autorise "
          "pour l'instant). Rapprochez-vous de la vie scolaire de "
          "l'établissement en attendant cette fonctionnalité.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Compris')),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _CarteRetard extends StatelessWidget {
  const _CarteRetard({required this.retard});

  final Retard retard;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(Icons.schedule_outlined, color: context.palette.accent),
        title: Text('${retard.minutesRetard} min — ${_formatDate(retard.dateRetard)}'),
        subtitle: retard.motif != null ? Text(retard.motif!) : null,
        trailing: Icon(
          retard.justifie ? Icons.check_circle_outline : Icons.circle_outlined,
          color: retard.justifie ? context.palette.succes : context.palette.encreSecondaire,
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
