import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/role_racine.dart';
import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/shimmer.dart';
import '../../auth/application/auth_providers.dart';
import '../../scolarite/domain/fiche_eleve.dart';
import '../application/vie_scolaire_providers.dart';
import '../domain/enums_vie_scolaire.dart';
import '../domain/sanction.dart';
import 'widgets/badge_signal_ia.dart';

/// Sanctions d'un élève (M7) — éducatives, jamais punitives par défaut.
///
/// Une sanction d'origine IA reste marquée « proposée, à valider » tant
/// qu'aucun humain ne l'a validée : le serveur l'impose déjà (trigger
/// `sanctions_verifie_validation`), l'écran l'explicite pour l'utilisateur.
class EcranSanctions extends ConsumerWidget {
  const EcranSanctions({super.key, required this.fiche});

  final FicheEleve fiche;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sanctions = ref.watch(sanctionsDeFicheProvider(fiche.id));
    final estDirection = ref.watch(profilProvider).value?.roleRacine == RoleRacine.direction;

    return Scaffold(
      appBar: AppBar(title: Text('Sanctions — ${fiche.prenom}')),
      body: sanctions.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: List.generate(3, (_) => const ShimmerCarteListe()),
        ),
        error: (erreur, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Sanctions indisponibles hors connexion pour le moment.'),
          ),
        ),
        data: (liste) => liste.isEmpty
            ? const Center(child: Text('Aucune sanction enregistrée.'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: liste.length,
                itemBuilder: (context, i) => EntreeAnimee(
                  index: i,
                  enfant: _CarteSanction(sanction: liste[i], peutValider: estDirection),
                ),
              ),
      ),
    );
  }
}

class _CarteSanction extends ConsumerWidget {
  const _CarteSanction({required this.sanction, required this.peutValider});

  final Sanction sanction;
  final bool peutValider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(sanction.typeSanction.libelle,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                _PastilleStatutSanction(statut: sanction.statut),
              ],
            ),
            const SizedBox(height: 6),
            Text(sanction.motif),
            if (sanction.contexteEducatif != null) ...[
              const SizedBox(height: 4),
              Text(
                sanction.contexteEducatif!,
                style: TextStyle(color: context.palette.encreSecondaire, fontSize: 13),
              ),
            ],
            const SizedBox(height: 8),
            if (sanction.origine == OrigineSanction.ia) ...[
              BadgeSignalIa(
                texte: sanction.estPropositionIaNonValidee
                    ? 'Proposition IA — à valider par un humain'
                    : 'Origine IA — validée par un humain',
              ),
              const SizedBox(height: 8),
            ],
            if (peutValider && sanction.estPropositionIaNonValidee)
              FilledButton.icon(
                onPressed: () async {
                  final profil = ref.read(profilProvider).value;
                  if (profil == null) return;
                  await ref
                      .read(vieScolaireRepositoryProvider)
                      .validerSanction(sanction.id, valideePar: profil.id);
                  ref.invalidate(sanctionsDeFicheProvider(sanction.ficheEleveId));
                },
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Valider la proposition'),
              ),
          ],
        ),
      ),
    );
  }
}

class _PastilleStatutSanction extends StatelessWidget {
  const _PastilleStatutSanction({required this.statut});

  final StatutSanction statut;

  @override
  Widget build(BuildContext context) {
    final (couleur, libelle) = switch (statut) {
      StatutSanction.proposee => (context.palette.premium, 'Proposée'),
      StatutSanction.notifiee => (context.palette.accent, 'Notifiée'),
      StatutSanction.executee => (context.palette.primaire, 'Exécutée'),
      StatutSanction.annulee => (context.palette.encreSecondaire, 'Annulée'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(libelle, style: TextStyle(color: couleur, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
