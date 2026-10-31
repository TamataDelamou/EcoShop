import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../revision/presentation/ecran_banque_questions.dart';
import 'referentiel_back_office.dart';
import 'referentiel_back_office_providers.dart';
import 'referentiel_back_office_repository.dart';

const _uuid = Uuid();

void _message(BuildContext context, String texte) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texte)));

/// Exécute une écriture et rafraîchit ; dit si elle est partie ou gardée.
Future<bool> _executer(BuildContext context, WidgetRef ref, Future<bool> Function() action, {String? pays}) async {
  try {
    final recu = await action();
    ref.invalidate(paysBackOfficeProvider);
    if (pays != null) ref.invalidate(referentielPaysProvider(pays));
    if (!recu && context.mounted) _message(context, 'Pas de réseau : gardé sur ce téléphone, envoyé au retour du réseau.');
    return true;
  } catch (e) {
    if (context.mounted) _message(context, ReferentielBackOfficeRepository.traduire(e).message);
    return false;
  }
}

Widget _pastille(BuildContext context, String texte, Color fond) => Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(10)),
      child: Text(texte, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );

Widget _statut(BuildContext context, bool publie) {
  final s = Theme.of(context).colorScheme;
  return _pastille(context, publie ? 'Publié' : 'Brouillon', publie ? s.secondaryContainer : s.surfaceContainerHighest);
}

/// Formulaire simple : une suite de champs, rendus par le dialogue.
class _Champ {
  _Champ(this.cle, this.libelle, {String? valeur, this.aide, this.nombre = false, this.lignes = 1, this.requis = true})
      : controleur = TextEditingController(text: valeur ?? '');

  final String cle;
  final String libelle;
  final String? aide;
  final bool nombre;
  final int lignes;
  final bool requis;
  final TextEditingController controleur;

  String get texte => controleur.text.trim();
  String? get texteOuNul => texte.isEmpty ? null : texte;
  int? get entier => int.tryParse(texte);
}

Future<bool> _formulaire(BuildContext context, String titre, List<_Champ> champs, {List<Widget> Function(StateSetter)? extras}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setState) => AlertDialog(
        title: Text(titre),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final c in champs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    key: Key('champ_${c.cle}'),
                    controller: c.controleur,
                    keyboardType: c.nombre ? const TextInputType.numberWithOptions(signed: true) : null,
                    maxLines: c.lignes,
                    decoration: InputDecoration(labelText: c.libelle, helperText: c.aide, helperMaxLines: 3),
                  ),
                ),
              ...?extras?.call(setState),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Annuler')),
          FilledButton(
            key: const Key('formulaire_valider'),
            onPressed: () {
              final manque = champs.where((c) => (c.requis && c.texte.isEmpty) || (c.nombre && c.texte.isNotEmpty && c.entier == null));
              if (manque.isNotEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('À compléter : ${manque.first.libelle}')));
                return;
              }
              Navigator.of(d).pop(true);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );
  return ok == true;
}

Future<bool> _confirmer(BuildContext context, String question, {String action = 'Confirmer'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        content: Text(question),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Annuler')),
          FilledButton(key: const Key('confirmer'), onPressed: () => Navigator.of(d).pop(true), child: Text(action)),
        ],
      ),
    ) ==
    true;

// ---------------------------------------------------------------------------
// Liste des pays
// ---------------------------------------------------------------------------

/// « Pays et programmes » : le référentiel pédagogique de chaque pays,
/// brouillons compris (Administrateur de contenu, Administrateur GSG).
class EcranBackOfficeReferentiel extends ConsumerWidget {
  const EcranBackOfficeReferentiel({super.key});

