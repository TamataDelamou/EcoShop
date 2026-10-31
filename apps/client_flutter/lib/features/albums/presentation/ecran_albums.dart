import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/providers.dart';
import '../../scolarite/application/scolarite_providers.dart';
import '../../scolarite/domain/classe.dart';
import '../data/albums_repository.dart';

/// Albums photo de l'école (REG-39) : mosaïque d'albums, par classe ou pour
/// toute l'école. La direction et les enseignants créent des albums ; les
/// familles et les élèves les regardent.
class EcranAlbums extends ConsumerWidget {
  const EcranAlbums({super.key, required this.etablissementId, this.peutCreer = false});

  final String etablissementId;

  /// Direction ou enseignant : bouton « Nouvel album ».
  final bool peutCreer;

  Future<void> _nouvelAlbum(BuildContext context, WidgetRef ref) async {
    final cree = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FormulaireAlbum(etablissementId: etablissementId),
    );
    if (cree == null || !context.mounted) return;
    ref.invalidate(albumsProvider(etablissementId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumsProvider(etablissementId));
    return Scaffold(
      appBar: AppBar(title: const Text('Albums photo')),
      floatingActionButton: peutCreer
          ? FloatingActionButton.extended(
              key: const Key('bouton_nouvel_album'),
              onPressed: () => _nouvelAlbum(context, ref),
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Nouvel album'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(albumsProvider(etablissementId)),
        child: albums.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(children: const [
            Padding(
              padding: EdgeInsets.all(32),
              child: Text('Albums indisponibles hors connexion pour le moment.', textAlign: TextAlign.center),
            ),
          ]),
          data: (liste) {
            if (liste.isEmpty) {
              return ListView(children: [
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    peutCreer
                        ? 'Aucun album pour le moment. Créez-en un pour une classe ou pour toute l’école.'
                        : 'Aucun album pour le moment.',
                    key: const Key('albums_vides'),
                    textAlign: TextAlign.center,
                  ),
                ),
              ]);
            }
            return LayoutBuilder(builder: (context, contraintes) {
              final colonnes = contraintes.maxWidth >= 720 ? 4 : (contraintes.maxWidth >= 480 ? 3 : 2);
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: colonnes,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.82,
                ),
                itemCount: liste.length,
                itemBuilder: (context, i) => _CarteAlbum(
                  album: liste[i],
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => EcranAlbum(etablissementId: etablissementId, album: liste[i]),
                    ));
                    ref.invalidate(albumsProvider(etablissementId));
                  },
                ),
              );
            });
          },
        ),
      ),
    );
  }
}

class _CarteAlbum extends StatelessWidget {
  const _CarteAlbum({required this.album, required this.onTap});

  final Album album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final schema = Theme.of(context).colorScheme;
    return Material(
      color: schema.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('album_${album.id}'),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: album.couverture == null
                  ? Container(
                      color: schema.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: Icon(Icons.photo_library_outlined, size: 40, color: schema.onSurfaceVariant),
                    )
                  : VignettePhoto(chemin: album.couverture!),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(album.titre, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${album.portee} · ${album.nombrePhotos} photo${album.nombrePhotos > 1 ? 's' : ''}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: schema.onSurfaceVariant)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Photo d'un album, remplie dans son cadre (copie du téléphone d'abord).
class VignettePhoto extends ConsumerWidget {
  const VignettePhoto({super.key, required this.chemin, this.fit = BoxFit.cover});

  final String chemin;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final octets = ref.watch(octetsPhotoAlbumProvider(chemin));
    final schema = Theme.of(context).colorScheme;
    return octets.when(
      loading: () => Container(color: schema.surfaceContainerHighest),
      error: (_, _) => _absente(schema),
      data: (o) => o == null
          ? _absente(schema)
          : Image.memory(o, fit: fit, width: double.infinity, height: double.infinity, gaplessPlayback: true),
    );
  }

  Widget _absente(ColorScheme schema) => Container(
        color: schema.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(Icons.cloud_off_outlined, color: schema.onSurfaceVariant),
      );
}

