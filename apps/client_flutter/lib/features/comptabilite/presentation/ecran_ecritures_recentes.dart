import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/shimmer.dart';
import '../application/comptabilite_providers.dart';
import '../domain/ecriture_comptable.dart';
import 'ecran_saisie_ecriture.dart';
import 'widgets/montant.dart';

/// Écritures récentes (M14) — les 100 dernières, tous journaux confondus.
/// Les codes de comptes sont résolus depuis le plan comptable déjà chargé
/// (pas d'embed PostgREST : deux FK vers `plans_comptables` sur la même
/// ligne rendraient la relation ambiguë, cf. `ecriture_comptable.dart`).
class EcranEcrituresRecentes extends ConsumerWidget {
  const EcranEcrituresRecentes({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ecritures = ref.watch(ecrituresRecentesProvider(etablissementId));
    final comptes = ref.watch(planComptableProvider(etablissementId)).value ?? const [];
    final journaux = ref.watch(journauxProvider(etablissementId)).value ?? const [];
    final libelleCompte = {for (final c in comptes) c.id: c.libelle};
    final libelleJournal = {for (final j in journaux) j.id: j.libelle};

    return Scaffold(
      appBar: AppBar(title: const Text('Écritures récentes')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => EcranSaisieEcriture(etablissementId: etablissementId)),
        ),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(ecrituresRecentesProvider(etablissementId).future),
        child: ecritures.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(16),
            children: List.generate(6, (_) => const ShimmerCarteListe()),
          ),
          error: (e, _) => ListView(
            children: const [
              Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Indisponible hors connexion pour le moment.'))),
            ],
          ),
          data: (liste) {
            if (liste.isEmpty) {
              return ListView(
                children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Aucune écriture.')))],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: liste.length,
              itemBuilder: (context, i) => _CarteEcriture(
                ecriture: liste[i],
                compteDebit: libelleCompte[liste[i].compteDebitId] ?? '—',
                compteCredit: libelleCompte[liste[i].compteCreditId] ?? '—',
                journal: libelleJournal[liste[i].journalId] ?? '—',
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CarteEcriture extends StatelessWidget {
  const _CarteEcriture({
    required this.ecriture,
    required this.compteDebit,
    required this.compteCredit,
    required this.journal,
  });

  final EcritureComptable ecriture;
  final String compteDebit;
  final String compteCredit;
  final String journal;

  @override
  Widget build(BuildContext context) {
    final date = ecriture.dateEcriture;
    final dateAffichee = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        title: Text(ecriture.libelle),
        subtitle: Text('$dateAffichee — $journal\n$compteDebit → $compteCredit'),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(formaterMontant(ecriture.montant), style: const TextStyle(fontWeight: FontWeight.w700)),
            if (ecriture.saisiHorsLigne)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Icon(Icons.cloud_off_outlined, size: 14),
              ),
          ],
        ),
      ),
    );
  }
}
