import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import 'ecran_anomalies_comptables.dart';
import 'ecran_balance.dart';
import 'ecran_ecritures_recentes.dart';
import 'ecran_ecritures_recommandees.dart';
import 'ecran_grand_livre.dart';
import 'ecran_journal_comptable.dart';
import 'ecran_journaux.dart';
import 'ecran_plan_comptable.dart';
import 'ecran_prevision_tresorerie.dart';
import 'ecran_tendances.dart';

/// Menu d'entrée de la comptabilité (M14) — partie double sans OHADA,
/// réservé direction/finance (`est_comptable` côté serveur ; ce gating
/// client est purement ergonomique).
class EcranComptabilite extends StatelessWidget {
  const EcranComptabilite({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Comptabilité')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(context, 'Saisie'),
          _tuile(context, Icons.receipt_long_outlined, AppColors.bleuElectrique, 'Écritures récentes',
              'Saisie et consultation', () => EcranEcrituresRecentes(etablissementId: etablissementId)),
          _section(context, 'Configuration'),
          _tuile(context, Icons.account_tree_outlined, AppColors.bleuElectrique, 'Plan comptable',
              'Structure ouverte, arborescente', () => EcranPlanComptable(etablissementId: etablissementId)),
          _tuile(context, Icons.menu_book_outlined, AppColors.bleuElectrique, 'Journaux',
              'Opérations, banque, caisse, achats, ventes', () => EcranJournaux(etablissementId: etablissementId)),
          _section(context, 'Documents'),
          _tuile(context, Icons.article_outlined, AppColors.orangePop, 'Journal comptable',
              'Chronologie d\'un journal', () => EcranJournalComptable(etablissementId: etablissementId)),
          _tuile(context, Icons.book_outlined, AppColors.orangePop, 'Grand livre',
              'Mouvements d\'un compte', () => EcranGrandLivre(etablissementId: etablissementId)),
          _tuile(context, Icons.balance_outlined, AppColors.orangePop, 'Balance',
              'Soldes débit/crédit à une date', () => EcranBalance(etablissementId: etablissementId)),
          _section(context, 'Supervision IA'),
          _tuile(context, Icons.report_gmailerrorred_outlined, AppColors.dore, 'Anomalies',
              'Montants élevés, doubles saisies', () => EcranAnomaliesComptables(etablissementId: etablissementId)),
          _tuile(context, Icons.trending_up_outlined, AppColors.dore, 'Prévision de trésorerie',
              'Projection à 30 jours', () => EcranPrevisionTresorerie(etablissementId: etablissementId)),
          _tuile(context, Icons.repeat_outlined, AppColors.dore, 'Écritures récurrentes',
              'Suggestions de ressaisie', () => EcranEcrituresRecommandees(etablissementId: etablissementId)),
          _tuile(context, Icons.insights_outlined, AppColors.dore, 'Tendances',
              'Charges/produits sur 12 mois', () => EcranTendances(etablissementId: etablissementId)),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String titre) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(titre, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.encreSecondaire)),
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
