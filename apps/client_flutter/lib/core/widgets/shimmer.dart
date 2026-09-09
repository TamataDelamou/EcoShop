import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// Loader squelette « Shimmer » — balayage lumineux en boucle sur une forme
/// neutre, le temps qu'une lecture réseau ou cache se résolve (charte ch. 2 —
/// micro-animations). Ne dépend d'aucun paquet tiers : un simple
/// [ShaderMask] animé suffit et évite d'alourdir le bundle pour un effet
/// purement décoratif.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.enfant});

  final Widget enfant;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controleur = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controleur,
      builder: (context, _) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) {
            final decalage = _controleur.value * 2 - 1; // -1 → 1
            return LinearGradient(
              begin: Alignment(decalage - 1, 0),
              end: Alignment(decalage, 0),
              colors: const [
                Color(0xFFE2E8F0),
                Color(0xFFF8FAFC),
                Color(0xFFE2E8F0),
              ],
              stops: const [0.35, 0.5, 0.65],
            ).createShader(rect);
          },
          child: widget.enfant,
        );
      },
    );
  }
}

/// Bloc rectangulaire arrondi utilisé comme squelette de contenu.
class ShimmerBloc extends StatelessWidget {
  const ShimmerBloc({
    super.key,
    this.hauteur = 16,
    this.largeur = double.infinity,
    this.rayon = 8,
  });

  final double hauteur;
  final double largeur;
  final double rayon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: hauteur,
      width: largeur,
      decoration: BoxDecoration(
        color: context.palette.bordure,
        borderRadius: BorderRadius.circular(rayon),
      ),
    );
  }
}

/// Squelette de carte (avatar + deux lignes de texte), pour les listes en
/// cours de chargement.
class ShimmerCarteListe extends StatelessWidget {
  const ShimmerCarteListe({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Shimmer(
      enfant: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.bordure),
        ),
        child: Row(
          children: [
            CircleAvatar(radius: 20, backgroundColor: palette.bordure),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  ShimmerBloc(hauteur: 14, largeur: 140),
                  SizedBox(height: 8),
                  ShimmerBloc(hauteur: 10, largeur: 90),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
