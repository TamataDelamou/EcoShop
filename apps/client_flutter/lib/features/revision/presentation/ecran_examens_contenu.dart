import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/widgets/choisir_date.dart';
import '../data/examens_contenu_repository.dart';
import '../domain/question.dart';

final examensContenuRepositoryProvider =
    Provider<ExamensContenuRepository>((ref) => ExamensContenuRepository(ref.watch(supabaseClientProvider)));

final examensReferentielProvider = FutureProvider.autoDispose<List<ExamenReferentiel>>(
  (ref) => ref.watch(examensContenuRepositoryProvider).examens(),
);

final _sessionsProvider = FutureProvider.autoDispose.family<List<SessionExamenContenu>, String>(
  (ref, id) => ref.watch(examensContenuRepositoryProvider).sessions(id),
);
final _epreuvesProvider = FutureProvider.autoDispose.family<List<EpreuveContenu>, String>(
  (ref, id) => ref.watch(examensContenuRepositoryProvider).epreuves(id),
);
final _annalesProvider = FutureProvider.autoDispose.family<List<AnnaleContenu>, String>(
  (ref, id) => ref.watch(examensContenuRepositoryProvider).annales(id),
);

void _erreur(BuildContext context, Object e) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(e is ErreurExamensContenu ? e.message : 'Action impossible pour le moment.'),
  ));
}

/// Administrateur de contenu : examens nationaux de chaque pays (cahier
/// 13, 30.5) — sessions, épreuves, annales.
class EcranExamensContenu extends ConsumerWidget {
  const EcranExamensContenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final examens = ref.watch(examensReferentielProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Examens et annales')),
      body: examens.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: Text(e is ErreurExamensContenu ? e.message : 'Indisponible pour le moment.'),
        ),
        data: (l) {
          final pays = <String, List<ExamenReferentiel>>{};
          for (final x in l) {
            (pays[x.paysCode] ??= []).add(x);
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            const Text('Chaque examen déclaré au référentiel ouvre un espace de préparation pour les élèves de '
                'sa classe d’examen, dans son pays seulement.'),
            for (final e in pays.entries) ...[
              const SizedBox(height: 12),
              Text(e.key, style: Theme.of(context).textTheme.titleMedium),
              for (final x in e.value)
                Card(
                  child: ListTile(
                    key: ValueKey('examen_ref_${x.id}'),
                    title: Text('${x.code} — ${x.nom}'),
                    subtitle: x.cycle == null ? null : Text(x.cycle!),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => EcranExamenContenu(examen: x),
                    )),
                  ),
                ),
            ],
          ]);
        },
      ),
    );
  }
}

class EcranExamenContenu extends ConsumerWidget {
  const EcranExamenContenu({super.key, required this.examen});

  final ExamenReferentiel examen;

