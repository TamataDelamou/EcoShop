import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_palette.dart';
import '../domain/reseau.dart';

String montantReseau(double montant, String devise) =>
    '${NumberFormat.decimalPattern('fr').format(montant)} $devise';

const _mois = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

String dateCourte(DateTime d) => '${d.day} ${_mois[d.month - 1]} ${d.year}';

String periode(DateTime debut, DateTime fin) =>
    debut == fin ? dateCourte(debut) : '${dateCourte(debut)} → ${dateCourte(fin)}';

/// Message d'erreur lisible, quelle que soit l'exception.
String messageErreurReseau(Object e) =>
    e is ErreurReseau ? e.messageUtilisateur : 'Opération impossible pour le moment.';

class EtatVideReseau extends StatelessWidget {
  const EtatVideReseau({super.key, required this.icone, required this.texte});

  final IconData icone;
  final String texte;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 48, color: palette.encreSecondaire),
            const SizedBox(height: 12),
            Text(texte, textAlign: TextAlign.center, style: TextStyle(color: palette.encreSecondaire)),
          ],
        ),
      ),
    );
  }
}

class ErreurChargementReseau extends StatelessWidget {
  const ErreurChargementReseau({super.key, required this.erreur, required this.reessayer});

  final Object erreur;
  final VoidCallback reessayer;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              erreur is ErreurReseau && (erreur as ErreurReseau).code == 'HORS_CONNEXION'
                  ? 'Pas encore de données sur cet appareil : connectez-vous une première fois au réseau.'
                  : messageErreurReseau(erreur),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: reessayer, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}

/// Pastille « en attente d'envoi » des actions faites sans réseau.
class PastilleEnAttente extends StatelessWidget {
  const PastilleEnAttente({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_upload_outlined, size: 14, color: palette.accent),
          const SizedBox(width: 4),
          Text('En attente d’envoi', style: TextStyle(fontSize: 12, color: palette.accent)),
        ],
      ),
    );
  }
}

class StatutEcole extends StatelessWidget {
  const StatutEcole({super.key, required this.statut, required this.libelle});

  final String statut;
  final String libelle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final couleur = switch (statut) {
      'membre' => palette.succes,
      'invite' => palette.accent,
      'retrait_demande' => palette.premium,
      _ => palette.encreSecondaire,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: couleur.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
      child: Text(libelle, style: TextStyle(fontSize: 12, color: couleur, fontWeight: FontWeight.w600)),
    );
  }
}

/// Double confirmation (cahier 28.4) : une première boîte explique, la
/// seconde demande de ressaisir un mot précis. Renvoie le texte saisi, ou
/// `null` si la personne renonce.
Future<String?> doubleConfirmation(
  BuildContext context, {
  required String titre,
  required String explication,
  required String consigne,
  required String attendu,
  required String libelleAction,
  bool motifLibre = false,
}) async {
  final premiere = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titre),
      content: Text(explication),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Continuer')),
      ],
    ),
  );
  if (premiere != true || !context.mounted) return null;
  final champ = TextEditingController();
  final resultat = await showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) {
        final valide = motifLibre
            ? champ.text.trim().length >= 3
            : champ.text.trim().toLowerCase() == attendu.trim().toLowerCase();
        return AlertDialog(
          title: Text('$titre — confirmation'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(consigne),
              const SizedBox(height: 12),
              TextField(
                controller: champ,
                autofocus: true,
                maxLines: motifLibre ? 3 : 1,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(border: const OutlineInputBorder(), hintText: motifLibre ? null : attendu),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
              onPressed: valide ? () => Navigator.pop(c, champ.text.trim()) : null,
              child: Text(libelleAction),
            ),
          ],
        );
      },
    ),
  );
  // Pas de dispose() : la boîte se referme encore (animation) et utilise
  // le champ ; le contrôleur est simplement abandonné.
  return resultat;
}
