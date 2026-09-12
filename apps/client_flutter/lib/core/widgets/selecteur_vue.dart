import 'package:flutter/material.dart';

/// Mode d'affichage d'une collection (D1) — trois vues génériques,
/// réutilisables par n'importe quel écran de liste (D2 les réutilise tel
/// quel pour les cartes profil, sans redessiner ce widget).
enum ModeAffichage { liste, grille, cartes }

/// Sélecteur de mode d'affichage (grille/liste/cartes, D1) — widget
/// générique sans connaissance du contenu affiché : l'écran appelant décide
/// seul comment rendre chaque mode.
class SelecteurVue extends StatelessWidget {
  const SelecteurVue({super.key, required this.mode, required this.onChanged});

  final ModeAffichage mode;
  final ValueChanged<ModeAffichage> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ModeAffichage>(
      segments: const [
        ButtonSegment(
          value: ModeAffichage.liste,
          icon: Icon(Icons.view_list_outlined),
          tooltip: 'Liste',
        ),
        ButtonSegment(
          value: ModeAffichage.grille,
          icon: Icon(Icons.grid_view_outlined),
          tooltip: 'Grille',
        ),
        ButtonSegment(
          value: ModeAffichage.cartes,
          icon: Icon(Icons.view_agenda_outlined),
          tooltip: 'Cartes',
        ),
      ],
      selected: {mode},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}
