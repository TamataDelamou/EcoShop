import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/annonces_providers.dart';
import '../domain/annonce.dart';

String dateAnnonce(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Annonces reçues par une famille ou un élève (toutes ses écoles). Ouvrir
/// une annonce confirme sa lecture, même sans réseau (envoyée au retour).
class EcranAnnonces extends ConsumerWidget {
  const EcranAnnonces({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final annonces = ref.watch(mesAnnoncesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Annonces de l’école')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(mesAnnoncesProvider),
        child: annonces.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(padding: const EdgeInsets.all(24), children: [
            Text(
              e is ErreurAnnonces ? e.message : 'Annonces indisponibles. Tirez pour réessayer.',
              textAlign: TextAlign.center,
            ),
          ]),
          data: (liste) => liste.isEmpty
              ? ListView(padding: const EdgeInsets.all(24), children: const [
                  Text('Aucune annonce pour le moment. Vous serez prévenu(e) dès que l’école en publiera une.',
                      textAlign: TextAlign.center),
                ])
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: liste.length,
                  itemBuilder: (_, i) => _CarteAnnonce(annonce: liste[i]),
                ),
        ),
      ),
    );
  }
}

class _CarteAnnonce extends ConsumerStatefulWidget {
  const _CarteAnnonce({required this.annonce});

  final Annonce annonce;

  @override
  ConsumerState<_CarteAnnonce> createState() => _CarteAnnonceState();
}

class _CarteAnnonceState extends ConsumerState<_CarteAnnonce> {
  bool _ouverte = false;
  bool _lue = false;

  @override
  void initState() {
    super.initState();
    _lue = widget.annonce.lue;
  }

  Future<void> _ouvrir() async {
    setState(() => _ouverte = !_ouverte);
    if (_ouverte && !_lue) {
      setState(() => _lue = true);
      try {
        await ref.read(annoncesRepositoryProvider).marquerLue(widget.annonce.id);
      } catch (_) {
        // Lecture confirmée plus tard : rien à montrer à la famille.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.annonce;
    final theme = Theme.of(context);
    final schema = theme.colorScheme;
    return Card(
      key: ValueKey('annonce_${a.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _ouvrir,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (!_lue)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(Icons.circle, size: 10, color: schema.primary, semanticLabel: 'Non lue'),
                    ),
                  if (a.importante)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.priority_high, size: 18, color: schema.error, semanticLabel: 'Important'),
                    ),
                  Expanded(
                    child: Text(a.titre,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: _lue ? FontWeight.w500 : FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [a.etablissement, a.cible, dateAnnonce(a.publieeLe)].whereType<String>().join(' · '),
                style: theme.textTheme.bodySmall,
              ),
              if (_ouverte) ...[
                const SizedBox(height: 10),
                SelectableText(a.corps, key: Key('corps_${a.id}')),
              ] else ...[
                const SizedBox(height: 6),
                Text(a.corps, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