  Future<void> _ajouterPays(BuildContext context, WidgetRef ref) async {
    final fiche = await _dialoguePays(context, null);
    if (fiche == null || !context.mounted) return;
    final ok = await _executer(context, ref, () => ref.read(referentielBackOfficeRepositoryProvider).enregistrerPays(fiche));
    if (ok && context.mounted) {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EcranPaysBackOffice(code: fiche.code)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liste = ref.watch(paysBackOfficeProvider);
    final schema = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Pays et programmes')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('bo_ajouter_pays'),
        onPressed: () => _ajouterPays(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter un pays'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(paysBackOfficeProvider),
        child: liste.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(padding: const EdgeInsets.all(24), children: [
            Text(ReferentielBackOfficeRepository.traduire(e).message, textAlign: TextAlign.center),
          ]),
          data: (l) => ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
            Text(
              'Un pays en brouillon reste invisible des écoles et des familles. Vérifiez chaque point sur les textes '
              'officiels du pays, puis publiez-le.',
              style: TextStyle(color: schema.onSurfaceVariant),
            ),
            for (final zone in ZonePays.values)
              if (l.where((p) => p.zone == zone).toList() case final pays when pays.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
                  child: Text(zone.libelle.toUpperCase(), style: Theme.of(context).textTheme.labelLarge),
                ),
                for (final p in pays)
                  Card(
                    child: ListTile(
                      key: ValueKey('bo_pays_${p.code}'),
                      leading: CircleAvatar(child: Text(p.code)),
                      title: Text(p.nom),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${systemesEducatifs[p.typeSysteme] ?? p.typeSysteme} · ${p.niveaux} niveaux · '
                            '${p.examens} examens · ${p.programmes} programmes'),
                        const SizedBox(height: 4),
                        Row(children: [
                          _statut(context, p.publie),
                          if (p.aVerifier) _pastille(context, 'À vérifier', schema.tertiaryContainer),
                          if (p.publie && p.brouillons > 0) _pastille(context, '${p.brouillons} à publier', schema.surfaceContainerHighest),
                        ]),
                      ]),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => EcranPaysBackOffice(code: p.code),
                      )),
                    ),
                  ),
              ],
          ]),
        ),
      ),
    );
  }
}

