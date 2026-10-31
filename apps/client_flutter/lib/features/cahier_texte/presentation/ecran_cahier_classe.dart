import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/widgets/choisir_date.dart';
import '../../auth/application/auth_providers.dart';
import '../../planification/application/planification_providers.dart';
import '../../revision/application/banque_providers.dart';
import '../../revision/domain/question.dart' show ChapitreMatiere;
import '../../scolarite/application/scolarite_providers.dart';
import '../../scolarite/domain/classe.dart';
import '../data/cahier_repository.dart';
import '../domain/cahier.dart';
import 'ecran_suivi_travail.dart';
import 'elements_cahier.dart';

/// Matière enseignée dans la classe (pour les listes de choix).
typedef MatiereClasse = ({String id, String nom});

/// Matières de la classe : celles de l'enseignant connecté, ou toutes pour
/// la direction.
final matieresCahierProvider = FutureProvider.autoDispose.family<List<MatiereClasse>, ({String classeId, bool toutes})>(
  (ref, p) async {
    final moi = ref.watch(profilProvider).valueOrNull?.id;
    final affectations = await ref.watch(affectationsDeClasseProvider(p.classeId).future);
    final vues = <String>{};
    return [
      for (final a in affectations)
        if (a.programmeMatiereId != null && (p.toutes || a.enseignantProfileId == moi) && vues.add(a.programmeMatiereId!))
          (id: a.programmeMatiereId!, nom: a.nomMatiere ?? 'Matière'),
    ]..sort((a, b) => a.nom.compareTo(b.nom));
  },
);

/// Cahier de texte d'une classe (REG-40) : séances et travail à faire.
/// Enseignant de la classe ou direction.
class EcranCahierClasse extends ConsumerWidget {
  const EcranCahierClasse({super.key, required this.classe, this.direction = false});

  final Classe classe;
  final bool direction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Builder(builder: (context) {
        return Scaffold(
          appBar: AppBar(
            title: Text('Cahier de texte — ${classe.nom}'),
            bottom: const TabBar(tabs: [Tab(text: 'Séances'), Tab(text: 'Travail à faire')]),
          ),
          floatingActionButton: _BoutonAjouter(classe: classe, direction: direction),
          body: TabBarView(children: [
            _OngletSeances(classe: classe, direction: direction),
            _OngletTravaux(classe: classe, direction: direction),
          ]),
        );
      }),
    );
  }
}

class _BoutonAjouter extends StatefulWidget {
  const _BoutonAjouter({required this.classe, required this.direction});

  final Classe classe;
  final bool direction;

  @override
  State<_BoutonAjouter> createState() => _BoutonAjouterState();
}

class _BoutonAjouterState extends State<_BoutonAjouter> {
  TabController? _onglets;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = DefaultTabController.of(context);
    if (c != _onglets) {
      _onglets?.removeListener(_maj);
      _onglets = c..addListener(_maj);
    }
  }

  void _maj() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _onglets?.removeListener(_maj);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seances = (_onglets?.index ?? 0) == 0;
    return FloatingActionButton.extended(
      key: Key(seances ? 'bouton_nouvelle_seance' : 'bouton_donner_travail'),
      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => seances
            ? EcranFormulaireSeance(classe: widget.classe, direction: widget.direction)
            : EcranFormulaireTravail(classe: widget.classe, direction: widget.direction),
      )),
      icon: Icon(seances ? Icons.edit_calendar_outlined : Icons.assignment_add),
      label: Text(seances ? 'Nouvelle séance' : 'Donner du travail'),
    );
  }
}

class _OngletSeances extends ConsumerWidget {
  const _OngletSeances({required this.classe, required this.direction});

