import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/widgets/choisir_date.dart';
import '../../scolarite/domain/fiche_eleve.dart';
import '../application/justificatifs_providers.dart';
import '../domain/justificatif.dart';

/// Justifier une absence passée ou prévenir d'une absence à venir (REG-36,
/// modèle Pronote) : motif, commentaire, photo du certificat au besoin.
/// Fonctionne sans réseau : le dépôt part au retour.
class EcranJustifierAbsence extends ConsumerStatefulWidget {
  const EcranJustifierAbsence({super.key, required this.fiche, this.date});

  final FicheEleve fiche;

  /// Jour de l'absence touchée dans la liste ; null : à choisir (absence à
  /// venir, ou plusieurs jours).
  final DateTime? date;

  @override
  ConsumerState<EcranJustifierAbsence> createState() => _EcranJustifierAbsenceState();
}

class _EcranJustifierAbsenceState extends ConsumerState<EcranJustifierAbsence> {
  late DateTime _debut = widget.date ?? DateTime.now();
  late DateTime _fin = widget.date ?? DateTime.now();
  MotifJustificatif _motif = MotifJustificatif.maladie;
  final _commentaire = TextEditingController();
  Uint8List? _piece;
  String _extension = 'jpg';
  bool _envoi = false;
  String? _erreur;

  @override
  void dispose() {
    _commentaire.dispose();
    super.dispose();
  }

  Future<void> _choisir({required bool debut}) async {
    final aujourdhui = DateTime.now();
    final choisie = await choisirDate(
      context: context,
      initialDate: debut ? _debut : _fin,
      firstDate: aujourdhui.subtract(const Duration(days: 120)),
      lastDate: aujourdhui.add(const Duration(days: 90)),
      helpText: debut ? 'Premier jour d’absence' : 'Dernier jour d’absence',
    );
    if (choisie == null) return;
    setState(() {
      if (debut) {
        _debut = choisie;
        if (_fin.isBefore(_debut)) _fin = _debut;
      } else {
        _fin = choisie.isBefore(_debut) ? _debut : choisie;
      }
    });
  }

  Future<void> _photo(ImageSource source) async {
    XFile? photo;
    try {
      photo = await ImagePicker().pickImage(source: source, imageQuality: 70, maxWidth: 1600, maxHeight: 1600);
    } catch (_) {
      if (mounted) setState(() => _erreur = 'Impossible d’accéder à l’appareil photo ou à la galerie.');
      return;
    }
    if (photo == null) return;
    final octets = await photo.readAsBytes();
    final nom = photo.name.toLowerCase();
    setState(() {
      _piece = octets;
      _extension = nom.endsWith('.png') ? 'png' : nom.endsWith('.webp') ? 'webp' : 'jpg';
      _erreur = null;
    });
  }

