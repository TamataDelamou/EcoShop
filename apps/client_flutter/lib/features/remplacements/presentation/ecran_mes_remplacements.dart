import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../export_pdf/data/emploi_du_temps_pdf_builder.dart';
import '../../export_pdf/presentation/ecran_apercu_pdf.dart';
import '../../planification/application/planification_providers.dart';
import '../../themes/application/theme_providers.dart';
import '../data/remplacements_repository.dart';
import '../domain/remplacement.dart';
import 'elements_remplacements.dart';

/// Enseignant (REG-41) : prévenir d'une absence, ses absences et leur
/// validation, les remplacements et études qu'il doit assurer.
class EcranMesRemplacements extends ConsumerWidget {
  const EcranMesRemplacements({super.key, required this.etablissementId, required this.profileId, this.anneeId});

  final String etablissementId;
  final String profileId;

  /// Année en cours : pour imprimer son emploi du temps.
  final String? anneeId;

  Future<void> _imprimer(BuildContext context, WidgetRef ref) async {
    final etablissement = ref.read(etablissementActifProvider);
    final annee = anneeId;
    if (etablissement == null || annee == null) return;
    try {
      final seances = await ref.read(emploisDeEnseignantProvider(
        (enseignantProfileId: profileId, etablissementId: etablissementId, anneeId: annee),
      ).future);
      final octets = await construireEmploiDuTempsPdf(
        seances: seances,
        etablissement: etablissement,
        titre: 'Mon emploi du temps',
        variante: ref.read(themeVariantProvider),
        identite: await ref.read(identitePdfProvider.future),
        parEnseignant: true,
      );
      if (!context.mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => EcranApercuPdf(titre: 'Mon emploi du temps', octets: octets, nomFichier: 'mon-emploi-du-temps.pdf'),
      ));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Emploi du temps indisponible pour le moment.')));
      }
    }
  }

  Future<void> _retirer(BuildContext context, WidgetRef ref, AbsenceEnseignant a) async {
    try {
      await ref.read(remplacementsRepositoryProvider).retirerAbsence(a.id);
      ref.invalidate(mesRemplacementsProvider(etablissementId));
    } on ErreurRemplacement catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mes = ref.watch(mesRemplacementsProvider(etablissementId));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Absences et remplacements'),
        actions: [
          if (anneeId != null)
            IconButton(
              tooltip: 'Mon emploi du temps en PDF',
              onPressed: () => _imprimer(context, ref),
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('prevenir_absence'),
        onPressed: () async {
          final ok = await formulaireAbsence(context, etablissementId: etablissementId, enseignantId: profileId);
          if (ok == true) ref.invalidate(mesRemplacementsProvider(etablissementId));
        },
        icon: const Icon(Icons.event_busy_outlined),
        label: const Text('Prévenir d’une absence'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(mesRemplacementsProvider(etablissementId)),
        child: mes.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(e is ErreurRemplacement ? e.message : 'Indisponible pour le moment.', textAlign: TextAlign.center),
            ),
          ]),
          data: (m) => ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
            Text('À assurer', style: theme.textTheme.titleSmall),
            if (m.aAssurer.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Aucun remplacement prévu.'))
            else
              for (final r in m.aAssurer)
                Card(
                  child: ListTile(
                    key: Key('a_assurer_${r.id}'),
                    leading: Icon(r.solution == SolutionSeance.etude ? Icons.menu_book_outlined : Icons.swap_horiz),
                    title: Text('${r.matiere ?? 'Cours'} — ${r.classe}'),
                    subtitle: Text([
                      '${jourLisible(r.date)}, ${r.debut} – ${r.fin}',
                      if (r.salle != null) 'salle ${r.salle}',
                      r.solution == SolutionSeance.etude ? 'étude surveillée' : 'remplacement',
                      if (r.absent != null) 'pour ${r.absent}',
                      if (r.note != null) r.note!,
                    ].join(' · ')),
                  ),
                ),
            const SizedBox(height: 16),
            Text('Mes absences', style: theme.textTheme.titleSmall),
            if (m.absences.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Aucune absence ces derniers temps.'))
            else
              for (final a in m.absences)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    a.statut == 'validee'
                        ? Icons.check_circle_outline
                        : (a.statut == 'refusee' ? Icons.cancel_outlined : Icons.hourglass_top),
                  ),
                  title: Text(a.du == a.au ? jourLisible(a.du) : 'Du ${jourLisible(a.du)} au ${jourLisible(a.au)}'),
                  subtitle: Text([
                    a.heures,
                    switch (a.statut) { 'validee' => 'validée', 'refusee' => 'refusée', _ => 'en attente de la direction' },
                    if (a.motif != null) a.motif!,
                  ].join(' · ')),
                  trailing: a.aValider
                      ? IconButton(tooltip: 'Retirer', onPressed: () => _retirer(context, ref, a), icon: const Icon(Icons.delete_outline))
                      : null,
                ),
          ]),
        ),
      ),
    );
  }
}

/// Changements de l'emploi du temps d'une classe (REG-41) : cours remplacés,
/// en étude, déplacés ou annulés, aujourd'hui et les deux semaines à venir.
class EcranChangementsClasse extends ConsumerWidget {
  const EcranChangementsClasse({super.key, this.classeId, this.ficheId}) : assert(classeId != null || ficheId != null);

  final String? classeId;
  final String? ficheId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final changements =
        ficheId != null ? ref.watch(changementsFicheProvider(ficheId!)) : ref.watch(changementsClasseProvider(classeId!));
    void relire() {
      if (ficheId != null) {
        ref.invalidate(changementsFicheProvider(ficheId!));
      } else {
        ref.invalidate(changementsClasseProvider(classeId!));
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Changements d’emploi du temps')),
      body: RefreshIndicator(
        onRefresh: () async => relire(),
        child: changements.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(e is ErreurRemplacement ? e.message : 'Indisponible pour le moment.', textAlign: TextAlign.center),
            ),
          ]),
          data: (liste) => liste.isEmpty
              ? ListView(children: const [
                  Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Aucun changement prévu : l’emploi du temps habituel s’applique.',
                        key: Key('aucun_changement'), textAlign: TextAlign.center),
                  ),
                ])
              : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
                  for (final c in liste)
                    Card(
                      child: ListTile(
                        key: Key('changement_${c.id}'),
                        leading: Icon(switch (c.solution) {
                          SolutionSeance.remplacement => Icons.swap_horiz,
                          SolutionSeance.etude => Icons.menu_book_outlined,
                          SolutionSeance.deplace => Icons.update,
                          SolutionSeance.annule => Icons.event_busy_outlined,
                        }, color: couleurSolution(context, c.solution)),
                        title: Text('${c.matiere ?? 'Cours'} — ${jourLisible(c.date)}, ${c.debut}'),
                        subtitle: Text([
                          switch (c.solution) {
                            SolutionSeance.remplacement => 'Remplacé${c.remplacant == null ? '' : ' par ${c.remplacant}'}',
                            SolutionSeance.etude => 'Étude surveillée',
                            SolutionSeance.deplace =>
                              'Déplacé${c.deplaceLe == null ? '' : ' au ${jourLisible(c.deplaceLe!).toLowerCase()} à ${c.deplaceDebut ?? ''}'}',
                            SolutionSeance.annule => 'Annulé',
                          },
                          if (c.salle != null) 'salle ${c.salle}',
                          if (c.note != null) c.note!,
                        ].join(' · ')),
                      ),
                    ),
                ]),
        ),
      ),
    );
  }
}
