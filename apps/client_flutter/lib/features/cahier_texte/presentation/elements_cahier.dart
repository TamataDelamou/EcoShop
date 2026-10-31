import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/cahier_repository.dart';
import '../domain/cahier.dart';

const _jours = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const _mois = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

/// « Aujourd'hui », « Demain », « Hier », sinon « lundi 3 nov. ».
String dateLisible(DateTime d, {DateTime? maintenant}) {
  final m = jour(maintenant ?? DateTime.now());
  final ecart = jour(d).difference(m).inDays;
  if (ecart == 0) return 'Aujourd’hui';
  if (ecart == 1) return 'Demain';
  if (ecart == -1) return 'Hier';
  return '${_jours[d.weekday - 1]} ${d.day} ${_mois[d.month - 1]}';
}

String minutesLisibles(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final r = minutes % 60;
  return r == 0 ? '$h h' : '$h h ${r.toString().padLeft(2, '0')}';
}

IconData iconeTravail(TypeTravail t) => switch (t) {
      TypeTravail.lecon => Icons.menu_book_outlined,
      TypeTravail.exercices => Icons.edit_note_outlined,
      TypeTravail.redaction => Icons.history_edu_outlined,
      TypeTravail.expose => Icons.co_present_outlined,
      TypeTravail.revision => Icons.refresh_outlined,
      TypeTravail.devoirNumerique => Icons.quiz_outlined,
      TypeTravail.evaluation => Icons.assignment_late_outlined,
    };

/// Pièces jointes : un appui ouvre le fichier (lien temporaire, réseau requis).
class PiecesJointes extends ConsumerWidget {
  const PiecesJointes({super.key, required this.pieces, this.onRetirer});

  final List<PieceJointe> pieces;
  final void Function(PieceJointe)? onRetirer;

  Future<void> _ouvrir(BuildContext context, WidgetRef ref, PieceJointe p) async {
    try {
      final lien = await ref.read(cahierRepositoryProvider).lienPieceJointe(p.chemin);
      await launchUrl(Uri.parse(lien), mode: LaunchMode.externalApplication);
    } on ErreurCahier catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible d’ouvrir ce fichier.')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (pieces.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 4, children: [
      for (final p in pieces)
        InputChip(
          avatar: const Icon(Icons.attach_file, size: 16),
          label: Text(p.nom, overflow: TextOverflow.ellipsis),
          onPressed: () => _ouvrir(context, ref, p),
          onDeleted: onRetirer == null ? null : () => onRetirer!(p),
        ),
    ]);
  }
}

/// Étiquette « en attente d'envoi » (écrit sans réseau).
class EtiquetteEnAttente extends StatelessWidget {
  const EtiquetteEnAttente({super.key});

  @override
  Widget build(BuildContext context) {
    final schema = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: schema.tertiaryContainer, borderRadius: BorderRadius.circular(8)),
      child: Text('en attente d’envoi', style: TextStyle(fontSize: 11, color: schema.onTertiaryContainer)),
    );
  }
}
