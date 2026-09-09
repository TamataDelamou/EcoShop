import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/scolarite_providers.dart';

String _formaterMontant(double montant) => NumberFormat.decimalPattern('fr').format(montant);

/// Cahier journal des encaissements de scolarité d'un établissement, tous
/// élèves confondus (M15quater) — vue de supervision pour la direction,
/// distincte du journal comptable général de M14 (`ecran_ecritures_recentes`) :
/// ici, chaque ligne est un encaissement réellement lié à un élève et une
/// inscription, jamais une écriture comptable libre.
class EcranCahierEncaissements extends ConsumerWidget {
  const EcranCahierEncaissements({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final encaissements = ref.watch(encaissementsRecentsProvider(etablissementId));
    final palette = context.palette;

    return Scaffold(
      appBar: AppBar(title: const Text('Cahier des encaissements')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(encaissementsRecentsProvider(etablissementId).future),
        child: encaissements.when(
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
                children: const [
                  Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Aucun encaissement enregistré.'))),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: liste.length,
              itemBuilder: (context, i) {
                final e = liste[i];
                final date = e.datePaiement;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    title: Text('${_formaterMontant(e.montant)} — ${e.typeFrais.libelle}'),
                    subtitle: Text(
                      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} '
                      '· ${e.moyenPaiement.libelle}'
                      '${e.estValide ? '' : ' · ANNULÉ'}',
                    ),
                    trailing: e.estValide
                        ? null
                        : Icon(Icons.cancel_outlined, color: palette.erreur),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
