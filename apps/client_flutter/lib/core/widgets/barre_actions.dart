import 'package:flutter/material.dart';

/// Une action d'écran, affichée avec son libellé (REG-28).
class ActionEcran {
  const ActionEcran({required this.icone, required this.libelle, required this.onPressed, this.cle, this.principale = false});

  final IconData icone;
  final String libelle;

  /// Null : action grisée (hors connexion, données pas encore chargées…).
  final VoidCallback? onPressed;
  final Key? cle;

  /// Action la plus utilisée de l'écran : bouton plein, en premier.
  final bool principale;
}

/// Actions d'un écran, sous la barre de titre (REG-28).
///
/// Une icône seule dans la barre de titre se repère mal : on ne sait ni
/// qu'elle existe ni ce qu'elle fait sans un appui long. Les actions qui
/// ouvrent une fonction de l'écran sont donc posées ici, chacune avec son
/// libellé, en une rangée qui défile horizontalement si elle déborde. La
/// barre de titre ne garde que le retour, le titre et, au plus, une icône
/// universelle (panier, menu « Plus »).
///
/// À placer dans `AppBar.bottom` ; [sousBarre] reçoit les onglets de
/// l'écran quand il en a.
class BarreActions extends StatelessWidget implements PreferredSizeWidget {
  const BarreActions({super.key, required this.actions, this.sousBarre});

  final List<ActionEcran> actions;
  final PreferredSizeWidget? sousBarre;

  static const double _hauteur = 52;

  @override
  Size get preferredSize => Size.fromHeight((actions.isEmpty ? 0 : _hauteur) + (sousBarre?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final rangee = actions.isEmpty
        ? null
        : SizedBox(
            height: _hauteur,
            child: ListView.separated(
              key: const Key('barre_actions'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              itemCount: actions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => _Bouton(action: actions[i]),
            ),
          );
    if (sousBarre == null) return rangee ?? const SizedBox.shrink();
    return Column(mainAxisSize: MainAxisSize.min, children: [?rangee, sousBarre!]);
  }
}

/// Mêmes actions, en tête d'une liste (écrans sans `AppBar.bottom` libre).
class RangeeActions extends StatelessWidget {
  const RangeeActions({super.key, required this.actions, this.padding = const EdgeInsets.only(bottom: 12)});

  final List<ActionEcran> actions;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final a in actions) _Bouton(action: a)],
      ),
    );
  }
}

class _Bouton extends StatelessWidget {
  const _Bouton({required this.action});

  final ActionEcran action;

  @override
  Widget build(BuildContext context) {
    const forme = EdgeInsets.symmetric(horizontal: 14);
    final icone = Icon(action.icone, size: 18);
    final libelle = Text(action.libelle);
    return action.principale
        ? FilledButton.icon(
            key: action.cle,
            onPressed: action.onPressed,
            icon: icone,
            label: libelle,
            style: FilledButton.styleFrom(padding: forme),
          )
        : FilledButton.tonalIcon(
            key: action.cle,
            onPressed: action.onPressed,
            icon: icone,
            label: libelle,
            style: FilledButton.styleFrom(padding: forme),
          );
  }
}
