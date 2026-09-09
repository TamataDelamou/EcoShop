import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/rh_providers.dart';
import '../domain/bulletin_paie.dart';
import '../domain/employe.dart';
import '../domain/enums_rh.dart';

/// Bulletins de paie d'un employé (M8) — **consultation uniquement** :
/// l'établissement des bulletins (calcul, validation, export) est le
/// périmètre du module M14 (Comptabilité). `net` provient toujours du
/// serveur (trigger `paie_calcule_net`), jamais recalculé côté client.
class EcranPaie extends ConsumerWidget {
  const EcranPaie({super.key, required this.employe});

  final Employe employe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bulletins = ref.watch(bulletinsDeEmployeProvider(employe.id));

    return Scaffold(
      appBar: AppBar(title: Text('Paie — ${employe.nomAffiche ?? employe.matricule}')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: context.palette.primaire.withValues(alpha: 0.06),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: context.palette.primaire, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Consultation seule — l'établissement des bulletins de paie "
                    'sera géré par le module Comptabilité.',
                    style: TextStyle(fontSize: 12, color: context.palette.primaire),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: bulletins.when(
              loading: () => ListView(
                padding: const EdgeInsets.all(16),
                children: List.generate(3, (_) => const ShimmerCarteListe()),
              ),
              error: (erreur, _) => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('Bulletins indisponibles hors connexion pour le moment.'),
                ),
              ),
              data: (liste) => liste.isEmpty
                  ? const Center(child: Text('Aucun bulletin établi.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: liste.length,
                      itemBuilder: (context, i) =>
                          EntreeAnimee(index: i, enfant: _CarteBulletin(bulletin: liste[i])),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CarteBulletin extends StatelessWidget {
  const _CarteBulletin({required this.bulletin});

  final BulletinPaie bulletin;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_formatDate(bulletin.periodeDebut)} — ${_formatDate(bulletin.periodeFin)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                _PastilleStatutPaie(statut: bulletin.statut),
              ],
            ),
            const SizedBox(height: 8),
            _LigneMontant(libelle: 'Base', montant: bulletin.salaireBase),
            _LigneMontant(libelle: 'Primes', montant: bulletin.primes, couleur: context.palette.succes),
            _LigneMontant(libelle: 'Retenues', montant: -bulletin.retenues, couleur: context.palette.erreur),
            const Divider(),
            _LigneMontant(libelle: 'Net', montant: bulletin.net, accent: true),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _LigneMontant extends StatelessWidget {
  const _LigneMontant({
    required this.libelle,
    required this.montant,
    this.couleur,
    this.accent = false,
  });

  final String libelle;
  final double montant;
  final Color? couleur;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            libelle,
            style: TextStyle(fontWeight: accent ? FontWeight.w700 : FontWeight.w400),
          ),
          Text(
            montant.toStringAsFixed(0),
            style: TextStyle(
              color: couleur,
              fontWeight: accent ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _PastilleStatutPaie extends StatelessWidget {
  const _PastilleStatutPaie({required this.statut});

  final StatutPaie statut;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final couleur = switch (statut) {
      StatutPaie.brouillon => palette.encreSecondaire,
      StatutPaie.valide => palette.primaire,
      StatutPaie.paye => palette.succes,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(statut.libelle, style: TextStyle(color: couleur, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
