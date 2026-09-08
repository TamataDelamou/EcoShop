import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/comptabilite_providers.dart';
import '../domain/journal.dart';
import 'widgets/montant.dart';

/// Journal comptable (M14) — enregistrements chronologiques d'un journal sur
/// une période, via la RPC `journal_comptable` (agrégat calculé à la
/// demande, non caché hors-ligne).
class EcranJournalComptable extends ConsumerStatefulWidget {
  const EcranJournalComptable({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  ConsumerState<EcranJournalComptable> createState() => _EcranJournalComptableState();
}

class _EcranJournalComptableState extends ConsumerState<EcranJournalComptable> {
  Journal? _journal;
  DateTime _debut = DateTime(DateTime.now().year, 1, 1);
  DateTime _fin = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final journaux = ref.watch(journauxProvider(widget.etablissementId));
    final journal = _journal;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Journal comptable'),
        actions: [
          IconButton(
            tooltip: 'Modifier la période',
            icon: const Icon(Icons.date_range_outlined),
            onPressed: () async {
              final choisie = await showDateRangePicker(
                context: context,
                initialDateRange: DateTimeRange(start: _debut, end: _fin),
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (choisie != null) {
                setState(() {
                  _debut = choisie.start;
                  _fin = choisie.end;
                });
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: journaux.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => const Text('Journaux indisponibles hors connexion.'),
              data: (liste) {
                if (liste.isEmpty) return const Text('Aucun journal configuré.');
                _journal ??= liste.first;
                return DropdownButtonFormField<Journal>(
                  initialValue: _journal,
                  decoration: const InputDecoration(labelText: 'Journal'),
                  items: liste.map((j) => DropdownMenuItem(value: j, child: Text(j.libelle))).toList(),
                  onChanged: (v) => setState(() => _journal = v),
                );
              },
            ),
          ),
          Expanded(
            child: journal == null
                ? const Center(child: Text('Sélectionnez un journal.'))
                : Consumer(
                    builder: (context, ref, _) {
                      final lignes = ref.watch(journalComptableProvider(
                        (etablissementId: widget.etablissementId, journalId: journal.id, debut: _debut, fin: _fin),
                      ));
                      return lignes.when(
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (e, _) => const Center(child: Text('Indisponible hors connexion pour le moment.')),
                        data: (liste) {
                          if (liste.isEmpty) return const Center(child: Text('Aucune écriture sur la période.'));
                          return ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: liste.length,
                            itemBuilder: (context, i) {
                              final l = liste[i];
                              final date =
                                  '${l.dateEcriture.day.toString().padLeft(2, '0')}/${l.dateEcriture.month.toString().padLeft(2, '0')}/${l.dateEcriture.year}';
                              return ListTile(
                                title: Text(l.libelle),
                                subtitle: Text('$date — ${l.compteDebit} → ${l.compteCredit}'),
                                trailing: Text(formaterMontant(l.montant), style: const TextStyle(fontWeight: FontWeight.w700)),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
