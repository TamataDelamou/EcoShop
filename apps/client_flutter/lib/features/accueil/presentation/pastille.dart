import 'package:flutter/material.dart';

import '../domain/fonction.dart';

/// Pastille de l'accueil (maquettes REG-21) : carte blanche à bords arrondis
/// (18), icône dans un carré coloré (44, rayon 14), libellé de deux lignes au
/// plus, badge orange. Vrai bouton, zone de toucher ≥ 96 × 96, libellé lu par
/// TalkBack avec le badge (« Annonces, 3 nouvelles »).
class Pastille extends StatelessWidget {
  const Pastille({super.key, required this.fonction, required this.onTap, this.badge = 0});

  final Fonction fonction;
  final VoidCallback onTap;
  final int badge;

  static String libelleAccessible(Fonction f, int badge) {
    if (badge <= 0) return f.libelle;
    final pluriel = badge > 1 ? 's' : '';
    return '${f.libelle}, $badge ${f.libelleBadge}$pluriel';
  }

  @override
  Widget build(BuildContext context) {
    final sombre = Theme.of(context).brightness == Brightness.dark;
    final schema = Theme.of(context).colorScheme;
    final t = fonction.teinte;
    return Semantics(
      button: true,
      label: libelleAccessible(fonction, badge),
      excludeSemantics: true,
      child: Material(
        color: sombre ? schema.surfaceContainerHigh : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: sombre ? schema.outlineVariant : const Color(0xFFE3E7E2)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('pastille_${fonction.id}'),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 96),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 14, 6, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: sombre ? t.fondSombre : t.fondClair,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(fonction.icone, color: sombre ? t.iconeSombre : t.iconeClair, size: 24),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        fonction.libelle,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.2),
                      ),
                    ],
                  ),
                ),
                if (badge > 0)
                  Positioned(
                    top: 8,
                    right: 10,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 20),
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(color: const Color(0xFFB9480F), borderRadius: BorderRadius.circular(10)),
                      alignment: Alignment.center,
                      child: Text(
                        badge > 99 ? '99+' : '$badge',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Grille de 3 colonnes (maquettes : écart 10).
class GrillePastilles extends StatelessWidget {
  const GrillePastilles({super.key, required this.enfants});

  final List<Widget> enfants;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, contraintes) {
      // Trois colonnes sur téléphone ; plus sur tablette et ordinateur.
      final colonnes = contraintes.maxWidth >= 720 ? 6 : (contraintes.maxWidth >= 480 ? 4 : 3);
      final largeur = (contraintes.maxWidth - 10 * (colonnes - 1)) / colonnes;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [for (final e in enfants) SizedBox(width: largeur, child: e)],
      );
    });
  }
}

/// Titre de section (majuscules, gris, 14 px gras).
class TitreSection extends StatelessWidget {
  const TitreSection(this.texte, {super.key, this.action});

  final String texte;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final couleur = Theme.of(context).brightness == Brightness.dark
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : const Color(0xFF4A5551);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 12),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(texte.toUpperCase(),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: couleur, letterSpacing: 0.6)),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