/// Un album : mosaïque de 3 photos par ligne ; une photo touchée s'ouvre en
/// grand, on glisse pour passer à la suivante.
class EcranAlbum extends ConsumerStatefulWidget {
  const EcranAlbum({super.key, required this.etablissementId, required this.album});

  final String etablissementId;
  final Album album;

  @override
  ConsumerState<EcranAlbum> createState() => _EcranAlbumState();
}

class _EcranAlbumState extends ConsumerState<EcranAlbum> {
  int? _envoi;
  int _total = 0;

  Future<void> _ajouterPhotos() async {
    if (!ref.read(estEnLigneProvider)) {
      _dire('L’ajout de photos demande le réseau. Réessayez une fois connecté.');
      return;
    }
    List<XFile> fichiers;
    try {
      fichiers = await ImagePicker().pickMultiImage(maxWidth: 1600, maxHeight: 1600, imageQuality: 78);
    } catch (_) {
      _dire('Galerie indisponible : vérifiez l’autorisation d’accès aux photos.');
      return;
    }
    if (fichiers.isEmpty) return;
    setState(() {
      _envoi = 0;
      _total = fichiers.length;
    });
    var echecs = 0;
    for (final f in fichiers) {
      try {
        await ref.read(albumsRepositoryProvider).ajouterPhoto(
              etablissementId: widget.etablissementId,
              albumId: widget.album.id,
              octets: await f.readAsBytes(),
            );
      } catch (_) {
        echecs++;
      }
      if (mounted) setState(() => _envoi = (_envoi ?? 0) + 1);
    }
    if (!mounted) return;
    setState(() => _envoi = null);
    ref.invalidate(photosAlbumProvider(widget.album.id));
    _dire(echecs == 0
        ? '${fichiers.length} photo${fichiers.length > 1 ? 's' : ''} ajoutée${fichiers.length > 1 ? 's' : ''}.'
        : '$echecs photo(s) non envoyée(s) : réessayez.');
  }

  Future<void> _retirerAlbum() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Retirer cet album ?'),
        content: const Text('Il ne sera plus visible des familles ni des élèves.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Retirer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(albumsRepositoryProvider).retirerAlbum(widget.album.id);
      if (mounted) Navigator.of(context).pop();
    } on ErreurAlbum catch (e) {
      _dire(e.message);
    }
  }

  void _dire(String texte) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texte)));
  }

  @override
  Widget build(BuildContext context) {
    final photos = ref.watch(photosAlbumProvider(widget.album.id));
    final album = widget.album;
    return Scaffold(
      appBar: AppBar(
        title: Text(album.titre),
        actions: [
          if (album.peutGerer)
            PopupMenuButton<String>(
              onSelected: (v) => v == 'retirer' ? _retirerAlbum() : null,
              itemBuilder: (_) => const [PopupMenuItem(value: 'retirer', child: Text('Retirer l’album'))],
            ),
        ],
      ),
      floatingActionButton: album.peutGerer
          ? FloatingActionButton.extended(
              key: const Key('bouton_ajouter_photos'),
              onPressed: _envoi == null ? _ajouterPhotos : null,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(_envoi == null ? 'Ajouter des photos' : 'Envoi $_envoi / $_total'),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_envoi != null) LinearProgressIndicator(value: _total == 0 ? null : _envoi! / _total),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              [album.portee, if (album.description != null) album.description!].join(' — '),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: photos.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const Center(child: Text('Photos indisponibles hors connexion pour le moment.')),
              data: (liste) => liste.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(album.peutGerer ? 'Album vide : ajoutez vos premières photos.' : 'Album vide pour le moment.',
                            textAlign: TextAlign.center),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 96),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 160,
                        mainAxisSpacing: 4,
                        crossAxisSpacing: 4,
                      ),
                      itemCount: liste.length,
                      itemBuilder: (context, i) => GestureDetector(
                        key: Key('photo_${liste[i].id}'),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => _VisionneusePhotos(album: album, photos: liste, depart: i),
                        )),
                        child: Hero(tag: liste[i].id, child: VignettePhoto(chemin: liste[i].chemin)),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Plein écran : on glisse d'une photo à l'autre, on pince pour agrandir.
