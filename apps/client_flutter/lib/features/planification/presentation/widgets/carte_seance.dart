import 'package:flutter/material.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';

import '../../../../core/widgets/glass_card.dart';
import '../../domain/emploi_du_temps.dart';
import '../../domain/enums_planification.dart';

/// Carte glassmorphic d'une séance d'emploi du temps — réutilisée par les
/// vues classe/enseignant/salle, chacune choisissant la ligne secondaire
/// pertinente via [libelleSecondaire].
class CarteSeance extends StatelessWidget {
  const CarteSeance({super.key, required this.emploi, this.libelleSecondaire});

  final EmploiDuTemps emploi;
  final String? libelleSecondaire;

  @override
  Widget build(BuildContext context) {
    final couleur = _couleurType(context, emploi.type);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        couleurBordure: couleur.withValues(alpha: 0.3),
        padding: const EdgeInsets.all(12),
        enfant: Row(
          children: [
            Container(width: 4, height: 40, color: couleur, margin: const EdgeInsets.only(right: 10)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    emploi.nomMatiere ?? emploi.type.libelle,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (libelleSecondaire != null)
                    Text(
                      libelleSecondaire!,
                      style: TextStyle(color: context.palette.encreSecondaire, fontSize: 12),
                    ),
                ],
              ),
            ),
            Text(
              '${emploi.heureDebut} – ${emploi.heureFin}',
              style: TextStyle(color: couleur, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  static Color _couleurType(BuildContext context, TypeSeance type) => switch (type) {
        TypeSeance.cours => context.palette.primaire,
        TypeSeance.examen => context.palette.erreur,
        TypeSeance.activite => context.palette.succes,
        TypeSeance.etude => context.palette.premium,
        TypeSeance.pause => context.palette.encreSecondaire,
      };
}

/// Libellés des jours de la semaine (1 = lundi … 7 = dimanche).
const joursSemaine = [
  'Lundi',
  'Mardi',
  'Mercredi',
  'Jeudi',
  'Vendredi',
  'Samedi',
  'Dimanche',
];