  Future<void> _session(BuildContext context, WidgetRef ref) async {
    final d = await choisirDate(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 180)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 800)),
      helpText: 'Premier jour de la session',
    );
    if (d == null) return;
    try {
      await ref.read(examensContenuRepositoryProvider).ajouterSession(examen.id, d);
      ref.invalidate(_sessionsProvider(examen.id));
    } catch (e) {
      if (context.mounted) _erreur(context, e);
    }
  }

  Future<void> _epreuve(BuildContext context, WidgetRef ref, [EpreuveContenu? actuelle]) async {
    final e = await showDialog<EpreuveContenu>(context: context, builder: (_) => _DialogueEpreuve(actuelle: actuelle));
    if (e == null) return;
    try {
      await ref.read(examensContenuRepositoryProvider).enregistrerEpreuve(examen.id, e);
      ref.invalidate(_epreuvesProvider(examen.id));
    } catch (err) {
      if (context.mounted) _erreur(context, err);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final depot = ref.read(examensContenuRepositoryProvider);
    final sessions = ref.watch(_sessionsProvider(examen.id)).valueOrNull ?? const [];
    final epreuves = ref.watch(_epreuvesProvider(examen.id)).valueOrNull ?? const [];
    final annales = ref.watch(_annalesProvider(examen.id)).valueOrNull ?? const [];
    final titre = Theme.of(context).textTheme.titleMedium;
    return Scaffold(
      appBar: AppBar(title: Text('${examen.code} (${examen.paysCode})')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        Text(examen.nom),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: Text('Sessions', style: titre)),
          TextButton.icon(key: const Key('ajouter_session'), onPressed: () => _session(context, ref), icon: const Icon(Icons.add), label: const Text('Date')),
        ]),
        if (sessions.isEmpty) const Text('Aucune date : le compte à rebours utilise le mois habituel de la session.'),
        for (final s in sessions)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('Session ${s.annee} : le ${formaterDate(s.dateDebut)}'),
            trailing: IconButton(
              tooltip: 'Supprimer',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                try {
                  await depot.supprimerSession(s.id);
                  ref.invalidate(_sessionsProvider(examen.id));
                } catch (e) {
                  if (context.mounted) _erreur(context, e);
                }
              },
            ),
          ),
        const Divider(height: 32),
        Row(children: [
          Expanded(child: Text('Épreuves', style: titre)),
          TextButton.icon(key: const Key('ajouter_epreuve'), onPressed: () => _epreuve(context, ref), icon: const Icon(Icons.add), label: const Text('Épreuve')),
        ]),
        const Text('Le code matière relie l’épreuve aux questions du programme du niveau d’examen (ex. : MATH).'),
        for (final e in epreuves)
          ListTile(
            key: ValueKey('epreuve_contenu_${e.id}'),
            contentPadding: EdgeInsets.zero,
            title: Text(e.libelle),
            subtitle: Text('${e.matiereCode} · ${e.dureeMin} min · coefficient ${e.coefficient} · ${e.questionsBlanc} questions au blanc'),
            onTap: () => _epreuve(context, ref, e),
            trailing: IconButton(
              tooltip: 'Supprimer',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                try {
                  await depot.supprimerEpreuve(e.id!);
                  ref.invalidate(_epreuvesProvider(examen.id));
                } catch (err) {
                  if (context.mounted) _erreur(context, err);
                }
              },
            ),
          ),
        const Divider(height: 32),
        Row(children: [
          Expanded(child: Text('Annales', style: titre)),
          TextButton.icon(
            key: const Key('ajouter_annale'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => EcranAnnaleContenu(examen: examen, epreuves: epreuves),
            )),
            icon: const Icon(Icons.add),
            label: const Text('Annale'),
          ),
        ]),
        const Text('Publiées seulement si le droit de diffusion est établi (source officielle, licence ou domaine public).'),
        for (final a in annales)
          ListTile(
            key: ValueKey('annale_contenu_${a.id}'),
            contentPadding: EdgeInsets.zero,
            title: Text(a.titre),
            subtitle: Text('${a.annee} · ${a.statut.libelle} · droit : ${a.droit.libelle}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => EcranAnnaleContenu(examen: examen, epreuves: epreuves, annale: a),
            )),
          ),
      ]),
    );
  }
}

class _DialogueEpreuve extends StatefulWidget {
  const _DialogueEpreuve({this.actuelle});

  final EpreuveContenu? actuelle;

  @override
  State<_DialogueEpreuve> createState() => _DialogueEpreuveState();
}

class _DialogueEpreuveState extends State<_DialogueEpreuve> {
  late final _libelle = TextEditingController(text: widget.actuelle?.libelle ?? '');
  late final _code = TextEditingController(text: widget.actuelle?.matiereCode ?? '');
  late final _duree = TextEditingController(text: '${widget.actuelle?.dureeMin ?? 120}');
  late final _coef = TextEditingController(text: '${widget.actuelle?.coefficient ?? 1}');
  late final _questions = TextEditingController(text: '${widget.actuelle?.questionsBlanc ?? 20}');
  late final _ordre = TextEditingController(text: '${widget.actuelle?.ordre ?? 0}');

