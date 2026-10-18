import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_palette.dart';
import '../../domain/inscription_en_ligne.dart';

/// Une pièce du dossier : photo prise sur le moment ou choisie dans la
/// galerie, compressée pour partir même sur un réseau faible.
class PrisePiece extends StatelessWidget {
  const PrisePiece({
    super.key,
    required this.piece,
    required this.prise,
    required this.onPrise,
    this.enAttenteEnvoi = false,
    this.onOuvrir,
  });

  final PieceRequise piece;

  /// Déjà fournie (sur le téléphone ou à l'école).
  final bool prise;

  /// Fournie mais encore sur le téléphone.
  final bool enAttenteEnvoi;
  final void Function(PieceAEnvoyer piece)? onPrise;

  /// Ouvrir la pièce déposée (Direction, famille).
  final VoidCallback? onOuvrir;

  Future<void> _prendre(BuildContext context, ImageSource source) async {
    XFile? photo;
    try {
      photo = await ImagePicker().pickImage(source: source, imageQuality: 70, maxWidth: 1600, maxHeight: 1600);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible d'accéder à l'appareil photo ou à la galerie.")),
      );
      return;
    }
    if (photo == null) return;
    final octets = await photo.readAsBytes();
    final nom = photo.name.toLowerCase();
    final extension = nom.endsWith('.png') ? 'png' : nom.endsWith('.webp') ? 'webp' : 'jpg';
    onPrise?.call(PieceAEnvoyer(code: piece.code, octets: octets, extension: extension));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final couleur = prise ? palette.succes : (piece.obligatoire ? palette.accent : palette.encreSecondaire);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Icon(prise ? Icons.check_circle : Icons.description_outlined, color: couleur),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(piece.libelle, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    prise
                        ? (enAttenteEnvoi ? "Sur ce téléphone — envoi au retour du réseau" : 'Fournie')
                        : (piece.obligatoire ? 'Obligatoire' : 'Facultative'),
                    style: TextStyle(color: couleur, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (onOuvrir != null && prise && !enAttenteEnvoi)
              IconButton(tooltip: 'Ouvrir', onPressed: onOuvrir, icon: const Icon(Icons.visibility_outlined)),
            if (onPrise != null) ...[
              IconButton(
                key: Key('photo_${piece.code}'),
                tooltip: 'Prendre une photo',
                onPressed: () => _prendre(context, ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
              ),
              IconButton(
                tooltip: 'Choisir dans la galerie',
                onPressed: () => _prendre(context, ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
