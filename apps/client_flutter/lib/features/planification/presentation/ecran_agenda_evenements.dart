import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';

import '../../../core/sync/device_id_provider.dart';
import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/planification_providers.dart';
import '../domain/enums_planification.dart';
import '../domain/evenement_agenda.dart';

/// Agenda des événements d'établissement (M11) — examens, conseils de
/// classe, réunions, sorties, jours fériés. Vue personnel (tout
/// l'établissement) ou vue élève/parent (classe concernée), selon les
/// paramètres fournis par l'appelant.
class EcranAgendaEvenements extends ConsumerWidget {
  const EcranAgendaEvenements({
    super.key,
    required this.anneeId,
    this.etablissementId,
    this.classeId,
    this.peutCreer = false,
  }) : assert(etablissementId != null || classeId != null, 'Fournir etablissementId ou classeId.');

  final String anneeId;
  final String? etablissementId;
  final String? classeId;
  final bool peutCreer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final evenements = etablissementId != null
        ? ref.watch(evenementsEtablissementProvider((etablissementId: etablissementId!, anneeId: anneeId)))
        : ref.watch(evenementsDeClasseProvider((classeId: classeId!, anneeId: anneeId)));

    return Scaffold(
      appBar: AppBar(title: const Text('Agenda')),
      floatingActionButton: peutCreer && etablissementId != null
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Nouvel événement'),
              onPressed: () => _ouvrirFormulaire(context, ref),
            )
          : null,
      body: evenements.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: List.generate(4, (_) => const ShimmerCarteListe()),
        ),
        error: (erreur, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Agenda indisponible hors connexion pour le moment.'),
          ),
        ),
        data: (liste) {
          if (liste.isEmpty) return const Center(child: Text('Aucun événement planifié.'));
          final triee = [...liste]..sort((a, b) => a.dateDebut.compareTo(b.dateDebut));
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: triee.length,
            itemBuilder: (context, i) => EntreeAnimee(index: i, enfant: _CarteEvenement(evenement: triee[i])),
          );
        },
      ),
    );
  }

  Future<void> _ouvrirFormulaire(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _FormulaireEvenement(etablissementId: etablissementId!, anneeId: anneeId),
    );
    ref.invalidate(evenementsEtablissementProvider((etablissementId: etablissementId!, anneeId: anneeId)));
  }
}

class _CarteEvenement extends StatelessWidget {
  const _CarteEvenement({required this.evenement});

  final EvenementAgenda evenement;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(_icone(evenement.type), color: _couleur(context, evenement.type)),
        title: Text(evenement.titre),
        subtitle: Text(
          [
            _formatPeriode(evenement),
            if (evenement.lieu != null && evenement.lieu!.isNotEmpty) evenement.lieu!,
          ].join(' · '),
        ),
        trailing: evenement.rappel ? const Icon(Icons.notifications_active_outlined, size: 18) : null,
      ),
    );
  }

  static String _formatPeriode(EvenementAgenda e) {
    final debut = _formatDate(e.dateDebut);
    final fin = _formatDate(e.dateFin);
    final periode = debut == fin ? debut : '$debut → $fin';
    return e.heureDebut == null ? periode : '$periode · ${e.heureDebut}';
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';

  static IconData _icone(TypeEvenementAgenda type) => switch (type) {
        TypeEvenementAgenda.examen => Icons.edit_document,
        TypeEvenementAgenda.reunion => Icons.groups_outlined,
        TypeEvenementAgenda.conseilClasse => Icons.forum_outlined,
        TypeEvenementAgenda.sortie => Icons.directions_bus_outlined,
        TypeEvenementAgenda.fete => Icons.celebration_outlined,
        TypeEvenementAgenda.rappel => Icons.notifications_outlined,
        TypeEvenementAgenda.autre => Icons.event_outlined,
      };

  static Color _couleur(BuildContext context, TypeEvenementAgenda type) => switch (type) {
        TypeEvenementAgenda.examen => context.palette.erreur,
        TypeEvenementAgenda.conseilClasse => context.palette.accent,
        TypeEvenementAgenda.fete => context.palette.succes,
        _ => context.palette.primaire,
      };
}

class _FormulaireEvenement extends ConsumerStatefulWidget {
  const _FormulaireEvenement({required this.etablissementId, required this.anneeId});

  final String etablissementId;
  final String anneeId;

  @override
  ConsumerState<_FormulaireEvenement> createState() => _FormulaireEvenementState();
}

class _FormulaireEvenementState extends ConsumerState<_FormulaireEvenement> {
  final _titreCtrl = TextEditingController();
  final _lieuCtrl = TextEditingController();
  TypeEvenementAgenda _type = TypeEvenementAgenda.reunion;
  DateTime _date = DateTime.now();
  bool _rappel = false;
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _titreCtrl.dispose();
    _lieuCtrl.dispose();
    super.dispose();
  }

  Future<void> _choisirDate() async {
    final choisie = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_date.year - 1),
      lastDate: DateTime(_date.year + 2),
    );
    if (choisie != null) setState(() => _date = choisie);
  }

  Future<void> _enregistrer() async {
    if (_titreCtrl.text.trim().isEmpty) {
      setState(() => _erreur = 'Le titre est requis.');
      return;
    }

    setState(() {
      _enCours = true;
      _erreur = null;
    });

    try {
      final deviceId = await ref.read(deviceIdProvider.future);
      final evenement = construireEvenement(
        etablissementId: widget.etablissementId,
        anneeScolaireId: widget.anneeId,
        titre: _titreCtrl.text.trim(),
        type: _type,
        dateDebut: _date,
        dateFin: _date,
        lieu: _lieuCtrl.text.trim().isEmpty ? null : _lieuCtrl.text.trim(),
        rappel: _rappel,
        deviceId: deviceId,
      );
      await ref.read(planificationRepositoryProvider).enregistrerEvenement(evenement);
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
      title: const Text('Nouvel événement'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: _titreCtrl, decoration: const InputDecoration(labelText: 'Titre')),
            const SizedBox(height: 12),
            DropdownButtonFormField<TypeEvenementAgenda>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final t in TypeEvenementAgenda.values) DropdownMenuItem(value: t, child: Text(t.libelle)),
              ],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date'),
              subtitle: Text('${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}'),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: _choisirDate,
            ),
            TextField(controller: _lieuCtrl, decoration: const InputDecoration(labelText: 'Lieu (optionnel)')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Rappel (via Notifications)'),
              value: _rappel,
              onChanged: (v) => setState(() => _rappel = v),
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 8),
              Text(_erreur!, style: TextStyle(color: context.palette.erreur)),
            ],
          ],
        ),
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
              : const Text('Enregistrer'),
        ),
      ],
    );
  }
}
