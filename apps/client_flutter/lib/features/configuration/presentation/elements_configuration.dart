import 'package:flutter/material.dart';

import '../data/configuration_repository.dart';

void signaler(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Exécute une action d'écriture et affiche son résultat.
Future<bool> executer(BuildContext context, Future<void> Function() action, {String? succes}) async {
  try {
    await action();
    if (context.mounted && succes != null) signaler(context, succes);
    return true;
  } on ErreurConfiguration catch (e) {
    if (context.mounted) signaler(context, e.message);
  } catch (e) {
    if (context.mounted) signaler(context, 'Action impossible pour le moment. Réessayez.');
  }
  return false;
}

/// Encadré d'explication en haut d'une étape.
class Explication extends StatelessWidget {
  const Explication(this.texte, {super.key, this.icone = Icons.info_outline});

  final String texte;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    final schema = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: schema.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 20, color: schema.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(child: Text(texte, style: TextStyle(color: schema.onSecondaryContainer))),
        ],
      ),
    );
  }
}

/// Liste vide : ce qu'il faut faire, et le bouton pour le faire.
class EtatVide extends StatelessWidget {
  const EtatVide({super.key, required this.icone, required this.titre, required this.texte, this.action});

  final IconData icone;
  final String titre;
  final String texte;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(titre, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(texte, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Erreur de chargement, avec « Réessayer ».
class ErreurChargement extends StatelessWidget {
  const ErreurChargement({super.key, required this.onReessayer});

  final VoidCallback onReessayer;

  @override
  Widget build(BuildContext context) => EtatVide(
        icone: Icons.cloud_off_rounded,
        titre: 'Pas encore disponible sur cet appareil',
        texte: 'Une connexion est nécessaire la première fois ; ensuite, la page reste consultable sans réseau.',
        action: FilledButton.icon(onPressed: onReessayer, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
      );
}
