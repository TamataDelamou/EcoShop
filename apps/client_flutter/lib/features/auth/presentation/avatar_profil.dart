import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../application/photo_profil_providers.dart';
import '../domain/profil.dart';

/// Initiales d'un nom (« Achille Delamou » → « AD »).
String initialesNom(String nom) {
  final mots = nom.trim().split(RegExp(r'\s+')).where((m) => m.isNotEmpty).toList();
  if (mots.isEmpty) return '?';
  if (mots.length == 1) return mots.first.substring(0, 1).toUpperCase();
  return (mots.first.substring(0, 1) + mots[1].substring(0, 1)).toUpperCase();
}

/// Photo de profil (REG-23), ou les initiales tant qu'il n'y en a pas (ou
/// hors connexion si elle n'a jamais été vue sur ce téléphone).
class AvatarProfil extends ConsumerWidget {
  const AvatarProfil({super.key, required this.nom, this.photoChemin, this.rayon = 20});

  factory AvatarProfil.duProfil(Profil profil, {Key? key, double rayon = 20}) =>
      AvatarProfil(key: key, nom: profil.nomAffiche, photoChemin: profil.photoChemin, rayon: rayon);

  final String nom;
  final String? photoChemin;
  final double rayon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chemin = photoChemin;
    final octets = chemin == null ? null : ref.watch(photoProfilProvider(chemin)).valueOrNull;
    return CircleAvatar(
      radius: rayon,
      backgroundImage: octets == null ? null : MemoryImage(octets),
      child: octets != null
          ? null
          : Text(
              initialesNom(nom),
              style: TextStyle(fontSize: rayon * 0.75, fontWeight: FontWeight.w700),
            ),
    );
  }
}

/// Avatar modifiable de « Mon profil » : toucher pour prendre une photo,
/// en choisir une, ou la retirer. Nécessite une connexion (envoi).
class AvatarProfilModifiable extends ConsumerStatefulWidget {
  const AvatarProfilModifiable({super.key, required this.profil});

  final Profil profil;

  @override
  ConsumerState<AvatarProfilModifiable> createState() => _AvatarProfilModifiableState();
}

class _AvatarProfilModifiableState extends ConsumerState<AvatarProfilModifiable> {
  bool _enCours = false;

  Future<void> _choisir() async {
    final aPhoto = widget.profil.photoChemin != null;
    final choix = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('photo_prendre'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.of(ctx).pop('camera'),
            ),
            ListTile(
              key: const Key('photo_galerie'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.of(ctx).pop('galerie'),
            ),
            if (aPhoto)
              ListTile(
                key: const Key('photo_retirer'),
                leading: const Icon(Icons.delete_outline),
                title: const Text('Retirer la photo'),
                onTap: () => Navigator.of(ctx).pop('retirer'),
              ),
          ],
        ),
      ),
    );
    if (choix == null || !mounted) return;
    ImageProfil? image;
    if (choix != 'retirer') {
      try {
        image = await ref.read(selecteurPhotoProfilProvider)(choix == 'camera' ? ImageSource.camera : ImageSource.gallery);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Impossible d’ouvrir l’appareil photo : autorisez-le dans les réglages du téléphone, ou choisissez une image de la galerie.'),
          ));
        }
        return;
      }
      if (image == null || !mounted) return;
    }
    setState(() => _enCours = true);
    try {
      await changerPhotoProfil(ref, profilId: widget.profil.id, image: image);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(image == null ? 'Photo retirée.' : 'Photo de profil enregistrée.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is ErreurPhotoProfil ? e.message : 'Pas de connexion : la photo sera à renvoyer une fois en ligne.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final schema = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Changer ma photo de profil',
      child: InkWell(
        key: const Key('avatar_modifiable'),
        customBorder: const CircleBorder(),
        onTap: _enCours ? null : _choisir,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AvatarProfil.duProfil(widget.profil, rayon: 32),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(color: schema.primary, shape: BoxShape.circle,
                    border: Border.all(color: schema.surface, width: 2)),
                child: _enCours
                    ? SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: schema.onPrimary))
                    : Icon(Icons.photo_camera, size: 12, color: schema.onPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
