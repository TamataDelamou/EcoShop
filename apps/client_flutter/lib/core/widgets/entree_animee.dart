import 'package:flutter/material.dart';

/// Anime l'entrée d'un élément de liste (fondu + léger glissement vertical),
/// décalée par [index] pour un effet d'apparition en cascade (charte ch. 2).
class EntreeAnimee extends StatelessWidget {
  const EntreeAnimee({super.key, required this.index, required this.enfant});

  final int index;
  final Widget enfant;

  static const _delaiParElement = Duration(milliseconds: 40);
  static const _duree = Duration(milliseconds: 320);

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: _duree + _delaiParElement * index,
      curve: Curves.easeOutCubic,
      builder: (context, valeur, enfant) {
        return Opacity(
          opacity: valeur,
          child: Transform.translate(
            offset: Offset(0, (1 - valeur) * 16),
            child: enfant,
          ),
        );
      },
      child: enfant,
    );
  }
}
