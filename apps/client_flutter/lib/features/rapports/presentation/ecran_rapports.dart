import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/rapports_providers.dart';
import '../domain/enums_rapports.dart';
import '../domain/rapport.dart';
import 'widgets/pastilles_rapports.dart';

/// Rapports générés d'un établissement (M10, vue personnel) — demande de
/// génération différée, tolérante hors connexion (`demandeHorsLigne`,
/// contrat M10 §5).
class EcranRapports extends ConsumerWidget {
  const EcranRapports({super.key, required this.etablissementId, required this.anneeId});

  final String etablissementId;
  final String anneeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rapports = ref.watch(rapportsEtablissementProvider(etablissementId));

    return Scaffold(
      appBar: AppBar(title: const Text('Rapports générés')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle demande'),
        onPressed: () => _ouvrirFormulaire(context, ref),
      ),
      body: rapports.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: List.generate(3, (_) => const ShimmerCarteListe()),
        ),
        error: (erreur, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Rapports indisponibles hors connexion pour le moment.'),
          ),
        ),
        data: (liste) => liste.isEmpty
            ? const Center(child: Text('Aucun rapport demandé.'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: liste.length,
                itemBuilder: (context, i) => EntreeAnimee(index: i, enfant: _CarteRapport(rapport: liste[i])),
              ),
      ),
    );
  }

  Future<void> _ouvrirFormulaire(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _FormulaireRapport(etablissementId: etablissementId, anneeId: anneeId),
    );
    ref.invalidate(rapportsEtablissementProvider(etablissementId));
  }
}

/// Rapports d'une fiche élève (M10, vue parent/élève) — **consultation
/// seule** : une demande directe par un parent/élève est refusée par la RLS
/// (`rapports.generer` réservé au personnel), l'IHM n'affiche donc aucune
/// action de création.
class EcranMesRapports extends ConsumerWidget {
  const EcranMesRapports({super.key, required this.ficheEleveId});

  final String ficheEleveId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rapports = ref.watch(rapportsDeFicheProvider(ficheEleveId));

    return Scaffold(
      appBar: AppBar(title: const Text('Mes rapports')),
      body: rapports.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: List.generate(3, (_) => const ShimmerCarteListe()),
        ),
        error: (erreur, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Rapports indisponibles hors connexion pour le moment.'),
          ),
        ),
        data: (liste) => liste.isEmpty
            ? const Center(child: Text('Aucun rapport disponible pour le moment.'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: liste.length,
                itemBuilder: (context, i) => EntreeAnimee(index: i, enfant: _CarteRapport(rapport: liste[i])),
              ),
      ),
    );
  }
}

class _CarteRapport extends StatelessWidget {
  const _CarteRapport({required this.rapport});

  final Rapport rapport;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(_icone(rapport.format), color: context.palette.primaire),
        title: Text(rapport.type),
        subtitle: Text(rapport.format.libelle + (rapport.demandeHorsLigne ? ' · déposé hors ligne' : '')),
        trailing: PastilleStatutRapport(statut: rapport.statut),
      ),
    );
  }

  static IconData _icone(TypeExport format) => switch (format) {
        TypeExport.pdf => Icons.picture_as_pdf_outlined,
        TypeExport.excel => Icons.table_chart_outlined,
        TypeExport.csv => Icons.grid_on_outlined,
        TypeExport.json => Icons.data_object_outlined,
      };
}

class _FormulaireRapport extends ConsumerStatefulWidget {
  const _FormulaireRapport({required this.etablissementId, required this.anneeId});

  final String etablissementId;
  final String anneeId;

  @override
  ConsumerState<_FormulaireRapport> createState() => _FormulaireRapportState();
}

class _FormulaireRapportState extends ConsumerState<_FormulaireRapport> {
  static const _types = ['bulletin', 'releve_notes', 'statistiques_globales', 'personnalise', 'resume_executif'];

  String _type = _types.first;
  TypeExport _format = TypeExport.pdf;
  bool _enCours = false;
  String? _erreur;

  Future<void> _enregistrer() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });

    try {
      final rapport = construireDemandeRapport(
        etablissementId: widget.etablissementId,
        anneeScolaireId: widget.anneeId,
        type: _type,
        format: _format,
      );
      await ref.read(rapportsRepositoryProvider).demanderRapport(rapport);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _erreur = 'Envoi impossible : $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouvelle demande de rapport'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Type de rapport'),
            items: [for (final t in _types) DropdownMenuItem(value: t, child: Text(t))],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<TypeExport>(
            initialValue: _format,
            decoration: const InputDecoration(labelText: 'Format'),
            items: [
              for (final f in TypeExport.values) DropdownMenuItem(value: f, child: Text(f.libelle)),
            ],
            onChanged: (v) => setState(() => _format = v ?? _format),
          ),
          if (_erreur != null) ...[
            const SizedBox(height: 8),
            Text(_erreur!, style: TextStyle(color: context.palette.erreur)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _enCours ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _enCours ? null : _enregistrer,
          child: _enCours
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Demander'),
        ),
      ],
    );
  }
}
