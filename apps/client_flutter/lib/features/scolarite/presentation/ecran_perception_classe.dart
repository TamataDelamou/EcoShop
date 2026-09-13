import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/scolarite_providers.dart';
import '../domain/classe.dart';
import '../domain/inscription.dart';
import '../domain/solde_scolarite.dart';
import 'ecran_encaissement_scolarite.dart';

String _formaterMontant(double montant) => NumberFormat.decimalPattern('fr').format(montant);

/// Perception des frais par classe (D6) — consultation uniquement : liste
/// des élèves de la classe avec leur solde, puis navigation vers
/// l'encaissement individuel déjà existant. Le solde vient exclusivement de
/// la RPC `solde_scolarite` (aucun recalcul ici, même principe que le reste
/// du module financier). Pas de saisie groupée dans cette passe (cf. rapport
/// d'écart D6) — une correction de solde erronée sur toute une classe serait
/// plus difficile à défaire qu'un export PDF groupé.
class EcranPerceptionClasse extends ConsumerWidget {
  const EcranPerceptionClasse({super.key, required this.classe});

  final Classe classe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inscriptions = ref.watch(inscriptionsDeClasseProvider(classe.id));
    final soldes = ref.watch(soldesClasseProvider(classe.id));

    return Scaffold(
      appBar: AppBar(title: Text('Frais — ${classe.nom}')),
      body: inscriptions.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: List.generate(5, (_) => const ShimmerCarteListe()),
        ),
        error: (erreur, _) => const _EtatErreur(
          message: 'Impossible d\'afficher les élèves de cette classe.',
        ),
        data: (liste) {
          final actives = liste.where((i) => i.fiche != null).toList()
            ..sort((a, b) => (a.fiche?.nomComplet ?? '').compareTo(b.fiche?.nomComplet ?? ''));
          if (actives.isEmpty) {
            return const _EtatErreur(message: 'Aucun élève inscrit pour le moment.');
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: actives.length,
            itemBuilder: (context, i) => _CarteSolde(
              inscription: actives[i],
              solde: soldes.value?[actives[i].id],
              chargement: soldes.isLoading,
            ),
          );
        },
      ),
    );
  }
}

class _CarteSolde extends StatelessWidget {
  const _CarteSolde({required this.inscription, required this.solde, required this.chargement});

  final Inscription inscription;
  final SoldeScolarite? solde;
  final bool chargement;

  @override
  Widget build(BuildContext context) {
    final fiche = inscription.fiche;
    final palette = context.palette;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        title: Text(fiche?.nomComplet ?? 'Élève'),
        subtitle: Text('Matricule ${fiche?.matricule ?? '—'}'),
        trailing: chargement && solde == null
            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : solde == null
                ? Text('—', style: TextStyle(color: palette.encreSecondaire))
                : _pastilleSolde(palette, solde!),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => EcranEncaissementScolarite(inscription: inscription)),
        ),
      ),
    );
  }

  Widget _pastilleSolde(AppPalette palette, SoldeScolarite s) {
    final couleur = s.estSolde ? palette.succes : palette.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        s.estSolde ? 'Soldé' : 'Doit ${_formaterMontant(s.solde)}',
        style: TextStyle(color: couleur, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _EtatErreur extends StatelessWidget {
  const _EtatErreur({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