Future<FichePays?> _dialoguePays(BuildContext context, FichePays? x) async {
  final code = _Champ('code', 'Code du pays (ISO, 2 lettres)', valeur: x?.code);
  final nom = _Champ('nom', 'Nom', valeur: x?.nom);
  final langue = _Champ('langue', 'Langue d’enseignement (fr, en, pt, ar)', valeur: x?.langue ?? 'fr');
  final devise = _Champ('devise', 'Devise (XOF, GNF, NGN…)', valeur: x?.devise ?? 'XOF');
  final organisme = _Champ('organisme', 'Organisme des examens', valeur: x?.organisme, requis: false);
  final sources = _Champ('sources', 'Sources consultées', valeur: x?.sources, lignes: 3, requis: false);
  final points = _Champ('points', 'Points à vérifier', valeur: x?.pointsAVerifier, lignes: 3, requis: false,
      aide: 'Videz ce champ quand tout est confirmé sur les textes officiels : la publication l’exige.');
  var systeme = x?.typeSysteme ?? 'francophone_cfa';
  var zone = x?.zone ?? ZonePays.cedeao;
  final champs = [if (x == null) code, nom, langue, devise, organisme, sources, points];
  final ok = await _formulaire(context, x == null ? 'Nouveau pays' : 'Fiche du pays', champs, extras: (setState) => [
        DropdownButtonFormField<String>(
          initialValue: systeme,
          decoration: const InputDecoration(labelText: 'Famille de système'),
          items: [for (final e in systemesEducatifs.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => setState(() => systeme = v ?? systeme),
        ),
        DropdownButtonFormField<ZonePays>(
          initialValue: zone,
          decoration: const InputDecoration(labelText: 'Zone'),
          items: [for (final z in ZonePays.values) DropdownMenuItem(value: z, child: Text(z.libelle))],
          onChanged: (v) => setState(() => zone = v ?? zone),
        ),
      ]);
  if (!ok) return null;
  return FichePays(
    code: (x?.code ?? code.texte).toUpperCase(),
    nom: nom.texte,
    typeSysteme: systeme,
    langue: langue.texte.toLowerCase(),
    organisme: organisme.texteOuNul,
    devise: devise.texte.toUpperCase(),
    zone: zone,
    sources: sources.texteOuNul,
    pointsAVerifier: points.texteOuNul,
    publie: x?.publie ?? false,
  );
}

// ---------------------------------------------------------------------------
// Un pays
// ---------------------------------------------------------------------------

class EcranPaysBackOffice extends ConsumerWidget {
  const EcranPaysBackOffice({super.key, required this.code});

  final String code;

  ReferentielBackOfficeRepository _depot(WidgetRef ref) => ref.read(referentielBackOfficeRepositoryProvider);

  Future<void> _publier(BuildContext context, WidgetRef ref, ReferentielPays r) async {
    final ok = await _confirmer(
      context,
      r.pays.publie
          ? 'Publier les ${r.brouillons} élément(s) en brouillon ? Ils deviennent visibles des écoles.'
          : 'Publier ${r.pays.nom} ? Le pays sera proposé à l’ouverture d’une école, et ses examens aux familles.',
      action: 'Publier',
    );
    if (!ok || !context.mounted) return;
    try {
      await _depot(ref).publierPays(code);
      ref
        ..invalidate(referentielPaysProvider(code))
        ..invalidate(paysBackOfficeProvider);
      if (context.mounted) _message(context, '${r.pays.nom} publié.');
    } catch (e) {
      if (context.mounted) _message(context, ReferentielBackOfficeRepository.traduire(e).message);
    }
  }

  Future<void> _supprimer(BuildContext context, WidgetRef ref, String type, String id, String nom) async {
    if (!await _confirmer(context, 'Supprimer « $nom » ?', action: 'Supprimer') || !context.mounted) return;
    try {
      await _depot(ref).supprimer(type, id);
      ref.invalidate(referentielPaysProvider(code));
    } catch (e) {
      if (context.mounted) _message(context, ReferentielBackOfficeRepository.traduire(e).message);
    }
  }

  Future<void> _cycle(BuildContext context, WidgetRef ref, ReferentielPays r, CycleBackOffice? x) async {
    final cCode = _Champ('cycle_code', 'Code (primaire, college…)', valeur: x?.code);
    final nom = _Champ('cycle_nom', 'Nom', valeur: x?.nom);
    final ordre = _Champ('cycle_ordre', 'Ordre', valeur: '${x?.ordre ?? r.cycles.length + 1}', nombre: true);
    final iMin = _Champ('cycle_isced_min', 'ISCED du', valeur: '${x?.iscedMin ?? 1}', nombre: true,
        aide: '0 préscolaire, 1 primaire, 2 collège, 3 lycée');
    final iMax = _Champ('cycle_isced_max', 'ISCED au', valeur: '${x?.iscedMax ?? 1}', nombre: true);
    final aMin = _Champ('cycle_age_min', 'Âge d’entrée', valeur: x?.ageMin?.toString(), nombre: true, requis: false);
    final aMax = _Champ('cycle_age_max', 'Âge de sortie', valeur: x?.ageMax?.toString(), nombre: true, requis: false);
    final duree = _Champ('cycle_duree', 'Durée (années)', valeur: x?.duree?.toString(), nombre: true, requis: false);
    if (!await _formulaire(context, x == null ? 'Nouveau cycle' : 'Cycle', [cCode, nom, ordre, iMin, iMax, aMin, aMax, duree]) ||
        !context.mounted) {
      return;
    }
    await _executer(
      context,
      ref,
      () => _depot(ref).enregistrerCycle(
            code,
            CycleBackOffice(
              id: x?.id ?? _uuid.v4(),
              code: cCode.texte,
              nom: nom.texte,
              ordre: ordre.entier ?? 1,
              iscedMin: iMin.entier ?? 1,
              iscedMax: iMax.entier ?? 1,
              ageMin: aMin.entier,
              ageMax: aMax.entier,
              duree: duree.entier,
            ),
          ),
      pays: code,
    );
  }

  Future<void> _niveau(BuildContext context, WidgetRef ref, ReferentielPays r, CycleBackOffice cycle, NiveauBackOffice? x) async {
    final nCode = _Champ('niveau_code', 'Code (CP1, 6e, JSS1…)', valeur: x?.code);
    final nom = _Champ('niveau_nom', 'Nom', valeur: x?.nom);
    final rang = _Champ('niveau_rang', 'Rang commun', valeur: '${x?.grade ?? r.prochainRang}', nombre: true,
        aide: '1 = première année du primaire dans tous les pays ; préscolaire 0, -1, -2. Les rangs se suivent sans trou.');
    final ordre = _Champ('niveau_ordre', 'Ordre dans le cycle', valeur: '${x?.ordre ?? cycle.niveaux.length + 1}', nombre: true);
    var examen = x?.examinateur ?? false;
    final ok = await _formulaire(context, x == null ? 'Nouveau niveau · ${cycle.nom}' : 'Niveau', [nCode, nom, rang, ordre],
        extras: (setState) => [
              if (x?.utilise ?? false)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('Des classes utilisent ce niveau : son rang ne change plus.'),
                ),
              SwitchListTile(
                key: const Key('niveau_examen'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Classe d’examen national'),
                value: examen,
                onChanged: (v) => setState(() => examen = v),
              ),
            ]);
    if (!ok || !context.mounted) return;
    await _executer(
      context,
      ref,
      () => _depot(ref).enregistrerNiveau(NiveauBackOffice(
            id: x?.id ?? _uuid.v4(),
            cycleId: cycle.id,
            code: nCode.texte,
            nom: nom.texte,
            grade: rang.entier ?? 1,
            isced: x?.isced ?? cycle.iscedMin,
            ordre: ordre.entier ?? 1,
            examinateur: examen,
          )),
      pays: code,
    );
  }

  Future<void> _examen(BuildContext context, WidgetRef ref, ReferentielPays r, ExamenBackOffice? x) async {
    final eCode = _Champ('examen_code', 'Sigle (BEPC, BAC, WASSCE…)', valeur: x?.code);
    final nom = _Champ('examen_nom', 'Nom complet', valeur: x?.nom);
    final organisme = _Champ('examen_organisme', 'Organisme', valeur: x?.organisme, requis: false);
    String? cycleId = x?.cycleId ?? r.cycles.lastOrNull?.id;
    int? mois = x?.mois;
    final ok = await _formulaire(context, x == null ? 'Nouvel examen' : 'Examen', [eCode, nom, organisme], extras: (setState) => [
          DropdownButtonFormField<String?>(
            initialValue: cycleId,
            decoration: const InputDecoration(labelText: 'Fin du cycle'),
            items: [
              const DropdownMenuItem<String?>(child: Text('Aucun')),
              for (final c in r.cycles) DropdownMenuItem<String?>(value: c.id, child: Text(c.nom)),
            ],
            onChanged: (v) => setState(() => cycleId = v),
          ),
          DropdownButtonFormField<int?>(
            initialValue: mois,
            decoration: const InputDecoration(labelText: 'Mois habituel de la session'),
            items: [
              const DropdownMenuItem<int?>(child: Text('Inconnu')),
              for (var m = 1; m <= 12; m++) DropdownMenuItem<int?>(value: m, child: Text(moisDeLAnnee[m - 1])),
            ],
            onChanged: (v) => setState(() => mois = v),
          ),
        ]);
    if (!ok || !context.mounted) return;
    await _executer(
      context,
      ref,
      () => _depot(ref).enregistrerExamen(
            code,
            ExamenBackOffice(
              id: x?.id ?? _uuid.v4(),
              code: eCode.texte,
              nom: nom.texte,
              organisme: organisme.texteOuNul,
              mois: mois,
              cycleId: cycleId,
            ),
          ),
      pays: code,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etat = ref.watch(referentielPaysProvider(code));
    final schema = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(etat.valueOrNull?.pays.nom ?? code),
        actions: [
          if (etat.valueOrNull case final r?)
            IconButton(
              key: const Key('bo_modifier_pays'),
              tooltip: 'Fiche du pays',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final fiche = await _dialoguePays(context, r.pays);
                if (fiche != null && context.mounted) {
                  await _executer(context, ref, () => _depot(ref).enregistrerPays(fiche), pays: code);
                }
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(referentielPaysProvider(code)),
        child: etat.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(padding: const EdgeInsets.all(24), children: [
            Text(ReferentielBackOfficeRepository.traduire(e).message, textAlign: TextAlign.center),
          ]),
          data: (r) => ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            Row(children: [
              _statut(context, r.pays.publie),
              Expanded(
                child: Text(
                  '${systemesEducatifs[r.pays.typeSysteme] ?? r.pays.typeSysteme} · ${r.pays.langue} · ${r.pays.devise}'
                  '${r.pays.organisme == null ? '' : ' · ${r.pays.organisme}'}',
                ),
              ),
            ]),
            if (r.pays.pointsAVerifier case final p?)
              Card(
                color: schema.tertiaryContainer,
                child: ListTile(
                  key: const Key('bo_points_a_verifier'),
                  leading: const Icon(Icons.fact_check_outlined),
                  title: const Text('À vérifier sur les textes officiels'),
                  subtitle: Text(p),
                ),
              ),
            if (r.pays.sources case final s?)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Sources : $s', style: TextStyle(color: schema.onSurfaceVariant, fontSize: 12)),
              ),
            const SizedBox(height: 12),
            Text('Contrôle', style: Theme.of(context).textTheme.titleSmall),
            if (r.controle.isEmpty) const ListTile(dense: true, leading: Icon(Icons.check_circle, color: Colors.green), title: Text('Rien à signaler.')),
            for (final c in r.controle)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(c.bloquant ? Icons.block : Icons.info_outline, color: c.bloquant ? schema.error : schema.tertiary),
                title: Text(c.message),
              ),
            if (!r.pays.publie || r.brouillons > 0)
              FilledButton.icon(
                key: const Key('bo_publier_pays'),
                onPressed: r.publiable ? () => _publier(context, ref, r) : null,
                icon: const Icon(Icons.public),
                label: Text(r.pays.publie ? 'Publier les brouillons (${r.brouillons})' : 'Publier le pays'),
              ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: Text('Cycles et niveaux', style: Theme.of(context).textTheme.titleSmall)),
              TextButton.icon(
                key: const Key('bo_ajouter_cycle'),
                onPressed: () => _cycle(context, ref, r, null),
                icon: const Icon(Icons.add),
                label: const Text('Cycle'),
              ),
            ]),
            for (final c in r.cycles)
              Card(
                child: ExpansionTile(
                  key: ValueKey('bo_cycle_${c.code}'),
                  title: Text(c.nom),
                  subtitle: Row(children: [
                    _statut(context, c.publie),
                    Expanded(child: Text('${c.niveaux.length} niveaux${c.ageMin == null ? '' : ' · ${c.ageMin}-${c.ageMax} ans'}')),
                  ]),
                  children: [
                    for (final n in c.niveaux)
                      ListTile(
                        key: ValueKey('bo_niveau_${n.code}'),
                        dense: true,
                        leading: CircleAvatar(radius: 14, child: Text('${n.grade}', style: const TextStyle(fontSize: 12))),
                        title: Text('${n.code} · ${n.nom}'),
                        subtitle: Text([
                          n.publie ? 'Publié' : 'Brouillon',
                          if (n.examinateur) 'classe d’examen',
                          if (n.utilise) 'utilisé par des classes',
                          n.programmes.isEmpty
                              ? 'sans programme'
                              : '${n.programmes.fold<int>(0, (s, p) => s + p.matieres.length)} matières',
                        ].join(' · ')),
                        onTap: () => _niveau(context, ref, r, c, n),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            key: ValueKey('bo_programme_${n.code}'),
                            tooltip: 'Programme national',
                            icon: const Icon(Icons.menu_book_outlined),
                            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                              builder: (_) => EcranProgrammeNational(pays: code, niveauId: n.id),
                            )),
                          ),
                          if (!n.publie && !n.utilise)
                            IconButton(
                              tooltip: 'Supprimer',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _supprimer(context, ref, 'niveau', n.id, n.nom),
                            ),
                        ]),
                      ),
                    OverflowBar(alignment: MainAxisAlignment.end, children: [
                      if (!c.publie && c.niveaux.isEmpty)
                        TextButton(onPressed: () => _supprimer(context, ref, 'cycle', c.id, c.nom), child: const Text('Supprimer')),
                      TextButton(onPressed: () => _cycle(context, ref, r, c), child: const Text('Modifier le cycle')),
                      TextButton.icon(
                        key: ValueKey('bo_ajouter_niveau_${c.code}'),
                        onPressed: () => _niveau(context, ref, r, c, null),
                        icon: const Icon(Icons.add),
                        label: const Text('Niveau'),
                      ),
                    ]),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: Text('Examens nationaux', style: Theme.of(context).textTheme.titleSmall)),
              TextButton.icon(
                key: const Key('bo_ajouter_examen'),
                onPressed: () => _examen(context, ref, r, null),
                icon: const Icon(Icons.add),
                label: const Text('Examen'),
              ),
            ]),
            for (final e in r.examens)
              Card(
                child: ListTile(
                  key: ValueKey('bo_examen_${e.code}'),
                  title: Text('${e.code} · ${e.nom}'),
                  subtitle: Text([
                    e.publie ? 'Publié' : 'Brouillon',
                    if (r.nomCycle(e.cycleId) case final c?) 'fin du cycle $c',
                    if (e.mois case final m?) 'session en ${moisDeLAnnee[m - 1]}',
                    ?e.organisme,
                  ].join(' · ')),
                  onTap: () => _examen(context, ref, r, e),
                  trailing: e.publie
                      ? null
                      : IconButton(
                          tooltip: 'Supprimer',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _supprimer(context, ref, 'examen', e.id, e.code),
                        ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Programme national d'un niveau
// ---------------------------------------------------------------------------

const _natures = {'tronc_commun': 'Tronc commun', 'specialite': 'Spécialité', 'option': 'Option'};

class EcranProgrammeNational extends ConsumerWidget {
  const EcranProgrammeNational({super.key, required this.pays, required this.niveauId});

  final String pays;
  final String niveauId;

  ReferentielBackOfficeRepository _depot(WidgetRef ref) => ref.read(referentielBackOfficeRepositoryProvider);

  Future<void> _creer(BuildContext context, WidgetRef ref, ReferentielPays r, NiveauBackOffice n) async {
    final annee = _Champ('programme_annee', 'Année scolaire du texte (facultatif)', requis: false, valeur: '');
    String? serie;
    final ok = await _formulaire(context, 'Programme national · ${n.nom}', [annee], extras: (setState) => [
          if (r.series.isNotEmpty)
            DropdownButtonFormField<String?>(
              initialValue: serie,
              decoration: const InputDecoration(labelText: 'Série'),
              items: [
                const DropdownMenuItem<String?>(child: Text('Toutes (tronc commun)')),
                for (final s in r.series) DropdownMenuItem<String?>(value: s.id, child: Text('${s.code} · ${s.nom}')),
              ],
              onChanged: (v) => setState(() => serie = v),
            ),
        ]);
    if (!ok || !context.mounted) return;
    await _executer(
      context,
      ref,
      () => _depot(ref).enregistrerProgramme(id: _uuid.v4(), niveauId: n.id, serieId: serie, annee: annee.texteOuNul),
      pays: pays,
    );
  }

  Future<void> _matiere(BuildContext context, WidgetRef ref, ProgrammeNational p, MatiereNationale? x) async {
    final mCode = _Champ('matiere_code', 'Code (MATH, FR, ENG…)', valeur: x?.code);
    final nom = _Champ('matiere_nom', 'Nom', valeur: x?.nom);
    final ordre = _Champ('matiere_ordre', 'Ordre', valeur: '${x?.ordre ?? p.matieres.length + 1}', nombre: true);
    var nature = x?.nature ?? 'tronc_commun';
    final ok = await _formulaire(context, x == null ? 'Nouvelle matière' : 'Matière', [mCode, nom, ordre], extras: (setState) => [
          DropdownButtonFormField<String>(
            initialValue: nature,
            decoration: const InputDecoration(labelText: 'Nature'),
            items: [for (final e in _natures.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => nature = v ?? nature),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Pas de coefficient ici : chaque école fixe les siens.'),
          ),
        ]);
    if (!ok || !context.mounted) return;
    await _executer(
      context,
      ref,
      () => _depot(ref).enregistrerMatiere(
            p.id,
            MatiereNationale(id: x?.id ?? _uuid.v4(), code: mCode.texte, nom: nom.texte, ordre: ordre.entier ?? 0, nature: nature),
          ),
      pays: pays,
    );
  }

  Future<void> _publier(BuildContext context, WidgetRef ref, ProgrammeNational p) async {
    if (!await _confirmer(context, 'Publier ce programme ? Les écoles pourront l’adopter et la banque de questions s’ouvre.',
            action: 'Publier') ||
        !context.mounted) {
      return;
    }
    try {
      await _depot(ref).publierProgramme(p.id);
      ref.invalidate(referentielPaysProvider(pays));
    } catch (e) {
      if (context.mounted) _message(context, ReferentielBackOfficeRepository.traduire(e).message);
    }
  }

  Future<void> _supprimer(BuildContext context, WidgetRef ref, String type, String id, String nom) async {
    if (!await _confirmer(context, 'Supprimer « $nom » ?', action: 'Supprimer') || !context.mounted) return;
    try {
      await _depot(ref).supprimer(type, id);
      ref.invalidate(referentielPaysProvider(pays));
    } catch (e) {
      if (context.mounted) _message(context, ReferentielBackOfficeRepository.traduire(e).message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(referentielPaysProvider(pays)).valueOrNull;
    final n = r?.niveaux.where((x) => x.id == niveauId).firstOrNull;
    if (r == null || n == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final schema = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('${r.pays.nom} · ${n.nom}')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('bo_creer_programme'),
        onPressed: () => _creer(context, ref, r, n),
        icon: const Icon(Icons.add),
        label: Text(n.programmes.isEmpty ? 'Créer le programme' : 'Programme d’une série'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
        Text(
          'Les matières du programme national servent aux écoles qui l’adoptent et à la banque de questions du '
          'niveau. Saisissez-les d’après le programme officiel.',
          style: TextStyle(color: schema.onSurfaceVariant),
        ),
        if (n.programmes.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Text('Aucun programme national pour ce niveau.')),
        for (final p in n.programmes)
          Card(
            key: ValueKey('bo_prog_${p.id}'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  _statut(context, p.publie),
                  Expanded(child: Text(p.nom, style: const TextStyle(fontWeight: FontWeight.w700))),
                ]),
                for (final m in p.matieres)
                  ListTile(
                    key: ValueKey('bo_matiere_${m.code}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${m.code} · ${m.nom}'),
                    subtitle: Text('${_natures[m.nature] ?? m.nature} · ${m.questions} question(s) dans la banque'),
                    onTap: () => _matiere(context, ref, p, m),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (p.publie)
                        IconButton(
                          tooltip: 'Banque de questions',
                          icon: const Icon(Icons.quiz_outlined),
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => EcranQuestionsMatiere(
                              matiereId: m.id,
                              titre: '${r.pays.nom} · ${n.nom} · ${m.nom}',
                              petitesClasses: n.grade <= 4,
                            ),
                          )),
                        ),
                      if (m.questions == 0)
                        IconButton(
                          tooltip: 'Supprimer',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _supprimer(context, ref, 'matiere', m.id, m.nom),
                        ),
                    ]),
                  ),
                OverflowBar(alignment: MainAxisAlignment.end, children: [
                  if (!p.publie && p.matieres.isEmpty)
                    TextButton(onPressed: () => _supprimer(context, ref, 'programme', p.id, p.nom), child: const Text('Supprimer')),
                  TextButton.icon(
                    key: ValueKey('bo_ajouter_matiere_${p.id}'),
                    onPressed: () => _matiere(context, ref, p, null),
                    icon: const Icon(Icons.add),
                    label: const Text('Matière'),
                  ),
                  if (!p.publie)
                    FilledButton(
                      key: ValueKey('bo_publier_programme_${p.id}'),
                      onPressed: p.matieres.isEmpty || !n.publie ? null : () => _publier(context, ref, p),
                      child: const Text('Publier'),
                    ),
                ]),
                if (!p.publie && !n.publie)
                  Text('Publiez d’abord le pays pour publier ce programme.', style: TextStyle(color: schema.onSurfaceVariant, fontSize: 12)),
              ]),
            ),
          ),
      ]),
    );
  }
}
