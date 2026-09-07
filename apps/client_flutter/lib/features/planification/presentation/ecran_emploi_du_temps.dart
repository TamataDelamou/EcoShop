import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/planification_providers.dart';
import '../domain/emploi_du_temps.dart';
import 'widgets/badge_signal_ia.dart';
import 'widgets/carte_seance.dart';

/// Emploi du temps d'une classe (M11) — vue élève/parent/personnel,
/// consultable hors connexion (cache Drift).
class EcranEmploiClasse extends ConsumerWidget {
  const EcranEmploiClasse({super.key, required this.classeId, required this.titre});

  final String classeId;
  final String titre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emplois = ref.watch(emploisDeClasseProvider(classeId));
    return _EcranGrille(
      titre: titre,
      emplois: emplois,
      onRefresh: () async => ref.invalidate(emploisDeClasseProvider(classeId)),
      libelleSecondaire: (e) => [e.nomEnseignant, e.libelleSalle].where((v) => v != null && v.isNotEmpty).join(' · '),
    );
  }
}

/// Emploi du temps d'un enseignant, toutes classes confondues.
class EcranEmploiEnseignant extends ConsumerWidget {
  const EcranEmploiEnseignant({
    super.key,
    required this.enseignantProfileId,
    required this.etablissementId,
    required this.anneeId,
  });

  final String enseignantProfileId;
  final String etablissementId;
  final String anneeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (enseignantProfileId: enseignantProfileId, etablissementId: etablissementId, anneeId: anneeId);
    final emplois = ref.watch(emploisDeEnseignantProvider(args));
    final charge = ref.watch(chargeEnseignantProvider(
      (etablissementId: etablissementId, anneeId: anneeId, enseignantProfileId: enseignantProfileId),
    ));

    return _EcranGrille(
      titre: 'Mon emploi du temps',
      emplois: emplois,
      onRefresh: () async => ref.invalidate(emploisDeEnseignantProvider(args)),
      libelleSecondaire: (e) => [e.nomClasse, e.libelleSalle].where((v) => v != null && v.isNotEmpty).join(' · '),
      enTete: charge.when(
        loading: () => const SizedBox.shrink(),
        error: (erreur, _) => const SizedBox.shrink(),
        data: (c) => c.surcharge
            ? Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: BadgeSignalIa(
                  texte: 'Surcharge détectée — ${c.heuresHebdo.toStringAsFixed(1)} h vs ${c.volumeContractuelHebdo} h contractuelles',
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

/// Occupation d'une salle sur une année — aide à la détection visuelle de
/// conflits de réservation.
class EcranEmploiSalle extends ConsumerWidget {
  const EcranEmploiSalle({super.key, required this.salleId, required this.anneeId, required this.titre});

  final String salleId;
  final String anneeId;
  final String titre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (salleId: salleId, anneeId: anneeId);
    final emplois = ref.watch(emploisDeSalleProvider(args));
    return _EcranGrille(
      titre: titre,
      emplois: emplois,
      onRefresh: () async => ref.invalidate(emploisDeSalleProvider(args)),
      libelleSecondaire: (e) => [e.nomClasse, e.nomEnseignant].where((v) => v != null && v.isNotEmpty).join(' · '),
    );
  }
}

class _EcranGrille extends StatelessWidget {
  const _EcranGrille({
    required this.titre,
    required this.emplois,
    required this.onRefresh,
    required this.libelleSecondaire,
    this.enTete,
  });

  final String titre;
  final AsyncValue<List<EmploiDuTemps>> emplois;
  final Future<void> Function() onRefresh;
  final String Function(EmploiDuTemps) libelleSecondaire;
  final Widget? enTete;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titre)),
      body: Column(
        children: [
          enTete ?? const SizedBox.shrink(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: onRefresh,
              child: emplois.when(
                loading: () => ListView(
                  padding: const EdgeInsets.all(16),
                  children: List.generate(5, (_) => const ShimmerCarteListe()),
                ),
                error: (erreur, _) => ListView(
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Emploi du temps indisponible hors connexion pour le moment.'),
                    ),
                  ],
                ),
                data: (liste) {
                  if (liste.isEmpty) {
                    return ListView(
                      children: const [Padding(padding: EdgeInsets.all(32), child: Text('Aucune séance planifiée.'))],
                    );
                  }
                  final parJour = <int, List<EmploiDuTemps>>{};
                  for (final e in liste) {
                    parJour.putIfAbsent(e.jourSemaine, () => []).add(e);
                  }
                  final jours = parJour.keys.toList()..sort();

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (var i = 0; i < jours.length; i++) ...[
                        Text(joursSemaine[jours[i] - 1], style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        for (final emploi in parJour[jours[i]]!)
                          EntreeAnimee(
                            index: i,
                            enfant: CarteSeance(emploi: emploi, libelleSecondaire: libelleSecondaire(emploi)),
                          ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
