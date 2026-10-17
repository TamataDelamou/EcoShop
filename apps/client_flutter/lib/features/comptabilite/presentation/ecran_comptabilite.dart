import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../application/referentiel_comptable_providers.dart';
import 'ecran_anomalies_comptables.dart';
import 'ecran_balance.dart';
import 'ecran_comptabilisation_automatique.dart';
import 'ecran_ecritures_recentes.dart';
import 'ecran_ecritures_recommandees.dart';
import 'ecran_exercices_comptables.dart';
import 'ecran_grand_livre.dart';
import 'ecran_journal_comptable.dart';
import 'ecran_journaux.dart';
import 'ecran_pieces_comptables.dart';
import 'ecran_plan_comptable.dart';
import 'ecran_prevision_tresorerie.dart';
import 'ecran_referentiel_comptable.dart';
import 'ecran_tendances.dart';

/// Menu d'entrée de la comptabilité (M14) — partie double sans OHADA,
/// réservé direction/finance (`est_comptable` côté serveur ; ce gating
/// client est purement ergonomique).
class EcranComptabilite extends ConsumerWidget {
  const EcranComptabilite({super.key, required this.etablissementId, this.devise = 'GNF'});

  final String etablissementId;

  /// Devise de l'établissement — seuil du Système minimal de trésorerie.
  final String devise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // En référentiel OHADA, la saisie se fait obligatoirement par pièces
    // (REG-03 C2) : l'ancienne saisie à deux comptes est masquée.
    final ohada = ref.watch(parametresComptablesProvider(etablissementId)).value?.referentiel.estReglementaire ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Comptabilité')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(context, 'Saisie'),
          _tuile(context, Icons.post_add_outlined, context.palette.primaire, 'Pièces comptables',
              'Brouillards, validation, contre-passation', () => EcranPiecesComptables(etablissementId: etablissementId)),
          _tuile(context, Icons.bolt_outlined, context.palette.primaire, 'Écritures automatiques',
              'Paiements de frais scolaires passés en comptabilité', () => EcranComptabilisationAutomatique(etablissementId: etablissementId)),
          if (!ohada)
            _tuile(context, Icons.receipt_long_outlined, context.palette.primaire, 'Écritures rapides',
                'Un débit, un crédit (comptabilité simplifiée)', () => EcranEcrituresRecentes(etablissementId: etablissementId)),
          _section(context, 'Configuration'),
          _tuile(context, Icons.gavel_outlined, context.palette.primaire, 'Référentiel comptable',
              'Simplifié, SYSCOHADA ou SYCEBNL', () => EcranReferentielComptable(etablissementId: etablissementId, devise: devise)),
          _tuile(context, Icons.account_tree_outlined, context.palette.primaire, 'Plan comptable',
              'Comptes et sous-comptes', () => EcranPlanComptable(etablissementId: etablissementId)),
          _tuile(context, Icons.event_available_outlined, context.palette.primaire, 'Exercices et clôtures',
              'Ouverture, clôture de période et d\'exercice', () => EcranExercicesComptables(etablissementId: etablissementId)),
          _tuile(context, Icons.menu_book_outlined, context.palette.primaire, 'Journaux',
              'Opérations, banque, caisse, achats, ventes', () => EcranJournaux(etablissementId: etablissementId)),
          _section(context, 'Documents'),
          _tuile(context, Icons.article_outlined, context.palette.accent, 'Journal comptable',
              'Chronologie d\'un journal', () => EcranJournalComptable(etablissementId: etablissementId)),
          _tuile(context, Icons.book_outlined, context.palette.accent, 'Grand livre',
              'Mouvements d\'un compte', () => EcranGrandLivre(etablissementId: etablissementId)),
          _tuile(context, Icons.balance_outlined, context.palette.accent, 'Balance',
              'Soldes débit/crédit à une date', () => EcranBalance(etablissementId: etablissementId)),
          _section(context, 'Supervision IA'),
          _tuile(context, Icons.report_gmailerrorred_outlined, context.palette.premium, 'Anomalies',
              'Montants élevés, doubles saisies', () => EcranAnomaliesComptables(etablissementId: etablissementId)),
          _tuile(context, Icons.trending_up_outlined, context.palette.premium, 'Prévision de trésorerie',
              'Projection à 30 jours', () => EcranPrevisionTresorerie(etablissementId: etablissementId)),
          _tuile(context, Icons.repeat_outlined, context.palette.premium, 'Écritures récurrentes',
              'Suggestions de ressaisie', () => EcranEcrituresRecommandees(etablissementId: etablissementId)),
          _tuile(context, Icons.insights_outlined, context.palette.premium, 'Tendances',
              'Charges/produits sur 12 mois', () => EcranTendances(etablissementId: etablissementId)),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String titre) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(titre, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: context.palette.encreSecondaire)),
      );

  Widget _tuile(
    BuildContext context,
    IconData icone,
    Color couleur,
    String titre,
    String sousTitre,
    Widget Function() ecran,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: couleur.withValues(alpha: 0.12), child: Icon(icone, color: couleur)),
        title: Text(titre),
        subtitle: Text(sousTitre),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ecran())),
      ),
    );
  }
}