  @override
  Widget build(BuildContext context) {
    final chiffres = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return AlertDialog(
      title: Text(widget.actuelle == null ? 'Nouvelle épreuve' : 'Modifier l’épreuve'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(key: const Key('epreuve_libelle'), controller: _libelle, decoration: const InputDecoration(labelText: 'Épreuve (ex. : Mathématiques)')),
          TextField(key: const Key('epreuve_code'), controller: _code, decoration: const InputDecoration(labelText: 'Code matière du programme (ex. : MATH)')),
          TextField(key: const Key('epreuve_duree'), controller: _duree, inputFormatters: chiffres, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Durée (minutes)')),
          TextField(key: const Key('epreuve_coef'), controller: _coef, inputFormatters: chiffres, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Coefficient')),
          TextField(controller: _questions, inputFormatters: chiffres, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Questions de l’épreuve blanche (5 à 50)')),
          TextField(controller: _ordre, inputFormatters: chiffres, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Ordre')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          key: const Key('epreuve_valider'),
          onPressed: () {
            final duree = int.tryParse(_duree.text.trim());
            final coef = double.tryParse(_coef.text.trim().replaceAll(',', '.'));
            if (_libelle.text.trim().isEmpty || _code.text.trim().isEmpty || duree == null || coef == null) return;
            Navigator.of(context).pop(EpreuveContenu(
              id: widget.actuelle?.id,
              libelle: _libelle.text,
              matiereCode: _code.text,
              dureeMin: duree.clamp(10, 480),
              coefficient: coef,
              questionsBlanc: (int.tryParse(_questions.text.trim()) ?? 20).clamp(5, 50),
              ordre: int.tryParse(_ordre.text.trim()) ?? 0,
            ));
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

/// Une annale : description, droit de diffusion, sujet et corrigé, version
/// interactive, circuit de validation.
class EcranAnnaleContenu extends ConsumerStatefulWidget {
  const EcranAnnaleContenu({super.key, required this.examen, required this.epreuves, this.annale});

  final ExamenReferentiel examen;
  final List<EpreuveContenu> epreuves;
  final AnnaleContenu? annale;

  @override
  ConsumerState<EcranAnnaleContenu> createState() => _EcranAnnaleContenuState();
}

class _EcranAnnaleContenuState extends ConsumerState<EcranAnnaleContenu> {
  late final String _id = widget.annale?.id ?? const Uuid().v4();
  late final _titre = TextEditingController(text: widget.annale?.titre ?? '${widget.examen.code} ');
  late final _source = TextEditingController(text: widget.annale?.source ?? '');
  late final _annee = TextEditingController(text: '${widget.annale?.annee ?? DateTime.now().year - 1}');
  late String _session = widget.annale?.session ?? 'normale';
  late DroitDiffusion _droit = widget.annale?.droit ?? DroitDiffusion.aVerifier;
  late String? _epreuve = widget.annale?.epreuveId;
  late String? _sujet = widget.annale?.sujetChemin;
  late String? _corrige = widget.annale?.corrigeChemin;
  late StatutContenu _statut = widget.annale?.statut ?? StatutContenu.brouillon;
  List<String> _questions = const [];
  bool _occupe = false;
  bool _enregistree = false;

  ExamensContenuRepository get _depot => ref.read(examensContenuRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _enregistree = widget.annale != null;
    if (widget.annale != null) {
      _depot.questionsAnnale(_id).then((l) {
        if (mounted) setState(() => _questions = l);
      }).catchError((Object _) {});
    }
  }

  Future<void> _faire(Future<void> Function() action, {String? succes}) async {
    setState(() => _occupe = true);
    try {
      await action();
      ref.invalidate(_annalesProvider(widget.examen.id));
      if (succes != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(succes)));
    } catch (e) {
      if (mounted) _erreur(context, e);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<void> _enregistrer() => _faire(() async {
        await _depot.enregistrerAnnale(
          widget.examen.id,
          AnnaleContenu(
            id: _id,
            annee: int.tryParse(_annee.text.trim()) ?? DateTime.now().year,
            titre: _titre.text.trim(),
            source: _source.text.trim(),
            session: _session,
            droit: _droit,
            epreuveId: _epreuve,
            sujetChemin: _sujet,
            corrigeChemin: _corrige,
          ),
        );
        setState(() {
          _enregistree = true;
          _statut = StatutContenu.brouillon;
        });
      }, succes: 'Annale enregistrée (brouillon).');

  Future<void> _fichier({required bool sujet}) => _faire(() async {
        final chemin = await _depot.choisirEtEnvoyer('${widget.examen.paysCode}/${widget.examen.code}/$_id');
        if (chemin == null) return;
        setState(() => sujet ? _sujet = chemin : _corrige = chemin);
      }, succes: 'Fichier envoyé : enregistrez l’annale pour le garder.');

  Future<void> _statutSuivant(String action, StatutContenu apres) =>
      _faire(() async {
        await _depot.changerStatutAnnale(_id, action);
        setState(() => _statut = apres);
      }, succes: 'Annale : ${apres.libelle.toLowerCase()}.');

  Future<void> _choisirQuestions() async {
    final ep = widget.epreuves.where((e) => e.id == _epreuve).firstOrNull;
    if (ep == null) {
      _erreur(context, const ErreurExamensContenu('EPREUVE_REQUISE'));
      return;
    }
    final dispo = await _depot.questionsPubliees(widget.examen.paysCode, ep.matiereCode).catchError((Object _) => <({String id, String enonce, String matiere})>[]);
    if (!mounted) return;
    final choisies = {..._questions};
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text('Questions (${choisies.length})'),
          content: SizedBox(
            width: double.maxFinite,
            child: dispo.isEmpty
                ? const Text('Aucune question publiée pour ce code matière.')
                : ListView(shrinkWrap: true, children: [
                    for (final q in dispo)
                      CheckboxListTile(
                        dense: true,
                        value: choisies.contains(q.id),
                        title: Text(q.enonce, maxLines: 2, overflow: TextOverflow.ellipsis),
                        onChanged: (v) => set(() => v == true ? choisies.add(q.id) : choisies.remove(q.id)),
                      ),
                  ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Valider')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final ordre = [for (final id in _questions) if (choisies.contains(id)) id, for (final id in choisies) if (!_questions.contains(id)) id];
    await _faire(() async {
      await _depot.definirQuestionsAnnale(_id, ordre);
      setState(() => _questions = ordre);
    }, succes: 'Version interactive : ${ordre.length} questions.');
  }

  Future<void> _voir(String chemin) async {
    try {
      await launchUrl(await _depot.lien(chemin), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) _erreur(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final schema = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.annale == null ? 'Nouvelle annale' : 'Annale')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        Text('${widget.examen.code} (${widget.examen.paysCode}) · ${_statut.libelle}',
            key: const Key('annale_statut'), style: TextStyle(color: schema.primary, fontWeight: FontWeight.w700)),
        TextField(key: const Key('annale_titre'), controller: _titre, decoration: const InputDecoration(labelText: 'Titre')),
        Row(children: [
          Expanded(
            child: TextField(
              key: const Key('annale_annee'),
              controller: _annee,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Session (année)'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _session,
              decoration: const InputDecoration(labelText: 'Type'),
              items: const [
                DropdownMenuItem(value: 'normale', child: Text('Normale')),
                DropdownMenuItem(value: 'remplacement', child: Text('Remplacement')),
                DropdownMenuItem(value: 'blanc_officiel', child: Text('Blanc officiel')),
              ],
              onChanged: (v) => setState(() => _session = v ?? _session),
            ),
          ),
        ]),
        DropdownButtonFormField<String?>(
          initialValue: _epreuve,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Épreuve'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('—')),
            for (final e in widget.epreuves) DropdownMenuItem<String?>(value: e.id, child: Text(e.libelle)),
          ],
          onChanged: (v) => setState(() => _epreuve = v),
        ),
        TextField(
          key: const Key('annale_source'),
          controller: _source,
          decoration: const InputDecoration(
            labelText: 'Source (obligatoire)',
            hintText: 'Ex. : Ministère de l’Éducation nationale, publication officielle',
          ),
        ),
        DropdownButtonFormField<DroitDiffusion>(
          key: const Key('annale_droit'),
          initialValue: _droit,
          decoration: const InputDecoration(labelText: 'Droit de diffusion'),
          items: [for (final d in DroitDiffusion.values) DropdownMenuItem(value: d, child: Text(d.libelle))],
          onChanged: (v) => setState(() => _droit = v ?? _droit),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(
            onPressed: _occupe ? null : () => _fichier(sujet: true),
            icon: Icon(_sujet == null ? Icons.upload_file : Icons.check_circle),
            label: const Text('Sujet (PDF ou image)'),
          ),
          if (_sujet != null) TextButton(onPressed: () => _voir(_sujet!), child: const Text('Voir le sujet')),
          OutlinedButton.icon(
            onPressed: _occupe ? null : () => _fichier(sujet: false),
            icon: Icon(_corrige == null ? Icons.upload_file : Icons.check_circle),
            label: const Text('Corrigé'),
          ),
          if (_corrige != null) TextButton(onPressed: () => _voir(_corrige!), child: const Text('Voir le corrigé')),
        ]),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('annale_enregistrer'),
          onPressed: _occupe ? null : _enregistrer,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Enregistrer'),
        ),
        if (_enregistree) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('annale_questions'),
            onPressed: _occupe ? null : _choisirQuestions,
            icon: const Icon(Icons.quiz_outlined),
            label: Text('Version interactive (${_questions.length} questions)'),
          ),
          const SizedBox(height: 8),
          switch (_statut) {
            StatutContenu.brouillon => FilledButton.tonal(
                key: const Key('annale_soumettre'),
                onPressed: _occupe ? null : () => _statutSuivant('soumettre', StatutContenu.revision),
                child: const Text('Envoyer en validation')),
            StatutContenu.revision => FilledButton.tonal(
                key: const Key('annale_valider'),
                onPressed: _occupe ? null : () => _statutSuivant('valider', StatutContenu.validee),
                child: const Text('Valider')),
            StatutContenu.validee => FilledButton.tonal(
                key: const Key('annale_publier'),
                onPressed: _occupe ? null : () => _statutSuivant('publier', StatutContenu.publiee),
                child: const Text('Publier pour les élèves')),
            StatutContenu.publiee => OutlinedButton(
                key: const Key('annale_retirer'),
                onPressed: _occupe ? null : () => _statutSuivant('retirer', StatutContenu.brouillon),
                child: const Text('Retirer de la diffusion')),
          },
        ],
      ]),
    );
  }
}