  Future<void> _envoyer() async {
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    try {
      final arrive = await ref.read(justificatifsRepositoryProvider).deposer(
            Justificatif(
              id: const Uuid().v4(),
              etablissementId: widget.fiche.etablissementId,
              ficheEleveId: widget.fiche.id,
              dateDebut: _debut,
              dateFin: _fin,
              motif: _motif,
              commentaire: _commentaire.text,
            ),
            piece: _piece,
            extension: _extension,
          );
      ref.invalidate(justificatifsDeFicheProvider(widget.fiche.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(arrive
            ? 'Envoyé à la vie scolaire. Vous verrez ici sa décision.'
            : 'Pas de réseau : gardé sur le téléphone, envoi automatique au retour du réseau.'),
      ));
      Navigator.of(context).pop();
    } on ErreurJustificatif catch (e) {
      setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final historique = ref.watch(justificatifsDeFicheProvider(widget.fiche.id));
    final schema = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('Absence de ${widget.fiche.prenom}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          const Text('Justifiez une absence passée, ou prévenez l’école d’une absence à venir. '
              'La vie scolaire accepte ou refuse ; l’absence n’est justifiée qu’après son accord.'),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('justificatif_debut'),
                onPressed: () => _choisir(debut: true),
                icon: const Icon(Icons.event_outlined),
                label: Text('Du ${formaterDate(_debut)}'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('justificatif_fin'),
                onPressed: () => _choisir(debut: false),
                icon: const Icon(Icons.event_outlined),
                label: Text('Au ${formaterDate(_fin)}'),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          DropdownButtonFormField<MotifJustificatif>(
            key: const Key('justificatif_motif'),
            initialValue: _motif,
            decoration: const InputDecoration(labelText: 'Motif', border: OutlineInputBorder()),
            items: [
              for (final m in MotifJustificatif.values) DropdownMenuItem(value: m, child: Text(m.libelle)),
            ],
            onChanged: (m) => setState(() => _motif = m ?? _motif),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('justificatif_commentaire'),
            controller: _commentaire,
            maxLength: 500,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Commentaire (facultatif)',
              hintText: 'Ex. : fièvre depuis lundi, certificat médical joint',
              border: OutlineInputBorder(),
            ),
          ),
          Row(children: [
            Icon(_piece == null ? Icons.attach_file : Icons.check_circle, color: _piece == null ? null : schema.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(_piece == null ? 'Pièce jointe (facultative)' : 'Photo jointe')),
            IconButton(
              tooltip: 'Prendre une photo',
              onPressed: () => _photo(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
            ),
            IconButton(
              tooltip: 'Choisir dans la galerie',
              onPressed: () => _photo(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
            ),
          ]),
          if (_erreur != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_erreur!, style: TextStyle(color: schema.error)),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('justificatif_envoyer'),
            onPressed: _envoi ? null : _envoyer,
            icon: const Icon(Icons.send_outlined),
            label: Text(_envoi ? 'Envoi…' : 'Envoyer à la vie scolaire'),
          ),
          const SizedBox(height: 24),
          Text('Déjà envoyés', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          historique.when(
            data: (liste) => liste.isEmpty
                ? const Text('Aucun justificatif pour le moment.', key: Key('justificatifs_vides'))
                : Column(children: [for (final j in liste) CarteJustificatif(justificatif: j)]),
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const Text('Liste indisponible pour le moment.'),
          ),
        ],
      ),
    );
  }
}

/// Un justificatif et son état, en mots simples.
class CarteJustificatif extends StatelessWidget {
  const CarteJustificatif({super.key, required this.justificatif, this.actions});

  final Justificatif justificatif;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final j = justificatif;
    final schema = Theme.of(context).colorScheme;
    final etat = j.enAttenteEnvoi ? 'Sur ce téléphone — envoi au retour du réseau' : j.statut.libelle;
    final couleur = switch (j.statut) {
      StatutJustificatif.accepte => schema.primary,
      StatutJustificatif.refuse => schema.error,
      StatutJustificatif.depose => schema.onSurfaceVariant,
    };
    final periode = j.dateDebut == j.dateFin
        ? 'Le ${formaterDate(j.dateDebut)}'
        : 'Du ${formaterDate(j.dateDebut)} au ${formaterDate(j.dateFin)}';
    return Card(
      key: ValueKey('justificatif_${j.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (j.nomEleve != null && j.nomEleve!.isNotEmpty)
            Text(j.nomEleve!, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('$periode — ${j.motif.libelle}${j.aUnePiece ? ' — pièce jointe' : ''}'),
          if (j.commentaire != null && j.commentaire!.isNotEmpty) Text('« ${j.commentaire} »'),
          const SizedBox(height: 4),
          Text(etat, style: TextStyle(color: couleur, fontSize: 12)),
          if (j.statut == StatutJustificatif.refuse && j.motifRefus != null)
            Text('Raison : ${j.motifRefus}', style: TextStyle(color: schema.error, fontSize: 12)),
          ?actions,
        ]),
      ),
    );
  }
}