  final Classe classe;
  final bool direction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seances = ref.watch(seancesClasseProvider(classe.id));
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(seancesClasseProvider(classe.id)),
      child: seances.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(e is ErreurCahier ? e.message : 'Cahier indisponible pour le moment.', textAlign: TextAlign.center),
          ),
        ]),
        data: (liste) {
          if (liste.isEmpty) {
            return ListView(children: const [
              Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Aucune séance pour le moment. Après chaque cours, notez ce qui a été fait : '
                  'élèves et parents le retrouvent dans leur cahier de texte.',
                  key: Key('seances_vides'),
                  textAlign: TextAlign.center,
                ),
              ),
            ]);
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: liste.length,
            itemBuilder: (context, i) {
              final s = liste[i];
              final nouvelleDate = i == 0 || jour(liste[i - 1].date) != jour(s.date);
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (nouvelleDate)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                    child: Text(dateLisible(s.date), style: Theme.of(context).textTheme.titleSmall),
                  ),
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    key: Key('seance_${s.id}'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => EcranFormulaireSeance(classe: classe, direction: direction, existante: s),
                    )),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                            child: Text([s.matiere, s.chapitre].whereType<String>().join(' · '),
                                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary)),
                          ),
                          if (s.enAttente) const EtiquetteEnAttente(),
                        ]),
                        const SizedBox(height: 4),
                        Text(s.titre, style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (s.contenu != null) ...[
                          const SizedBox(height: 4),
                          Text(s.contenu!, maxLines: 4, overflow: TextOverflow.ellipsis),
                        ],
                        if (s.piecesJointes.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          PiecesJointes(pieces: s.piecesJointes),
                        ],
                      ]),
                    ),
                  ),
                ),
              ]);
            },
          );
        },
      ),
    );
  }
}

class _OngletTravaux extends ConsumerWidget {
  const _OngletTravaux({required this.classe, required this.direction});

  final Classe classe;
  final bool direction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final travaux = ref.watch(travauxClasseProvider(classe.id));
    final aujourdhui = jour(DateTime.now());
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(travauxClasseProvider(classe.id)),
      child: travaux.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(e is ErreurCahier ? e.message : 'Travail indisponible pour le moment.', textAlign: TextAlign.center),
          ),
        ]),
        data: (liste) {
          if (liste.isEmpty) {
            return ListView(children: const [
              Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Aucun travail donné. Les devoirs courts et fréquents (30 min au plus) sont les plus efficaces.',
                  key: Key('travaux_vides'),
                  textAlign: TextAlign.center,
                ),
              ),
            ]);
          }
          final aVenir = [for (final t in liste) if (!jour(t.pourLe).isBefore(aujourdhui)) t]
            ..sort((a, b) => a.pourLe.compareTo(b.pourLe));
          final passes = [for (final t in liste) if (jour(t.pourLe).isBefore(aujourdhui)) t];
          final charge = chargeParJour([for (final t in aVenir) (pourLe: t.pourLe, minutes: t.tempsEstimeMin)]);
          Widget carte(Travail t) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  key: Key('travail_${t.id}'),
                  leading: Icon(iconeTravail(t.type)),
                  title: Text(t.titre, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text([
                    if (t.matiere != null) t.matiere!,
                    'pour ${dateLisible(t.pourLe).toLowerCase()}',
                    minutesLisibles(t.tempsEstimeMin),
                    if (t.type == TypeTravail.devoirNumerique) '${t.questions.length} questions',
                  ].join(' · ')),
                  trailing: t.enAttente ? const EtiquetteEnAttente() : const Icon(Icons.chevron_right),
                  onTap: t.enAttente
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => EcranSuiviTravail(classe: classe, travail: t, direction: direction),
                          )),
                ),
              );
          return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
            if (aVenir.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                child: Text('À venir', style: Theme.of(context).textTheme.titleSmall),
              ),
              for (final (i, t) in aVenir.indexed) ...[
                if (i == 0 || jour(aVenir[i - 1].pourLe) != jour(t.pourLe))
                  _EnteteJour(date: t.pourLe, minutes: charge[jour(t.pourLe)] ?? 0),
                carte(t),
              ],
            ],
            if (passes.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                child: Text('Passés', style: Theme.of(context).textTheme.titleSmall),
              ),
              for (final t in passes) carte(t),
            ],
          ]);
        },
      ),
    );
  }
}

class _EnteteJour extends StatelessWidget {
  const _EnteteJour({required this.date, required this.minutes});

