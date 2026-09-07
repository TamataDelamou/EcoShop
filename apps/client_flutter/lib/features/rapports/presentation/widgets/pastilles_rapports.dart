import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/enums_rapports.dart';

/// Pastille générique — factorise l'apparence commune à toutes les pastilles
/// de statut/sévérité/priorité de M10.
class _Pastille extends StatelessWidget {
  const _Pastille({required this.libelle, required this.couleur});

  final String libelle;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
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

class PastilleStatutRapport extends StatelessWidget {
  const PastilleStatutRapport({super.key, required this.statut});

  final StatutRapport statut;

  @override
  Widget build(BuildContext context) {
    final couleur = switch (statut) {
      StatutRapport.demande => AppColors.dore,
      StatutRapport.enAttente => AppColors.orangePop,
      StatutRapport.genere => AppColors.vertMenthe,
      StatutRapport.echec => AppColors.erreur,
      StatutRapport.expire => AppColors.encreSecondaire,
    };
    return _Pastille(libelle: statut.libelle, couleur: couleur);
  }
}

class PastilleSeverite extends StatelessWidget {
  const PastilleSeverite({super.key, required this.severite});

  final String severite;

  @override
  Widget build(BuildContext context) {
    final couleur = switch (severite) {
      'elevee' => AppColors.erreur,
      'moyenne' => AppColors.orangePop,
      _ => AppColors.encreSecondaire,
    };
    return _Pastille(libelle: severite, couleur: couleur);
  }
}

class PastilleStatutAnomalie extends StatelessWidget {
  const PastilleStatutAnomalie({super.key, required this.statut});

  final StatutAnomalie statut;

  @override
  Widget build(BuildContext context) {
    final couleur = switch (statut) {
      StatutAnomalie.ouverte => AppColors.dore,
      StatutAnomalie.confirmee => AppColors.orangePop,
      StatutAnomalie.rejetee => AppColors.encreSecondaire,
      StatutAnomalie.traitee => AppColors.vertMenthe,
    };
    return _Pastille(libelle: statut.libelle, couleur: couleur);
  }
}

class PastillePriorite extends StatelessWidget {
  const PastillePriorite({super.key, required this.priorite});

  final String priorite;

  @override
  Widget build(BuildContext context) {
    final couleur = switch (priorite) {
      'haute' => AppColors.erreur,
      'moyenne' => AppColors.orangePop,
      _ => AppColors.encreSecondaire,
    };
    return _Pastille(libelle: priorite, couleur: couleur);
  }
}

class PastilleStatutRecommandation extends StatelessWidget {
  const PastilleStatutRecommandation({super.key, required this.statut});

  final StatutRecommandation statut;

  @override
  Widget build(BuildContext context) {
    final couleur = switch (statut) {
      StatutRecommandation.proposee => AppColors.dore,
      StatutRecommandation.validee => AppColors.bleuElectrique,
      StatutRecommandation.miseEnOeuvre => AppColors.vertMenthe,
      StatutRecommandation.rejetee => AppColors.encreSecondaire,
    };
    return _Pastille(libelle: statut.libelle, couleur: couleur);
  }
}
