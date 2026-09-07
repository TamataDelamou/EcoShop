import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/role_racine.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/domain/profil.dart';
import '../application/scolarite_providers.dart';
import '../domain/affectation_enseignant.dart';
import 'ecran_detail_classe.dart';
import 'ecran_fiche_eleve.dart';
import 'ecran_structure_etablissement.dart';

/// Accueil de l'onglet Scolarité — le contenu s'adapte au rôle racine :
/// un parent voit l'enfant actif du sélecteur, un élève sa propre fiche, le
/// personnel l'annuaire de l'établissement (contrat M05, ch. 4).
class EcranScolarite extends ConsumerWidget {
  const EcranScolarite({super.key, required this.profil});

  final Profil? profil;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (profil?.roleRacine) {
      RoleRacine.parent => const _VueParent(),
      RoleRacine.eleve => const _VueEleve(),
      RoleRacine.enseignant => const _VueEnseignant(),
      RoleRacine.direction => const EcranStructureEtablissement(),
      _ => const Center(child: Text('Scolarité indisponible pour ce rôle.')),
    };
  }
}

class _VueParent extends ConsumerWidget {
  const _VueParent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enfant = ref.watch(enfantActifProvider);
    final enfants = ref.watch(mesEnfantsProvider);

    if (enfants.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (enfant == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            "Aucun enfant lié pour l'instant — utilisez le bouton « Ajouter » "
            'en haut de l\'écran.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return EcranFicheEleve(fiche: enfant);
  }
}

class _VueEleve extends ConsumerWidget {
  const _VueEleve();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fiche = ref.watch(maFicheProvider);

    return fiche.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (erreur, _) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Fiche indisponible hors connexion pour le moment.'),
        ),
      ),
      data: (f) => f == null
          ? const Center(child: Text('Aucune fiche liée à ce compte.'))
          : EcranFicheEleve(fiche: f),
    );
  }
}

class _VueEnseignant extends ConsumerWidget {
  const _VueEnseignant();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final affectations = ref.watch(mesAffectationsProvider);

    return affectations.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (erreur, _) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Vos classes sont indisponibles hors connexion pour le moment.'),
        ),
      ),
      data: (liste) => liste.isEmpty
          ? const Center(child: Text("Aucune classe affectée pour l'année en cours."))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Mes classes', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                for (final a in liste) _CarteMaClasse(affectation: a),
              ],
            ),
    );
  }
}

class _CarteMaClasse extends StatelessWidget {
  const _CarteMaClasse({required this.affectation});

  final AffectationEnseignant affectation;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const Icon(Icons.class_outlined, color: AppColors.bleuElectrique),
        title: Text(affectation.nomMatiere ?? 'Matière non précisée'),
        subtitle: Text(affectation.roleAffectation.code),
        trailing: const Icon(Icons.chevron_right),
        onTap: affectation.classe == null
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EcranDetailClasse(classe: affectation.classe!),
                  ),
                ),
      ),
    );
  }
}