  final DateTime date;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final lourd = minutes > seuilChargeJour;
    final schema = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
      child: Row(children: [
        Expanded(child: Text('Pour ${dateLisible(date).toLowerCase()}', style: const TextStyle(fontWeight: FontWeight.w600))),
        Icon(Icons.timer_outlined, size: 16, color: lourd ? schema.error : schema.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(minutesLisibles(minutes), style: TextStyle(color: lourd ? schema.error : schema.onSurfaceVariant)),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Formulaire d'une séance
// ---------------------------------------------------------------------------

class EcranFormulaireSeance extends ConsumerStatefulWidget {
  const EcranFormulaireSeance({super.key, required this.classe, this.direction = false, this.existante});

  final Classe classe;
  final bool direction;
  final Seance? existante;

  @override
  ConsumerState<EcranFormulaireSeance> createState() => _EcranFormulaireSeanceState();
}

class _EcranFormulaireSeanceState extends ConsumerState<EcranFormulaireSeance> {
  late final _titre = TextEditingController(text: widget.existante?.titre ?? '');
  late final _contenu = TextEditingController(text: widget.existante?.contenu ?? '');
  late DateTime _date = widget.existante?.date ?? DateTime.now();
  late String? _matiereId = widget.existante?.matiereId;
  late String? _chapitreId = widget.existante?.chapitreId;
  late List<PieceJointe> _pieces = [...?widget.existante?.piecesJointes];
  bool _travailEnsuite = false;
  bool _enCours = false;
  bool _depot = false;
  String? _erreur;

  @override
  void dispose() {
    _titre.dispose();
    _contenu.dispose();
    super.dispose();
  }

  Future<void> _ajouterPiece() async {
    if (_pieces.length >= 5) return;
    setState(() => _depot = true);
    try {
      final p = await ref
          .read(cahierRepositoryProvider)
          .ajouterPieceJointe(etablissementId: widget.classe.etablissementId, classeId: widget.classe.id);
      if (p != null && mounted) setState(() => _pieces = [..._pieces, p]);
    } on ErreurCahier catch (e) {
      if (mounted) setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _depot = false);
    }
  }

  Future<void> _enregistrer() async {
    if (_titre.text.trim().isEmpty || _matiereId == null) {
      setState(() => _erreur = 'Choisissez la matière et donnez un titre (la notion vue en cours).');
      return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    final seance = Seance(
      id: widget.existante?.id ?? const Uuid().v4(),
      etablissementId: widget.classe.etablissementId,
      anneeId: widget.classe.anneeScolaireId,
      classeId: widget.classe.id,
      date: _date,
      titre: _titre.text,
      contenu: _contenu.text,
      matiereId: _matiereId,
      chapitreId: _chapitreId,
      piecesJointes: _pieces,
    );
    try {
      final envoye = await ref.read(cahierRepositoryProvider).enregistrerSeance(seance);
      ref.invalidate(seancesClasseProvider(widget.classe.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(envoye ? 'Séance enregistrée.' : 'Sans réseau : la séance partira au retour de la connexion.'),
      ));
      final navigateur = Navigator.of(context);
      if (_travailEnsuite) {
        navigateur.pushReplacement(MaterialPageRoute<void>(
          builder: (_) => EcranFormulaireTravail(classe: widget.classe, direction: widget.direction, seance: seance),
        ));
      } else {
        navigateur.pop();
      }
    } on ErreurCahier catch (e) {
      setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _retirer() async {
    try {
      await ref.read(cahierRepositoryProvider).retirerSeance(widget.existante!.id);
      ref.invalidate(seancesClasseProvider(widget.classe.id));
      if (mounted) Navigator.of(context).pop();
    } on ErreurCahier catch (e) {
      setState(() => _erreur = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final matieres = ref.watch(matieresCahierProvider((classeId: widget.classe.id, toutes: widget.direction))).valueOrNull ??
        const <MatiereClasse>[];
    if (_matiereId == null && matieres.length == 1) _matiereId = matieres.first.id;
    final chapitres = _matiereId == null
        ? const <ChapitreMatiere>[]
        : ref.watch(structureMatiereProvider(_matiereId!)).valueOrNull?.chapitres ?? const <ChapitreMatiere>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existante == null ? 'Nouvelle séance' : 'Séance'),
        actions: [
          if (widget.existante != null && !widget.existante!.enAttente)
            IconButton(tooltip: 'Retirer', onPressed: _retirer, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_outlined),
          title: Text(dateLisible(_date)),
          subtitle: const Text('Date de la séance'),
          onTap: () async {
            final d = await choisirDate(
              context: context,
              initialDate: _date,
              firstDate: DateTime.now().subtract(const Duration(days: 120)),
              lastDate: DateTime.now().add(const Duration(days: 30)),
              helpText: 'Date de la séance',
            );
            if (d != null) setState(() => _date = d);
          },
        ),
        DropdownButtonFormField<String?>(
          key: const Key('seance_matiere'),
          initialValue: matieres.any((m) => m.id == _matiereId) ? _matiereId : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Matière', border: OutlineInputBorder()),
          items: [for (final m in matieres) DropdownMenuItem<String?>(value: m.id, child: Text(m.nom))],
          onChanged: (v) => setState(() {
            _matiereId = v;
            _chapitreId = null;
          }),
        ),
        if (matieres.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Aucune matière : la direction attribue les cours dans « Cours et enseignants ».',
                style: TextStyle(fontSize: 12)),
          ),
        const SizedBox(height: 12),
        if (chapitres.isNotEmpty) ...[
          DropdownButtonFormField<String?>(
            key: ValueKey('seance_chapitre_$_matiereId'),
            initialValue: chapitres.any((c) => c.id == _chapitreId) ? _chapitreId : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Chapitre du programme (facultatif)', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('—')),
              for (final c in chapitres) DropdownMenuItem<String?>(value: c.id, child: Text(c.titre)),
            ],
            onChanged: (v) => setState(() => _chapitreId = v),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          key: const Key('seance_titre'),
          controller: _titre,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Notion vue en cours', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('seance_contenu'),
          controller: _contenu,
          minLines: 3,
          maxLines: 8,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Ce qui a été fait',
            hintText: 'Cours, exemples, exercices corrigés…',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        PiecesJointes(pieces: _pieces, onRetirer: (p) => setState(() => _pieces = [..._pieces]..remove(p))),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _depot || _pieces.length >= 5 ? null : _ajouterPiece,
            icon: _depot
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.attach_file),
            label: const Text('Joindre un fichier (réseau requis)'),
          ),
        ),
        if (widget.existante == null)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Donner du travail pour cette séance'),
            value: _travailEnsuite,
            onChanged: (v) => setState(() => _travailEnsuite = v),
          ),
        if (_erreur != null) Text(_erreur!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('enregistrer_seance'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _enCours ? null : _enregistrer,
          child: Text(_travailEnsuite ? 'Enregistrer et donner du travail' : 'Enregistrer'),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Formulaire du travail à faire (et du devoir numérique)
// ---------------------------------------------------------------------------

class EcranFormulaireTravail extends ConsumerStatefulWidget {
  const EcranFormulaireTravail({super.key, required this.classe, this.direction = false, this.seance});

  final Classe classe;
  final bool direction;

  /// Séance d'où vient le travail (matière et chapitre repris).
  final Seance? seance;

  @override
  ConsumerState<EcranFormulaireTravail> createState() => _EcranFormulaireTravailState();
}

class _EcranFormulaireTravailState extends ConsumerState<EcranFormulaireTravail> {
  final _titre = TextEditingController();
  final _consigne = TextEditingController();
  TypeTravail _type = TypeTravail.exercices;
  late String? _matiereId = widget.seance?.matiereId;
  late String? _chapitreId = widget.seance?.chapitreId;
  DateTime? _pourLe;
  bool _pourLeChoisi = false;
  int _temps = 20;
  List<PieceJointe> _pieces = const [];
  List<String> _questions = const [];
  int? _duree;
  bool _correctionApres = false;
  bool _enCours = false;
  bool _depot = false;
  String? _erreur;

  @override
  void dispose() {
    _titre.dispose();
    _consigne.dispose();
    super.dispose();
  }

  Future<void> _ajouterPiece() async {
    setState(() => _depot = true);
    try {
      final p = await ref
          .read(cahierRepositoryProvider)
          .ajouterPieceJointe(etablissementId: widget.classe.etablissementId, classeId: widget.classe.id);
      if (p != null && mounted) setState(() => _pieces = [..._pieces, p]);
    } on ErreurCahier catch (e) {
      if (mounted) setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _depot = false);
    }
  }

  Future<void> _choisirQuestions() async {
    final matiere = _matiereId;
    if (matiere == null) {
      setState(() => _erreur = 'Choisissez d’abord la matière.');
      return;
    }
    final choix = await Navigator.of(context).push<List<String>>(MaterialPageRoute(
      builder: (_) => _ChoixQuestions(matiereId: matiere, chapitreId: _chapitreId, deja: _questions),
    ));
    if (choix != null) {
      setState(() {
        _questions = choix;
        // Temps estimé : environ une minute et demie par question.
        _temps = (choix.length * 1.5).ceil().clamp(5, 240);
      });
    }
  }

  Future<void> _enregistrer(DateTime pourLe) async {
    final devoir = _type == TypeTravail.devoirNumerique;
    if (_titre.text.trim().isEmpty || _matiereId == null) {
      setState(() => _erreur = 'Choisissez la matière et donnez un titre.');
      return;
    }
    if (devoir && _questions.isEmpty) {
      setState(() => _erreur = 'Choisissez les questions du devoir.');
      return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    final travail = Travail(
      id: const Uuid().v4(),
      etablissementId: widget.classe.etablissementId,
      anneeId: widget.classe.anneeScolaireId,
      classeId: widget.classe.id,
      type: _type,
      titre: _titre.text,
      consigne: _consigne.text,
      pourLe: pourLe,
      donneLe: DateTime.now(),
      matiereId: _matiereId,
      chapitreId: _chapitreId,
      seanceId: widget.seance?.id,
      tempsEstimeMin: _temps,
      piecesJointes: _pieces,
      questions: _questions,
      dureeMin: devoir ? _duree : null,
      correctionApresEcheance: devoir && _correctionApres,
    );
    try {
      final envoye = await ref.read(cahierRepositoryProvider).enregistrerTravail(travail);
      ref.invalidate(travauxClasseProvider(widget.classe.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(envoye
            ? 'Travail donné : élèves et parents sont prévenus.'
            : 'Sans réseau : le travail partira au retour de la connexion.'),
      ));
      Navigator.of(context).pop();
    } on ErreurCahier catch (e) {
      setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final matieres = ref.watch(matieresCahierProvider((classeId: widget.classe.id, toutes: widget.direction))).valueOrNull ??
        const <MatiereClasse>[];
    if (_matiereId == null && matieres.length == 1) _matiereId = matieres.first.id;
    final chapitres = _matiereId == null
        ? const <ChapitreMatiere>[]
        : ref.watch(structureMatiereProvider(_matiereId!)).valueOrNull?.chapitres ?? const <ChapitreMatiere>[];

    // Échéance par défaut : le prochain cours de la matière (Pronote).
    final emplois = ref.watch(emploisDeClasseProvider(widget.classe.id)).valueOrNull ?? const [];
    final joursCours = [for (final e in emplois) if (e.programmeMatiereId == _matiereId) e.jourSemaine];
    final pourLe = _pourLeChoisi && _pourLe != null ? _pourLe! : prochainCours(joursCours, DateTime.now());

    // Charge déjà prévue ce jour-là pour la classe.
    final travaux = ref.watch(travauxClasseProvider(widget.classe.id)).valueOrNull ?? const <Travail>[];
    final dejaCeJour = travaux.where((t) => jour(t.pourLe) == jour(pourLe)).fold<int>(0, (s, t) => s + t.tempsEstimeMin);
    final total = dejaCeJour + _temps;
    final schema = Theme.of(context).colorScheme;
    final devoir = _type == TypeTravail.devoirNumerique;

    return Scaffold(
      appBar: AppBar(title: const Text('Donner du travail')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final t in TypeTravail.values)
            ChoiceChip(
              key: Key('type_${t.code}'),
              avatar: Icon(iconeTravail(t), size: 18),
              label: Text(t.libelle),
              selected: _type == t,
              onSelected: (_) => setState(() => _type = t),
            ),
        ]),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          key: const Key('travail_matiere'),
          initialValue: matieres.any((m) => m.id == _matiereId) ? _matiereId : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Matière', border: OutlineInputBorder()),
          items: [for (final m in matieres) DropdownMenuItem<String?>(value: m.id, child: Text(m.nom))],
          onChanged: (v) => setState(() {
            _matiereId = v;
            _chapitreId = null;
            _questions = const [];
          }),
        ),
        const SizedBox(height: 12),
        if (chapitres.isNotEmpty) ...[
          DropdownButtonFormField<String?>(
            key: ValueKey('travail_chapitre_$_matiereId'),
            initialValue: chapitres.any((c) => c.id == _chapitreId) ? _chapitreId : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Chapitre (facultatif)', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('—')),
              for (final c in chapitres) DropdownMenuItem<String?>(value: c.id, child: Text(c.titre)),
            ],
            onChanged: (v) => setState(() => _chapitreId = v),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          key: const Key('travail_titre'),
          controller: _titre,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Titre',
            hintText: devoir ? 'Devoir sur les fractions' : 'Exercices 1 à 4 page 32',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _consigne,
          minLines: 2,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Consigne (facultatif)',
            hintText: 'Ce que l’élève doit faire, et pourquoi',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        ListTile(
          key: const Key('travail_pour_le'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_available_outlined),
          title: Text('Pour ${dateLisible(pourLe).toLowerCase()}'),
          subtitle: Text(_pourLeChoisi ? 'Échéance choisie' : 'Prochain cours de la matière — touchez pour changer'),
          onTap: () async {
            final d = await choisirDate(
              context: context,
              initialDate: pourLe,
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 120)),
              helpText: 'Pour le',
            );
            if (d != null) {
              setState(() {
                _pourLe = d;
                _pourLeChoisi = true;
              });
            }
          },
        ),
        const Text('Temps estimé pour l’élève', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, children: [
          for (final m in const [10, 15, 20, 30, 45, 60, 90])
            ChoiceChip(label: Text(minutesLisibles(m)), selected: _temps == m, onSelected: (_) => setState(() => _temps = m)),
        ]),
        const SizedBox(height: 8),
        Container(
          key: const Key('charge_du_jour'),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: total > seuilChargeJour ? schema.errorContainer : schema.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            total > seuilChargeJour
                ? 'Charge de la classe ce jour-là : ${minutesLisibles(total)}. Au-delà d’1 h 30, le travail profite moins : '
                    'pensez à choisir un autre jour ou à alléger.'
                : 'Charge de la classe ce jour-là : ${minutesLisibles(total)}'
                    '${dejaCeJour > 0 ? ' (dont ${minutesLisibles(dejaCeJour)} déjà donnés)' : ''}.',
            style: TextStyle(color: total > seuilChargeJour ? schema.onErrorContainer : null),
          ),
        ),
        if (devoir) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Devoir numérique', style: Theme.of(context).textTheme.titleSmall),
                const Text('Questions de la banque, corrigées automatiquement. L’élève peut le faire sans réseau.'),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('choisir_questions'),
                  onPressed: _choisirQuestions,
                  icon: const Icon(Icons.playlist_add_check),
                  label: Text(_questions.isEmpty ? 'Choisir les questions' : '${_questions.length} questions choisies'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int?>(
                  initialValue: _duree,
                  decoration: const InputDecoration(labelText: 'Durée', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem<int?>(value: null, child: Text('Sans limite (à son rythme)')),
                    DropdownMenuItem<int?>(value: 10, child: Text('10 min')),
                    DropdownMenuItem<int?>(value: 15, child: Text('15 min')),
                    DropdownMenuItem<int?>(value: 20, child: Text('20 min')),
                    DropdownMenuItem<int?>(value: 30, child: Text('30 min')),
                    DropdownMenuItem<int?>(value: 45, child: Text('45 min')),
                  ],
                  onChanged: (v) => setState(() => _duree = v),
                ),
                if (_duree != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('Chronométré : l’élève a besoin du réseau pour le commencer.', style: TextStyle(fontSize: 12)),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Correction après la date limite'),
                  subtitle: const Text('Évite que les réponses circulent avant l’échéance'),
                  value: _correctionApres,
                  onChanged: (v) => setState(() => _correctionApres = v),
                ),
              ]),
            ),
          ),
        ],
        const SizedBox(height: 12),
        PiecesJointes(pieces: _pieces, onRetirer: (p) => setState(() => _pieces = [..._pieces]..remove(p))),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _depot || _pieces.length >= 5 ? null : _ajouterPiece,
            icon: _depot
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.attach_file),
            label: const Text('Joindre un fichier (réseau requis)'),
          ),
        ),
        if (_erreur != null) Text(_erreur!, style: TextStyle(color: schema.error)),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('enregistrer_travail'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _enCours ? null : () => _enregistrer(pourLe),
          child: const Text('Donner ce travail'),
        ),
      ]),
    );
  }
}

