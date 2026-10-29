import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/role_racine.dart';
import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../application/scolarite_providers.dart';
import '../../domain/fiche_eleve.dart';
import 'ajouter_enfant_sheet.dart';
import '../../../auth/application/espace_providers.dart';

/// Sélecteur d'enfant — composant clé du multi-profils parent (M5).
///
/// Placé en haut de la coquille applicative : le choix qui y est fait
/// (`enfantSelectionneProvider`) aiguille tout le reste de l'application
/// (notes, absences, emploi du temps) une fois ces modules branchés. N'est
/// rendu que pour un compte parent — invisible et sans coût pour les autres
/// rôles.
class SelecteurEnfant extends ConsumerWidget {
  const SelecteurEnfant({super.key, this.avecAjouter = true});

  /// Faux dans l'en-tête de l'accueil, qui porte déjà le bouton « Ajouter »
  /// sur la ligne du nom.
  final bool avecAjouter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(roleUtiliseProvider);
    if (role != RoleRacine.parent) return const SizedBox.shrink();

    final enfants = ref.watch(mesEnfantsProvider);

    return enfants.when(
      loading: () => const _RubanChargement(),
      error: (_, _) => const SizedBox.shrink(),
      // Enfants de l'école de l'espace parent utilisé (REG-32).
      data: (_) {
        final fiches = ref
            .watch(enfantsEspaceProvider)
            .where((r) => r.estActive)
            .map((r) => r.fiche)
            .whereType<FicheEleve>()
            .toList(growable: false);
        final actif = ref.watch(enfantActifProvider);
        if (!avecAjouter && fiches.isEmpty) return const SizedBox.shrink();

        return Container(
          height: 88,
          color: context.palette.surface,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            children: [
              for (final fiche in fiches)
                _PuceEnfant(
                  fiche: fiche,
                  selectionne: actif?.id == fiche.id,
                  onTap: () =>
                      ref.read(enfantSelectionneProvider.notifier).state = fiche,
                ),
              if (avecAjouter) _PuceAjouter(onTap: () => afficherAjouterEnfant(context, ref)),
            ],
          ),
        );
      },
    );
  }
}

class _RubanChargement extends StatelessWidget {
  const _RubanChargement();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 88,
      child: Center(
        child: SizedBox(
          height: 18,
          width: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _PuceEnfant extends StatelessWidget {
  const _PuceEnfant({
    required this.fiche,
    required this.selectionne,
    required this.onTap,
  });

  final FicheEleve fiche;
  final bool selectionne;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          width: 68,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selectionne ? context.palette.primaire : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: selectionne
                      ? context.palette.primaire
                      : context.palette.primaire.withValues(alpha: 0.12),
                  child: Text(
                    _initiales(fiche.nomComplet),
                    style: TextStyle(
                      color: selectionne ? Colors.white : context.palette.primaire,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                fiche.prenom,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selectionne ? FontWeight.w700 : FontWeight.w400,
                  color: selectionne ? context.palette.primaire : context.palette.encreSecondaire,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _initiales(String nom) {
    final mots = nom.trim().split(RegExp(r'\s+')).where((m) => m.isNotEmpty).take(2);
    if (mots.isEmpty) return '?';
    return mots.map((m) => m.substring(0, 1)).join().toUpperCase();
  }
}

class _PuceAjouter extends StatelessWidget {
  const _PuceAjouter({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 68,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
            child: CircleAvatar(
              radius: 22,
              backgroundColor: context.palette.accent.withValues(alpha: 0.12),
              child: Icon(Icons.add, color: context.palette.accent),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Ajouter',
            maxLines: 1,
            style: TextStyle(fontSize: 12, color: context.palette.encreSecondaire),
          ),
        ],
      ),
    );
  }
}
