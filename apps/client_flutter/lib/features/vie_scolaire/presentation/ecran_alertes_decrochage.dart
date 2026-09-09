import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/vie_scolaire_providers.dart';
import '../domain/alerte_decrochage.dart';
import '../domain/enums_vie_scolaire.dart';
import 'widgets/badge_signal_ia.dart';

/// Alertes de décrochage d'un établissement (M7, vue direction).
///
/// **Lecture seule** : `alertes_decrochage` ne porte aucune policy RLS
/// d'écriture côté client (contrat M07 §5 — calcul et traitement réservés au
/// serveur/back-office). L'écran ne propose donc aucune action de
/// « marquer traitée » tant qu'aucune RPC dédiée n'est publiée.
class EcranAlertesDecrochage extends ConsumerWidget {
  const EcranAlertesDecrochage({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertes = ref.watch(alertesEtablissementProvider(etablissementId));

    return Scaffold(
      appBar: AppBar(title: const Text('Alertes de décrochage')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: context.palette.premium.withValues(alpha: 0.08),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: context.palette.premium, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ces scores sont un signal, jamais un verdict — le traitement '
                    "(entretien, soutien, transmission) reste une décision humaine.",
                    style: TextStyle(fontSize: 12, color: context.palette.premium),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: alertes.when(
              loading: () => ListView(
                padding: const EdgeInsets.all(16),
                children: List.generate(4, (_) => const ShimmerCarteListe()),
              ),
              error: (erreur, _) => const Center(
                child: Text('Alertes indisponibles hors connexion pour le moment.'),
              ),
              data: (liste) => liste.isEmpty
                  ? const Center(child: Text('Aucune alerte ouverte.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: liste.length,
                      itemBuilder: (context, i) =>
                          EntreeAnimee(index: i, enfant: _CarteAlerte(alerte: liste[i])),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CarteAlerte extends StatelessWidget {
  const _CarteAlerte({required this.alerte});

  final AlerteDecrochage alerte;

  @override
  Widget build(BuildContext context) {
    final couleur = alerte.score >= 0.8 ? context.palette.erreur : context.palette.accent;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(alerte.nomEleve ?? 'Élève', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: couleur.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${(alerte.score * 100).toStringAsFixed(0)} %',
                    style: TextStyle(color: couleur, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            BadgeSignalIa(texte: _libelleStatut(alerte.statut)),
          ],
        ),
      ),
    );
  }

  static String _libelleStatut(StatutAlerte statut) => switch (statut) {
        StatutAlerte.ouverte => 'Signal IA — ouverte, à examiner',
        StatutAlerte.transmise => 'Signal IA — transmise à la famille',
        StatutAlerte.traitee => 'Signal IA — traitée',
        StatutAlerte.ignoree => 'Signal IA — classée sans suite',
      };
}
