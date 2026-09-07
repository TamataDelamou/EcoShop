import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Carte « glassmorphism » — flou d'arrière-plan léger, bordure fine
/// lumineuse et ombre douce (charte ch. 2). Réservée aux surfaces posées sur
/// un fond illustré ou dégradé ; sur fond uni, [Card] du thème Material
/// suffit et coûte moins cher à recomposer.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.enfant,
    this.padding = const EdgeInsets.all(16),
    this.rayon = 20,
    this.couleurBordure,
  });

  final Widget enfant;
  final EdgeInsetsGeometry padding;
  final double rayon;
  final Color? couleurBordure;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(rayon),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(rayon),
            border: Border.all(
              color: couleurBordure ?? AppColors.bleuElectrique.withValues(alpha: 0.18),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.encre.withValues(alpha: 0.06),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: enfant,
        ),
      ),
    );
  }
}
