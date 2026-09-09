import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../application/comptabilite_providers.dart';
import '../domain/plan_comptable.dart';
import 'widgets/montant.dart';

/// Grand livre (M14) — mouvements (débit/crédit) d'un compte sur une
/// période, via la RPC `grand_livre`.
class EcranGrandLivre extends ConsumerStatefulWidget {
  const EcranGrandLivre({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  ConsumerState<EcranGrandLivre> createState() => _EcranGrandLivreState();
}

class _EcranGrandLivreState extends ConsumerState<EcranGrandLivre> {
  PlanComptable? _compte;
  DateTime _debut = DateTime(DateTime.now().year, 1, 1);
  DateTime _fin = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final comptes = ref.watch(planComptableProvider(widget.etablissementId));
    final compte = _compte;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Grand livre'),
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
            child: comptes.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => const Text('Comptes indisponibles hors connexion.'),
              data: (liste) {
                if (liste.isEmpty) return const Text('Aucun compte configuré.');
                _compte ??= liste.first;
                return DropdownButtonFormField<PlanComptable>(
                  initialValue: _compte,
                  decoration: const InputDecoration(labelText: 'Compte'),
                  items: liste.map((c) => DropdownMenuItem(value: c, child: Text(c.libelle))).toList(),
                  onChanged: (v) => setState(() => _compte = v),
                );
              },
            ),
          ),
          Expanded(
            child: compte == null
                ? const Center(child: Text('Sélectionnez un compte.'))
                : Consumer(
                    builder: (context, ref, _) {
                      final mouvements = ref.watch(grandLivreProvider(
                        (etablissementId: widget.etablissementId, compteId: compte.id, debut: _debut, fin: _fin),
                      ));
                      return mouvements.when(
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (e, _) => const Center(child: Text('Indisponible hors connexion pour le moment.')),
                        data: (liste) {
                          if (liste.isEmpty) return const Center(child: Text('Aucun mouvement sur la période.'));
                          return ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: liste.length,
                            itemBuilder: (context, i) {
                              final m = liste[i];
                              final date =
                                  '${m.dateEcriture.day.toString().padLeft(2, '0')}/${m.dateEcriture.month.toString().padLeft(2, '0')}/${m.dateEcriture.year}';
                              return ListTile(
                                leading: Icon(
                                  m.estDebit ? Icons.arrow_downward : Icons.arrow_upward,
                                  color: m.estDebit ? context.palette.primaire : context.palette.accent,
                                ),
                                title: Text(m.libelle),
                                subtitle: Text(date),
                                trailing: Text(
                                  formaterMontant(m.montant),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: m.estDebit ? context.palette.primaire : context.palette.accent,
                                  ),
                                ),
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
