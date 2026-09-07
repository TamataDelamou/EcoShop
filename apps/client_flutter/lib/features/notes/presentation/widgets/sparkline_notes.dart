import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Mini-graphique d'évolution des notes d'une matière (charte ch. 2 —
/// indicateurs visuels de performance). Pas de dépendance graphique tierce :
/// un simple [CustomPainter] suffit pour une poignée de points.
class SparklineNotes extends StatelessWidget {
  const SparklineNotes({super.key, required this.valeursSur20, this.hauteur = 48});

  final List<double> valeursSur20;
  final double hauteur;

  @override
  Widget build(BuildContext context) {
    if (valeursSur20.length < 2) {
      return SizedBox(
        height: hauteur,
        child: Center(
          child: Text(
            valeursSur20.isEmpty ? 'Pas encore de note' : '${valeursSur20.single.toStringAsFixed(1)}/20',
            style: const TextStyle(color: AppColors.encreSecondaire, fontSize: 12),
          ),
        ),
      );
    }

    return SizedBox(
      height: hauteur,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(valeursSur20),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.valeurs);

  final List<double> valeurs;

  @override
  void paint(Canvas canvas, Size size) {
    final trait = Paint()
      ..color = AppColors.bleuElectrique
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final point = Paint()..color = AppColors.bleuElectrique;
    final pointReussite = Paint()..color = AppColors.vertMenthe;

    final dx = size.width / (valeurs.length - 1);
    final chemin = Path();

    for (var i = 0; i < valeurs.length; i++) {
      final x = dx * i;
      final y = size.height - (valeurs[i].clamp(0, 20) / 20) * size.height;
      if (i == 0) {
        chemin.moveTo(x, y);
      } else {
        chemin.lineTo(x, y);
      }
    }
    canvas.drawPath(chemin, trait);

    for (var i = 0; i < valeurs.length; i++) {
      final x = dx * i;
      final y = size.height - (valeurs[i].clamp(0, 20) / 20) * size.height;
      canvas.drawCircle(Offset(x, y), 3.5, valeurs[i] >= 10 ? pointReussite : point);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) => oldDelegate.valeurs != valeurs;
}
