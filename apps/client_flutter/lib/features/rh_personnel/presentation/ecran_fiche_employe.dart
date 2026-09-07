import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/role_racine.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/shimmer.dart';
import '../../auth/application/auth_providers.dart';
import '../../scolarite/application/scolarite_providers.dart';
import '../application/rh_providers.dart';
import '../domain/employe.dart';
import '../domain/enums_rh.dart';
import 'ecran_absences_personnel.dart';
import 'ecran_conges.dart';
import 'ecran_contrats.dart';
import 'ecran_paie.dart';
import 'widgets/badge_signal_ia.dart';
import 'widgets/pastille_statut_employe.dart';

/// Fiche employé (M8) — infos, contrat en cours, charge horaire, et pour la
/// RH/direction : signaux IA (risque de turn-over, recommandation de
/// formation), toujours présentés comme des signaux à valider humainement.
class EcranFicheEmploye extends ConsumerWidget {
  const EcranFicheEmploye({super.key, required this.employe});

  final Employe employe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profil = ref.watch(profilProvider).value;
    final estRh = profil?.roleRacine == RoleRacine.direction;
    final estSoiMeme = profil != null && profil.id == employe.profileId;

    final contrats = ref.watch(contratsDeEmployeProvider(employe.id));
    final chargeHoraire = ref.watch(chargeHoraireProvider(employe.id));

    return Scaffold(
      appBar: AppBar(title: Text(employe.nomAffiche ?? employe.matricule)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(employe.nomAffiche ?? employe.matricule,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                      ),
                      PastilleStatutEmploye(statut: employe.statut),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Matricule : ${employe.matricule}'),
                  Text('Catégorie : ${employe.categorie.libelle}'),
                  Text('Embauché le ${_formatDate(employe.dateEmbauche)}'),
                  const SizedBox(height: 12),
                  chargeHoraire.when(
                    loading: () => const ShimmerBloc(hauteur: 14, largeur: 160),
                    error: (erreur, _) => const SizedBox.shrink(),
                    data: (heures) => Text(
                      'Charge horaire hebdomadaire : $heures h',
                      style: const TextStyle(color: AppColors.encreSecondaire),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          contrats.when(
            loading: () => const ShimmerCarteListe(),
            error: (erreur, _) => const SizedBox.shrink(),
            data: (liste) {
              final actuel = liste.where((c) => c.estEnCours).toList();
              if (actuel.isEmpty) return const SizedBox.shrink();
              final contrat = actuel.first;
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.description_outlined, color: AppColors.bleuElectrique),
                  title: Text('Contrat en cours — ${contrat.type.libelle}'),
                  subtitle: Text(
                    contrat.dateFin == null
                        ? 'Depuis le ${_formatDate(contrat.dateDebut)}'
                        : 'Du ${_formatDate(contrat.dateDebut)} au ${_formatDate(contrat.dateFin!)}',
                  ),
                ),
              );
            },
          ),
          if (estRh) ...[
            const SizedBox(height: 16),
            _CarteScoreTurnover(employeId: employe.id),
            if (employe.categorie == CategorieEmploye.enseignant) ...[
              const SizedBox(height: 16),
              _CarteRecommandationFormation(employeId: employe.id),
            ],
          ],
          const SizedBox(height: 24),
          Text('Dossier', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _LienDossier(
            icone: Icons.description_outlined,
            libelle: 'Contrats',
            visible: estRh,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EcranContrats(employe: employe)),
            ),
          ),
          _LienDossier(
            icone: Icons.beach_access_outlined,
            libelle: 'Congés',
            visible: estRh || estSoiMeme,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EcranConges(employe: employe, estRh: estRh)),
            ),
          ),
          _LienDossier(
            icone: Icons.event_busy_outlined,
            libelle: 'Absences',
            visible: estRh || estSoiMeme,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EcranAbsencesPersonnel(employe: employe, estRh: estRh)),
            ),
          ),
          _LienDossier(
            icone: Icons.payments_outlined,
            libelle: 'Paie',
            visible: estRh || estSoiMeme,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EcranPaie(employe: employe)),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _LienDossier extends StatelessWidget {
  const _LienDossier({
    required this.icone,
    required this.libelle,
    required this.visible,
    required this.onTap,
  });

  final IconData icone;
  final String libelle;
  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icone, color: AppColors.bleuElectrique),
        title: Text(libelle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _CarteScoreTurnover extends ConsumerWidget {
  const _CarteScoreTurnover({required this.employeId});

  final String employeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final score = ref.watch(scoreTurnoverProvider(employeId));

    return score.when(
      loading: () => const ShimmerCarteListe(),
      error: (erreur, _) => const SizedBox.shrink(),
      data: (valeur) {
        final couleur = valeur >= 0.7
            ? AppColors.erreur
            : (valeur >= 0.4 ? AppColors.orangePop : AppColors.vertMenthe);
        return GlassCard(
          couleurBordure: couleur.withValues(alpha: 0.3),
          enfant: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Risque de turn-over', style: Theme.of(context).textTheme.titleMedium),
                  ),
                  Text(
                    '${(valeur * 100).toStringAsFixed(0)} %',
                    style: TextStyle(color: couleur, fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const BadgeSignalIa(texte: 'Signal IA — jamais un motif de décision seul'),
            ],
          ),
        );
      },
    );
  }
}

class _CarteRecommandationFormation extends ConsumerWidget {
  const _CarteRecommandationFormation({required this.employeId});

  final String employeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final structure = ref.watch(structureEtablissementProvider(null));

    return structure.when(
      loading: () => const SizedBox.shrink(),
      error: (erreur, _) => const SizedBox.shrink(),
      data: (donnees) {
        final anneeId = donnees?.anneeCourante?.id;
        if (anneeId == null) return const SizedBox.shrink();
        return _Recommandations(employeId: employeId, anneeId: anneeId);
      },
    );
  }
}

class _Recommandations extends ConsumerWidget {
  const _Recommandations({required this.employeId, required this.anneeId});

  final String employeId;
  final String anneeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recommandations = ref.watch(recommanderFormationProvider((employeId: employeId, anneeId: anneeId)));

    return recommandations.when(
      loading: () => const ShimmerCarteListe(),
      error: (erreur, _) => const SizedBox.shrink(),
      data: (liste) {
        if (liste.isEmpty) return const SizedBox.shrink();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Formations recommandées', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                const BadgeSignalIa(texte: 'Signal IA — décision RH/direction'),
                const SizedBox(height: 8),
                for (final r in liste)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text('${r.code} — ${r.libelle}'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
