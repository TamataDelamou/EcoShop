import 'package:flutter/material.dart';

/// Bouton « Continuer avec Google », selon les règles de présentation de
/// Google (developers.google.com/identity/branding-guidelines) :
///
/// - logo « G » officiel, extrait sans retouche du kit de Google
///   (`signin-assets.zip`, Android + Web, thème clair) : jamais redessiné,
///   recoloré ni redimensionné hors des tailles du kit ;
/// - thème clair : fond #FFFFFF, contour #747775 de 1 px, texte #1F1F1F,
///   graisse Medium, 14/20 ; il reste lisible sur un fond clair ou sombre ;
/// - 12 px à gauche du logo, 10 px entre le logo et le texte, 12 px à
///   droite du texte ; forme pilule ;
/// - libellé « Continuer avec Google » (traduction permise de « Continue
///   with Google »).
class BoutonGoogle extends StatelessWidget {
  const BoutonGoogle({super.key, required this.onPressed, this.enCours = false});

  /// Null : bouton désactivé.
  final VoidCallback? onPressed;

  /// Connexion en cours : le bouton est désactivé, le libellé reste.
  final bool enCours;

  static const logo = 'assets/images/google_g.png';
  static const _fond = Color(0xFFFFFFFF);
  static const _contour = Color(0xFF747775);
  static const _texte = Color(0xFF1F1F1F);
  static const _hauteur = 40.0;
  static const _tailleLogo = 20.0;

  @override
  Widget build(BuildContext context) {
    final actif = onPressed != null && !enCours;
    return Semantics(
      button: true,
      enabled: actif,
      label: 'Continuer avec Google',
      excludeSemantics: true,
      child: Opacity(
        // Désactivé : même dessin, estompé (le logo garde ses couleurs).
        opacity: actif ? 1 : 0.6,
        child: Material(
          color: _fond,
          shape: const StadiumBorder(
            side: BorderSide(color: _contour, width: 1, strokeAlign: BorderSide.strokeAlignInside),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: actif ? onPressed : null,
            child: SizedBox(
              height: _hauteur,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Positioned(
                    left: 12,
                    child: Image(
                      image: AssetImage(logo),
                      width: _tailleLogo,
                      height: _tailleLogo,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 12 + _tailleLogo + 10, right: 12),
                    child: Text(
                      'Continuer avec Google',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _texte,
                        fontSize: 14,
                        height: 20 / 14,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.25,
                      ),
                      textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