class _VisionneusePhotos extends ConsumerStatefulWidget {
  const _VisionneusePhotos({required this.album, required this.photos, required this.depart});

  final Album album;
  final List<PhotoAlbum> photos;
  final int depart;

  @override
  ConsumerState<_VisionneusePhotos> createState() => _VisionneusePhotosState();
}

class _VisionneusePhotosState extends ConsumerState<_VisionneusePhotos> {
  late final PageController _pages = PageController(initialPage: widget.depart);
  late int _index = widget.depart;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _action(String action) async {
    final photo = widget.photos[_index];
    final depot = ref.read(albumsRepositoryProvider);
    try {
      if (action == 'couverture') {
        await depot.definirCouverture(widget.album.id, photo.chemin);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo de couverture choisie.')));
      } else if (action == 'retirer') {
        await depot.retirerPhoto(photo);
        ref.invalidate(photosAlbumProvider(widget.album.id));
        if (mounted) Navigator.of(context).pop();
      }
    } on ErreurAlbum catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} / ${widget.photos.length}'),
        actions: [
          if (widget.album.peutGerer)
            PopupMenuButton<String>(
              onSelected: _action,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'couverture', child: Text('Choisir comme couverture')),
                PopupMenuItem(value: 'retirer', child: Text('Retirer la photo')),
              ],
            ),
        ],
      ),
      body: Stack(children: [
        PageView.builder(
          controller: _pages,
          itemCount: widget.photos.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (_, i) => InteractiveViewer(
            maxScale: 4,
            child: Center(
              child: Hero(
                tag: widget.photos[i].id,
                child: VignettePhoto(chemin: widget.photos[i].chemin, fit: BoxFit.contain),
              ),
            ),
          ),
        ),
        if (photo.legende != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.all(16),
              child: Text(photo.legende!, style: const TextStyle(color: Colors.white)),
            ),
          ),
      ]),
    );
  }
}

/// Nouvel album : titre, classe (ou toute l'école), description.
class _FormulaireAlbum extends ConsumerStatefulWidget {
  const _FormulaireAlbum({required this.etablissementId});

  final String etablissementId;

  @override
  ConsumerState<_FormulaireAlbum> createState() => _FormulaireAlbumState();
}

class _FormulaireAlbumState extends ConsumerState<_FormulaireAlbum> {
  final _titre = TextEditingController();
  final _description = TextEditingController();
  String? _classeId;
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _titre.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _creer() async {
    if (_titre.text.trim().isEmpty) {
      setState(() => _erreur = 'Donnez un titre à l’album (ex. « Fête de fin d’année »).');
      return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final id = await ref.read(albumsRepositoryProvider).creerAlbum(
            etablissementId: widget.etablissementId,
            titre: _titre.text,
            classeId: _classeId,
            description: _description.text,
          );
      if (mounted) Navigator.of(context).pop(id);
    } on ErreurAlbum catch (e) {
      setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final classes = [
      for (final c in ref.watch(structureEtablissementProvider(null)).valueOrNull?.classes ?? const <Classe>[])
        if (c.actif) c,
    ]..sort((a, b) => a.nom.compareTo(b.nom));
    final bas = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bas),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Nouvel album', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            key: const Key('champ_titre_album'),
            controller: _titre,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Titre', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            key: const Key('choix_classe_album'),
            initialValue: _classeId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Pour', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Toute l’école')),
              for (final c in classes) DropdownMenuItem<String?>(value: c.id, child: Text(c.nom)),
            ],
            onChanged: (v) => setState(() => _classeId = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Description (facultatif)', border: OutlineInputBorder()),
          ),
          if (_erreur != null) ...[
            const SizedBox(height: 8),
            Text(_erreur!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('bouton_creer_album'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _enCours ? null : _creer,
            child: const Text('Créer l’album'),
          ),
        ]),
      ),
    );
  }
}
