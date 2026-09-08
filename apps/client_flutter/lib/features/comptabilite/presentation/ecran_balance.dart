import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/comptabilite_providers.dart';
import 'widgets/montant.dart';

/// Balance comptable (M14) — soldes débit/crédit par compte à une date, via
/// la RPC `balance_comptable` (calcul à la volée) ; le bouton « Générer »
/// persiste un instantané dans `balances` via `generer_balance`.
class EcranBalance extends ConsumerStatefulWidget {
  const EcranBalance({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  ConsumerState<EcranBalance> createState() => _EcranBalanceState();
}

class _EcranBalanceState extends ConsumerState<EcranBalance> {
  DateTime _date = DateTime.now();
  bool _generationEnCours = false;

  Future<void> _genererBalance() async {
    setState(() => _generationEnCours = true);
    await ref.read(comptabiliteRepositoryProvider).genererBalance(widget.etablissementId, _date);
    if (!mounted) return;
    setState(() => _generationEnCours = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Balance générée et archivée.')));
  }

  @override
  Widget build(BuildContext context) {
    final args = (etablissementId: widget.etablissementId, date: _date);
    final balance = ref.watch(balanceComptableProvider(args));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Balance'),
        actions: [
          IconButton(
            tooltip: 'Choisir la date',
            icon: const Icon(Icons.calendar_today_outlined),
            onPressed: () async {
              final choisie = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (choisie != null) setState(() => _date = choisie);
            },
          ),
        ],
      ),
      body: balance.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('Indisponible hors connexion pour le moment.')),
        data: (liste) {
          if (liste.isEmpty) return const Center(child: Text('Aucun compte à balancer.'));
          final totalDebit = liste.fold<double>(0, (a, l) => a + l.soldeDebit);
          final totalCredit = liste.fold<double>(0, (a, l) => a + l.soldeCredit);
          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: liste.length,
                  itemBuilder: (context, i) {
                    final l = liste[i];
                    return ListTile(
                      title: Text('${l.code} — ${l.intitule}'),
                      trailing: Text(
                        l.soldeDebit > 0 ? '${formaterMontant(l.soldeDebit)} D' : '${formaterMontant(l.soldeCredit)} C',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                minimum: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total débit : ${formaterMontant(totalDebit)}'),
                        Text('Total crédit : ${formaterMontant(totalCredit)}'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _generationEnCours ? null : _genererBalance,
                      child: Text(_generationEnCours ? 'Génération…' : 'Générer et archiver cette balance'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