/// Choix des questions d'un devoir : tirage automatique ou à la main.
class _ChoixQuestions extends ConsumerStatefulWidget {
  const _ChoixQuestions({required this.matiereId, this.chapitreId, this.deja = const []});

  final String matiereId;
  final String? chapitreId;
  final List<String> deja;

  @override
  ConsumerState<_ChoixQuestions> createState() => _ChoixQuestionsState();
}

class _ChoixQuestionsState extends ConsumerState<_ChoixQuestions> {
  late final Set<String> _choisies = {...widget.deja};
  late bool _toutLeChapitre = widget.chapitreId == null;
  List<QuestionProposeeDevoir>? _questions;
  ErreurCahier? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _questions = null;
      _erreur = null;
    });
    try {
      final q = await ref
          .read(cahierRepositoryProvider)
          .questionsPourDevoir(widget.matiereId, chapitreId: _toutLeChapitre ? null : widget.chapitreId);
      if (mounted) setState(() => _questions = q);
    } on ErreurCahier catch (e) {
      if (mounted) setState(() => _erreur = e);
    }
  }

  /// Tirage équilibré : des facile aux difficiles, [n] questions.
  void _tirer(int n) {
    final q = [...?_questions]..shuffle();
    final ordre = {'facile': 0, 'moyen': 1, 'difficile': 2};
    final choix = q.take(n).toList()..sort((a, b) => (ordre[a.difficulte] ?? 1).compareTo(ordre[b.difficulte] ?? 1));
    setState(() {
      _choisies
        ..clear()
        ..addAll(choix.map((x) => x.id));
    });
  }

  @override
  Widget build(BuildContext context) {
    final questions = _questions;
    return Scaffold(
      appBar: AppBar(
        title: Text('${_choisies.length} question${_choisies.length > 1 ? 's' : ''}'),
        actions: [
          TextButton(
            key: const Key('valider_questions'),
            onPressed: _choisies.isEmpty
                ? null
                : () => Navigator.of(context).pop([
                      for (final q in questions ?? const <QuestionProposeeDevoir>[]) if (_choisies.contains(q.id)) q.id,
                    ]),
            child: const Text('Valider'),
          ),
        ],
      ),
      body: _erreur != null
          ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(_erreur!.message, textAlign: TextAlign.center)))
          : questions == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 32), children: [
                  if (widget.chapitreId != null)
                    SwitchListTile(
                      title: const Text('Toute la matière'),
                      subtitle: const Text('Sinon, seulement le chapitre choisi'),
                      value: _toutLeChapitre,
                      onChanged: (v) {
                        setState(() => _toutLeChapitre = v);
                        _charger();
                      },
                    ),
                  if (questions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Aucune question publiée ici pour le moment. La banque de questions est alimentée '
                          'par les contenus validés (Administrateur de contenu).', textAlign: TextAlign.center),
                    )
                  else ...[
                    Wrap(spacing: 6, children: [
                      const Text('Tirage automatique : '),
                      for (final n in const [5, 10, 15])
                        if (n <= questions.length)
                          ActionChip(key: Key('tirer_$n'), label: Text('$n'), onPressed: () => _tirer(n)),
                    ]),
                    const SizedBox(height: 8),
                    for (final q in questions)
                      CheckboxListTile(
                        key: Key('question_${q.id}'),
                        value: _choisies.contains(q.id),
                        onChanged: (v) => setState(() => v == true ? _choisies.add(q.id) : _choisies.remove(q.id)),
                        title: Text(q.enonce, maxLines: 3, overflow: TextOverflow.ellipsis),
                        subtitle: Text([q.chapitre, q.competence, q.difficulte].whereType<String>().join(' · ')),
                      ),
                  ],
                ]),
    );
  }
}
