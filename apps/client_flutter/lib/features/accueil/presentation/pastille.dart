import 'package:flutter/material.dart';

import '../domain/fonction.dart';

/// Pastille de l'accueil (maquettes REG-21) : carte blanche à bords arrondis
/// (18), icône dans un carré coloré (44, rayon 14), libellé de deux lignes au
/// plus, badge orange. Vrai bouton, zone de toucher ≥ 96 × 96, libellé lu par
/// TalkBack avec le badge (« Annonces, 3 nouvelles »).
class Pastille extends StatelessWidget {
  const Pastille({super.key, required this.fonction, required this.onTap, this.badge = 0, this.grande = false});

  final Fonction fonction;
  final VoidCallback onTap;
  final int badge;

  /// Deux pastilles par ligne (REG-25) : icône et libellé plus grands.
  final bool grande;

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
            constraints: BoxConstraints(minHeight: grande ? 116 : 96),
            child: Stack(
              children: [
                // Toute la largeur, contenu aligné à gauche : l'icône était
                // centrée quand le libellé remplissait la ligne et à gauche
                // quand il était court (retour du porteur de projet,
                // 2026-10-31).
                SizedBox(
                  width: double.infinity,
                  child: Padding(
                  padding: grande ? const EdgeInsets.fromLTRB(14, 16, 10, 14) : const EdgeInsets.fromLTRB(12, 14, 8, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: grande ? 56 : 44,
                        height: grande ? 56 : 44,
                        decoration: BoxDecoration(
                          color: sombre ? t.fondSombre : t.fondClair,
                          borderRadius: BorderRadius.circular(grande ? 18 : 14),
                        ),
                        child: Icon(fonction.icone, color: sombre ? t.iconeSombre : t.iconeClair, size: grande ? 30 : 24),
                      ),
                      SizedBox(height: grande ? 10 : 8),
                      Text(
                        fonction.libelle,
                        textAlign: TextAlign.start,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: grande ? 15 : 13, fontWeight: FontWeight.w600, height: 1.2),
                      ),
                    ],
                  ),
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

/// Pastilles d'une section (maquettes : écart 10), selon l'affichage choisi
/// (REG-25) :
/// - **défilante** : grille de 2 ou 3 colonnes sur un téléphone (plus sur
///   tablette et ordinateur), la page défile de haut en bas ;
/// - **fixe** : une seule ligne qu'on fait glisser de côté ; la pastille
///   suivante dépasse un peu pour montrer qu'il y en a d'autres.
class GrillePastilles extends StatelessWidget {
  const GrillePastilles({super.key, required this.enfants, this.colonnes = 3, this.fixe = false});

  final List<Widget> enfants;

  /// Pastilles par ligne sur un téléphone : 2 ou 3.
  final int colonnes;
  final bool fixe;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, contraintes) {
      final large = contraintes.maxWidth;
      final parLigne = large >= 720 ? colonnes * 2 : (large >= 480 ? colonnes + 1 : colonnes);
      if (fixe) {
        // Hauteur réservée : deux lignes de libellé, texte agrandi compris.
        final echelle = MediaQuery.textScalerOf(context).scale(14) / 14;
        final hauteur = (colonnes == 2 ? 132.0 : 112.0) + 34 * (echelle - 1);
        final largeur = (large - 10 * parLigne) / (parLigne + 0.35);
        return SizedBox(
          height: hauteur,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: enfants.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) => SizedBox(width: largeur, child: enfants[i]),
          ),
        );
      }
      final largeur = (large - 10 * (parLigne - 1)) / parLigne;
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
