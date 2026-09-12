import 'package:flutter/material.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';

/// Fil d'Ariane (breadcrumb, D1) — réservé aux écrans POUSSÉS (2-3 niveaux
/// réels de l'app, ex. Profil → Sanctions), jamais aux 5 onglets racine de
/// la coquille qui n'ont pas de parent. Format fixe : « Onglet > Écran » ou,
/// quand un contexte existe, « Onglet > Écran — Entité contextuelle ».
///
/// Conçu comme `PreferredSizeWidget` pour un usage direct en
/// `AppBar(bottom: FilAriane(...))`.
class FilAriane extends StatelessWidget implements PreferredSizeWidget {
  const FilAriane({super.key, required this.onglet, required this.ecran, this.contexte});

  final String onglet;
  final String ecran;
  final String? contexte;

  @override
  Size get preferredSize => const Size.fromHeight(28);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      height: preferredSize.height,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text.rich(
        TextSpan(
          style: TextStyle(fontSize: 12, color: palette.encreSecondaire),
          children: [
            TextSpan(text: onglet),
            const TextSpan(text: '   >   '),
            TextSpan(
              text: ecran,
              style: TextStyle(fontWeight: FontWeight.w600, color: palette.encre),
            ),
            if (contexte != null) TextSpan(text: '   —   $contexte'),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
