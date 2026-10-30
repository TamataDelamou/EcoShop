import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../application/banque_providers.dart';
import '../domain/question.dart';

/// Créer ou modifier une question de la banque (cahier 10, 30.5) : toutes
/// les métadonnées obligatoires, un éditeur par type, puis le circuit
/// brouillon → à valider → validée → publiée.
class EcranEditeurQuestion extends ConsumerStatefulWidget {
  const EcranEditeurQuestion({
    super.key,
    required this.matiereId,
    required this.titreMatiere,
    this.question,
    this.petitesClasses = false,
  });

  final String matiereId;
  final String titreMatiere;
  final Question? question;

  /// CP1 à CE2 : types adaptés seulement, trois choix au plus.
  final bool petitesClasses;

  @override
  ConsumerState<EcranEditeurQuestion> createState() => _EcranEditeurQuestionState();
}

class _Ligne {
  _Ligne(this.id, String texte, {this.bon = false, String autre = ''})
      : texte = TextEditingController(text: texte),
        autre = TextEditingController(text: autre);

  final String id;
  final TextEditingController texte;

  /// Terme de droite (association).
  final TextEditingController autre;
  bool bon;

  void dispose() {
    texte.dispose();
    autre.dispose();
  }
}

class _EcranEditeurQuestionState extends ConsumerState<EcranEditeurQuestion> {
  late final String _id = widget.question?.id ?? const Uuid().v4();
  late TypeQuestion _type;
  late Difficulte _difficulte;
  String? _competenceId;
  String? _chapitreId;
  String? _leconId;
  final _enonce = TextEditingController();
  final _explication = TextEditingController();
  final _source = TextEditingController();
  final _tags = TextEditingController();
  final _acceptees = TextEditingController();
  final _valeur = TextEditingController();
  final _tolerance = TextEditingController();
  final _unite = TextEditingController();
  int _temps = 60;
  bool _vrai = true;
  final List<_Ligne> _lignes = [];
  final Map<String, TextEditingController> _trous = {};
  String? _mediaChemin;
  String? _mediaType;
  bool _occupe = false;
  String? _erreur;
  Question? _question;
  var _compteurIds = 0;

  @override
  void initState() {
    super.initState();
    _question = widget.question;
    final c = widget.question?.travail;
    _type = c?.type ?? TypeQuestion.qcmSimple;
    _difficulte = c?.difficulte ?? Difficulte.moyen;
    _competenceId = c?.competenceId;
    _chapitreId = c?.chapitreId;
    _leconId = c?.leconId;
    _enonce.text = c?.enonce ?? '';
    _explication.text = c?.explication ?? '';
    _source.text = c?.source ?? '';
    _tags.text = (c?.tags ?? const []).join(', ');
    _temps = c?.tempsRecommandeS ?? 60;
    _mediaChemin = c?.mediaChemin;
    _mediaType = c?.mediaType;
    if (c != null) _charger(c);
    if (_lignes.isEmpty) _lignesParDefaut();
    _enonce.addListener(_synchroniserTrous);
    _synchroniserTrous();
  }

  void _charger(ContenuQuestion c) {
    switch (c.type) {
      case TypeQuestion.qcmSimple:
      case TypeQuestion.qcmMultiple:
        final bonnes = {for (final b in (c.reponse['bonnes'] as List?) ?? const []) '$b'};
        _lignes.addAll([for (final x in c.choix) _Ligne(x.id, x.texte, bon: bonnes.contains(x.id))]);
      case TypeQuestion.vraiFaux:
        _vrai = c.reponse['valeur'] != false;
      case TypeQuestion.reponseCourte:
        _acceptees.text = ((c.reponse['acceptees'] as List?) ?? const []).join('\n');
      case TypeQuestion.texteATrous:
        final t = ((c.reponse['trous'] as Map?) ?? const {}).cast<String, dynamic>();
        for (final e in t.entries) {
          _trous[e.key] = TextEditingController(text: (e.value as List).join(' / '));
        }
      case TypeQuestion.association:
        final paires = ((c.reponse['paires'] as Map?) ?? const {}).cast<String, dynamic>();
        final droite = {for (final d in c.droite) d.id: d.texte};
        _lignes.addAll([for (final g in c.gauche) _Ligne(g.id, g.texte, autre: droite[paires[g.id]] ?? '')]);
      case TypeQuestion.classement:
        final t = {for (final e in c.elements) e.id: e.texte};
        _lignes.addAll([
          for (final o in (c.reponse['ordre'] as List?) ?? const []) _Ligne('$o', t['$o'] ?? ''),
        ]);
      case TypeQuestion.calcul:
        _valeur.text = '${c.reponse['valeur'] ?? ''}';
        _tolerance.text = c.reponse['tolerance'] == null ? '' : '${c.reponse['tolerance']}';
        _unite.text = '${c.reponse['unite'] ?? ''}';
    }
  }

  String _nouvelId(String prefixe) {
    final pris = {for (final l in _lignes) l.id};
    String id;
    do {
      id = '$prefixe${++_compteurIds}';
    } while (pris.contains(id));
    return id;
  }

  void _lignesParDefaut() {
    final prefixe = switch (_type) {
      TypeQuestion.association => 'g',
      TypeQuestion.classement => 'e',
      _ => 'c',
    };
    final n = _type == TypeQuestion.qcmSimple || _type == TypeQuestion.qcmMultiple ? 3 : 2;
    if (_type == TypeQuestion.qcmSimple ||
        _type == TypeQuestion.qcmMultiple ||
        _type == TypeQuestion.association ||
        _type == TypeQuestion.classement) {
      for (var i = 0; i < n; i++) {
        _lignes.add(_Ligne(_nouvelId(prefixe), '', bon: i == 0 && _type != TypeQuestion.association));
      }
    }
  }

  void _changerType(TypeQuestion t) {
    if (t == _type) return;
    setState(() {
      final garder = (_type == TypeQuestion.qcmSimple || _type == TypeQuestion.qcmMultiple) &&
          (t == TypeQuestion.qcmSimple || t == TypeQuestion.qcmMultiple);
      _type = t;
      if (!garder) {
        for (final l in _lignes) {
          l.dispose();
        }
        _lignes.clear();
        _lignesParDefaut();
      } else if (t == TypeQuestion.qcmSimple) {
        var vu = false;
        for (final l in _lignes) {
          l.bon = l.bon && !vu;
          vu = vu || l.bon;
        }
      }
      _erreur = null;
    });
    _synchroniserTrous();
  }

  void _synchroniserTrous() {
    if (_type != TypeQuestion.texteATrous) return;
    final presents = {for (final m in ContenuQuestion.motifTrou.allMatches(_enonce.text)) m.group(1)!};
    final retires = _trous.keys.where((k) => !presents.contains(k)).toList();
    final ajoutes = presents.where((k) => !_trous.containsKey(k)).toList();
    if (retires.isEmpty && ajoutes.isEmpty) return;
    setState(() {
      for (final k in retires) {
        _trous.remove(k)?.dispose();
      }
      for (final k in ajoutes) {
        _trous[k] = TextEditingController();
      }
    });
  }

  void _insererTrou() {
    final pris = _trous.keys.toSet();
    var n = 1;
    while (pris.contains('$n')) {
      n++;
    }
    final sel = _enonce.selection;
    final texte = _enonce.text;
    final position = sel.isValid ? sel.start : texte.length;
    final marque = '[[$n]]';
    _enonce.value = TextEditingValue(
      text: texte.replaceRange(position, sel.isValid ? sel.end : texte.length, marque),
      selection: TextSelection.collapsed(offset: position + marque.length),
    );
  }

  @override
  void dispose() {
    for (final c in [_enonce, _explication, _source, _tags, _acceptees, _valeur, _tolerance, _unite]) {
      c.dispose();
    }
    for (final l in _lignes) {
      l.dispose();
    }
    for (final c in _trous.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _textes(String brut, {String separateur = '\n'}) =>
      [for (final t in brut.split(separateur)) if (t.trim().isNotEmpty) t.trim()];

  ContenuQuestion _construire() {
    final contenu = <String, dynamic>{};
    final reponse = <String, dynamic>{};
    switch (_type) {
      case TypeQuestion.qcmSimple:
      case TypeQuestion.qcmMultiple:
        contenu['choix'] = [for (final l in _lignes) ItemQuestion(l.id, l.texte.text.trim()).versJson()];
        reponse['bonnes'] = [for (final l in _lignes) if (l.bon) l.id];
      case TypeQuestion.vraiFaux:
        reponse['valeur'] = _vrai;
      case TypeQuestion.reponseCourte:
        reponse['acceptees'] = _textes(_acceptees.text);
      case TypeQuestion.texteATrous:
        reponse['trous'] = {for (final e in _trous.entries) e.key: _textes(e.value.text, separateur: '/')};
      case TypeQuestion.association:
        contenu['gauche'] = [for (final l in _lignes) ItemQuestion(l.id, l.texte.text.trim()).versJson()];
        contenu['droite'] = [for (final l in _lignes) ItemQuestion('d${l.id}', l.autre.text.trim()).versJson()];
        reponse['paires'] = {for (final l in _lignes) l.id: 'd${l.id}'};
      case TypeQuestion.classement:
        contenu['elements'] = [for (final l in _lignes) ItemQuestion(l.id, l.texte.text.trim()).versJson()];
        reponse['ordre'] = [for (final l in _lignes) l.id];
      case TypeQuestion.calcul:
        final v = lireNombre(_valeur.text);
        if (v != null) reponse['valeur'] = v == v.roundToDouble() ? v.round() : v;
        final t = lireNombre(_tolerance.text);
        if (t != null) reponse['tolerance'] = t;
        if (_unite.text.trim().isNotEmpty) reponse['unite'] = _unite.text.trim();
    }
    return ContenuQuestion(
      type: _type,
      difficulte: _difficulte,
      competenceId: _competenceId,
      chapitreId: _chapitreId,
      leconId: _chapitreId == null ? null : _leconId,
      enonce: _enonce.text,
      contenu: contenu,
      reponse: reponse,
      explication: _explication.text,
      tempsRecommandeS: _temps,
      source: _source.text,
      tags: _textes(_tags.text, separateur: ','),
      mediaChemin: _mediaChemin,
      mediaType: _mediaType,
    );
  }

  Future<void> _executer(Future<void> Function() action, {String? succes}) async {
    setState(() {
      _occupe = true;
      _erreur = null;
    });
    try {
      await action();
      ref
        ..invalidate(questionsMatiereProvider(widget.matiereId))
        ..invalidate(questionsATraiterProvider)
        ..invalidate(questionsSignaleesProvider);
      if (succes != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(succes)));
      }
    } on ErreurBanque catch (e) {
      if (mounted) setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<void> _enregistrer() => _executer(() async {
        final recu = await ref
            .read(banqueQuestionsRepositoryProvider)
            .enregistrer(_id, widget.matiereId, _construire(), petitesClasses: widget.petitesClasses);
        if (!mounted) return;
        if (recu) await _relire();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(recu
              ? (_question?.versionPubliee != null && _question?.statut != StatutContenu.publiee
                  ? 'Brouillon enregistré. Les élèves gardent la version publiée jusqu’à la prochaine publication.'
                  : 'Brouillon enregistré.')
              : 'Pas de réseau : brouillon gardé sur l’appareil, envoyé au retour du réseau.'),
        ));
      });

  Future<void> _relire() async {
    final liste = await ref.read(banqueQuestionsRepositoryProvider).questions(widget.matiereId);
    final q = liste.where((q) => q.id == _id).firstOrNull;
    if (mounted && q != null) setState(() => _question = q);
  }

  Future<void> _action(String action, String succes) async {
    String? remarque;
    if (action == 'renvoyer') {
      remarque = await _demanderRemarque();
      if (remarque == null) return;
    }
    await _executer(() async {
      await ref.read(banqueQuestionsRepositoryProvider).changerStatut(_id, action, remarque: remarque);
      await _relire();
    }, succes: succes);
  }

  Future<String?> _demanderRemarque() {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Renvoyer à l’auteur'),
        content: TextField(
          key: const Key('remarque_revision'),
          controller: c,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Ce qui est à reprendre'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (c.text.trim().isNotEmpty) Navigator.of(d).pop(c.text.trim());
            },
            child: const Text('Renvoyer'),
          ),
        ],
      ),
    );
  }

  Future<void> _choisirImage() async {
    XFile? f;
    try {
      f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1600, maxHeight: 1600);
    } catch (_) {
      setState(() => _erreur = 'Impossible d’ouvrir la galerie.');
      return;
    }
    if (f == null) return;
    final octets = await f.readAsBytes();
    final nom = f.name.toLowerCase();
    final ext = nom.endsWith('.png') ? 'png' : nom.endsWith('.webp') ? 'webp' : 'jpg';
    await _executer(() async {
      final chemin = await ref.read(banqueQuestionsRepositoryProvider).envoyerMedia(_id, octets, ext);
      setState(() {
        _mediaChemin = chemin;
        _mediaType = 'image';
      });
    }, succes: 'Image jointe. Enregistrez le brouillon pour la garder.');
  }

  @override
  Widget build(BuildContext context) {
    final structure = ref.watch(structureMatiereProvider(widget.matiereId)).valueOrNull ?? const StructureMatiere();
    final schema = Theme.of(context).colorScheme;
    final types = [for (final t in TypeQuestion.values) if (!widget.petitesClasses || t.petitesClasses) t];
    final chapitre = structure.chapitres.where((c) => c.id == _chapitreId).firstOrNull;
    final q = _question;
    final apercu = _construire();
    final erreurApercu = apercu.erreur(petitesClasses: widget.petitesClasses);

    return Scaffold(
      appBar: AppBar(title: Text(q == null ? 'Nouvelle question' : 'Question')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          Text(widget.titreMatiere, style: TextStyle(color: schema.onSurfaceVariant)),
          if (q != null) _BandeauStatut(question: q),
          if (widget.petitesClasses)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Petites classes (CP1 à CE2) : types adaptés et trois choix au plus.'),
            ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<TypeQuestion>(
                key: const Key('question_type'),
                initialValue: types.contains(_type) ? _type : types.first,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                items: [for (final t in types) DropdownMenuItem(value: t, child: Text(t.libelle))],
                onChanged: (t) => t == null ? null : _changerType(t),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<Difficulte>(
                key: const Key('question_difficulte'),
                initialValue: _difficulte,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Difficulté', border: OutlineInputBorder()),
                items: [for (final d in Difficulte.values) DropdownMenuItem(value: d, child: Text(d.libelle))],
                onChanged: (d) => setState(() => _difficulte = d ?? _difficulte),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('question_competence'),
            initialValue: structure.competences.any((c) => c.id == _competenceId) ? _competenceId : null,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Compétence travaillée',
              border: const OutlineInputBorder(),
              helperText: structure.competences.isEmpty ? 'Ajoutez d’abord une compétence (Chapitres et compétences).' : null,
            ),
            items: [
              for (final c in structure.competences)
                DropdownMenuItem(value: c.id, child: Text('${c.code} — ${c.libelle}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _competenceId = v),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                key: const Key('question_chapitre'),
                initialValue: chapitre?.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Chapitre', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('—')),
                  for (final c in structure.chapitres)
                    DropdownMenuItem<String?>(value: c.id, child: Text(c.titre, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() {
                  _chapitreId = v;
                  _leconId = null;
                }),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String?>(
                key: ValueKey('question_lecon_$_chapitreId'),
                initialValue: chapitre?.lecons.any((l) => l.id == _leconId) == true ? _leconId : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Leçon', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('—')),
                  for (final l in chapitre?.lecons ?? const <LeconChapitre>[])
                    DropdownMenuItem<String?>(value: l.id, child: Text(l.titre, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: chapitre == null ? null : (v) => setState(() => _leconId = v),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            key: const Key('question_enonce'),
            controller: _enonce,
            onChanged: (_) => setState(() {}),
            maxLines: 4,
            minLines: 2,
            maxLength: 4000,
            decoration: InputDecoration(
              labelText: 'Énoncé',
              border: const OutlineInputBorder(),
              helperText: _type == TypeQuestion.texteATrous ? 'Placez les trous avec [[1]], [[2]]…' : null,
            ),
          ),
          if (_type == TypeQuestion.texteATrous)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('inserer_trou'),
                onPressed: _insererTrou,
                icon: const Icon(Icons.space_bar),
                label: const Text('Insérer un trou'),
              ),
            ),
          _image(schema),
          const SizedBox(height: 8),
          Text('Réponse', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _editeurReponse(),
          const SizedBox(height: 12),
          TextField(
            key: const Key('question_explication'),
            controller: _explication,
            onChanged: (_) => setState(() {}),
            maxLines: 3,
            minLines: 2,
            maxLength: 4000,
            decoration: const InputDecoration(
              labelText: 'Explication (montrée à l’élève après sa réponse)',
              border: OutlineInputBorder(),
            ),
          ),
          Row(children: [
            const Text('Temps conseillé'),
            Expanded(
              child: Slider(
                value: _temps.toDouble(),
                min: 15,
                max: 600,
                divisions: 39,
                label: _duree(_temps),
                onChanged: (v) => setState(() => _temps = v.round()),
              ),
            ),
            Text(_duree(_temps)),
          ]),
          TextField(
            controller: _source,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'Source pédagogique (facultatif)',
              hintText: 'Ex. : manuel de 7e, BEPC 2024',
              border: OutlineInputBorder(),
            ),
          ),
          TextField(
            controller: _tags,
            decoration: const InputDecoration(
              labelText: 'Mots-clés (séparés par des virgules)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (erreurApercu == null)
            Text('Bonne réponse : ${apercu.bonneReponseLisible()}',
                key: const Key('question_apercu'), style: TextStyle(color: schema.primary)),
          if (_erreur != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_erreur!, key: const Key('question_erreur'), style: TextStyle(color: schema.error)),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('question_enregistrer'),
            onPressed: _occupe ? null : _enregistrer,
            icon: const Icon(Icons.save_outlined),
            label: Text(_occupe ? 'Patientez…' : 'Enregistrer le brouillon'),
          ),
          if (q != null && !q.enAttenteEnvoi) ..._actionsCircuit(q),
        ],
      ),
    );
  }

  List<Widget> _actionsCircuit(Question q) {
    final boutons = <Widget>[];
    void ajouter(String cle, String libelle, String action, String succes, {bool principal = false}) {
      boutons.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: principal
            ? FilledButton.tonal(
                key: Key(cle), onPressed: _occupe ? null : () => _action(action, succes), child: Text(libelle))
            : OutlinedButton(key: Key(cle), onPressed: _occupe ? null : () => _action(action, succes), child: Text(libelle)),
      ));
    }

    switch (q.statut) {
      case StatutContenu.brouillon:
        ajouter('question_soumettre', 'Envoyer en validation', 'soumettre', 'Envoyée en validation.', principal: true);
      case StatutContenu.revision:
        ajouter('question_valider', 'Valider', 'valider', 'Validée.', principal: true);
        ajouter('question_renvoyer', 'Renvoyer à l’auteur', 'renvoyer', 'Renvoyée à l’auteur.');
      case StatutContenu.validee:
        ajouter('question_publier', 'Publier pour les élèves', 'publier', 'Publiée : les élèves la reçoivent.',
            principal: true);
        ajouter('question_renvoyer', 'Renvoyer à l’auteur', 'renvoyer', 'Renvoyée à l’auteur.');
      case StatutContenu.publiee:
        boutons.add(const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Modifier et enregistrer crée une nouvelle version ; les élèves gardent la version publiée '
              'jusqu’à la prochaine publication.'),
        ));
    }
    return boutons;
  }

  static String _duree(int s) => s < 60 ? '$s s' : (s % 60 == 0 ? '${s ~/ 60} min' : '${s ~/ 60} min ${s % 60}');

  Widget _image(ColorScheme schema) => Row(children: [
        Icon(_mediaChemin == null ? Icons.image_outlined : Icons.check_circle,
            color: _mediaChemin == null ? null : schema.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(_mediaChemin == null ? 'Image (facultative)' : 'Image jointe')),
        if (_mediaChemin != null)
          IconButton(
            tooltip: 'Retirer l’image',
            onPressed: () => setState(() {
              _mediaChemin = null;
              _mediaType = null;
            }),
            icon: const Icon(Icons.close),
          ),
        IconButton(
          tooltip: 'Choisir une image',
          onPressed: _occupe ? null : _choisirImage,
          icon: const Icon(Icons.add_photo_alternate_outlined),
        ),
      ]);

  Widget _editeurReponse() {
    switch (_type) {
      case TypeQuestion.qcmSimple:
      case TypeQuestion.qcmMultiple:
        final max = widget.petitesClasses && _type == TypeQuestion.qcmSimple ? 3 : 6;
        return Column(children: [
          for (final (i, l) in _lignes.indexed)
            Row(children: [
              _type == TypeQuestion.qcmSimple
                  ? IconButton(
                      key: ValueKey('bon_${l.id}'),
                      tooltip: 'Bonne réponse',
                      onPressed: () => setState(() {
                        for (final x in _lignes) {
                          x.bon = x == l;
                        }
                      }),
                      icon: Icon(l.bon ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                    )
                  : Checkbox(
                      key: ValueKey('bon_${l.id}'),
                      value: l.bon,
                      onChanged: (v) => setState(() => l.bon = v ?? false),
                    ),
              Expanded(
                child: TextField(
                  key: ValueKey('choix_${l.id}'),
                  controller: l.texte,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(labelText: 'Choix ${i + 1}', isDense: true),
                ),
              ),
              _retirer(l, min: 2),
            ]),
          _ajouter(max, 'c', 'Ajouter un choix'),
          const Align(alignment: Alignment.centerLeft, child: Text('Cochez la ou les bonnes réponses.')),
        ]);
      case TypeQuestion.vraiFaux:
        return SegmentedButton<bool>(
          key: const Key('vrai_faux'),
          segments: const [
            ButtonSegment(value: true, label: Text('Vrai')),
            ButtonSegment(value: false, label: Text('Faux')),
          ],
          selected: {_vrai},
          onSelectionChanged: (s) => setState(() => _vrai = s.first),
        );
      case TypeQuestion.reponseCourte:
        return TextField(
          key: const Key('reponses_acceptees'),
          controller: _acceptees,
          maxLines: 3,
          minLines: 2,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Réponses acceptées (une par ligne)',
            helperText: 'Majuscules, accents et point final ne comptent pas.',
            border: OutlineInputBorder(),
          ),
        );
      case TypeQuestion.texteATrous:
        if (_trous.isEmpty) return const Text('Ajoutez au moins un trou dans l’énoncé.');
        final cles = _trous.keys.toList()..sort();
        return Column(children: [
          for (final k in cles)
            TextField(
              key: ValueKey('trou_$k'),
              controller: _trous[k],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: 'Trou [[$k]] : réponses acceptées (séparées par /)', isDense: true),
            ),
        ]);
      case TypeQuestion.association:
        return Column(children: [
          for (final l in _lignes)
            Row(children: [
              Expanded(
                child: TextField(
                  key: ValueKey('gauche_${l.id}'),
                  controller: l.texte,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Terme', isDense: true),
                ),
              ),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward, size: 18)),
              Expanded(
                child: TextField(
                  key: ValueKey('droite_${l.id}'),
                  controller: l.autre,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Va avec', isDense: true),
                ),
              ),
              _retirer(l, min: 2),
            ]),
          _ajouter(8, 'g', 'Ajouter une paire'),
          const Align(alignment: Alignment.centerLeft, child: Text('Les termes de droite seront mélangés pour l’élève.')),
        ]);
      case TypeQuestion.classement:
        return Column(children: [
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (a, b) => setState(() => _lignes.insert(b, _lignes.removeAt(a))),
            children: [
              for (final (i, l) in _lignes.indexed)
                Row(key: ValueKey('ligne_${l.id}'), children: [
                  ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
                  const SizedBox(width: 8),
                  Text('${i + 1}.'),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: ValueKey('element_${l.id}'),
                      controller: l.texte,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(isDense: true),
                    ),
                  ),
                  _retirer(l, min: 2),
                ]),
            ],
          ),
          _ajouter(8, 'e', 'Ajouter un élément'),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Saisissez les éléments dans le bon ordre ; ils seront mélangés pour l’élève.'),
          ),
        ]);
      case TypeQuestion.calcul:
        final nombre = FilteringTextInputFormatter.allow(RegExp(r'[0-9,.\- ]'));
        return Row(children: [
          Expanded(
            child: TextField(
              key: const Key('calcul_valeur'),
              controller: _valeur,
              inputFormatters: [nombre],
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Résultat', isDense: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const Key('calcul_tolerance'),
              controller: _tolerance,
              inputFormatters: [nombre],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Écart toléré', isDense: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _unite,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Unité', isDense: true),
            ),
          ),
        ]);
    }
  }

  Widget _retirer(_Ligne l, {required int min}) => IconButton(
        tooltip: 'Retirer',
        onPressed: _lignes.length <= min
            ? null
            : () => setState(() {
                  _lignes.remove(l);
                  l.dispose();
                }),
        icon: const Icon(Icons.remove_circle_outline),
      );

  Widget _ajouter(int max, String prefixe, String libelle) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: Key('ajouter_$prefixe'),
          onPressed: _lignes.length >= max ? null : () => setState(() => _lignes.add(_Ligne(_nouvelId(prefixe), ''))),
          icon: const Icon(Icons.add),
          label: Text(libelle),
        ),
      );
}

/// Où en est la question dans le circuit.
class _BandeauStatut extends StatelessWidget {
  const _BandeauStatut({required this.question});

  final Question question;

  @override
  Widget build(BuildContext context) {
    final q = question;
    final schema = Theme.of(context).colorScheme;
    final lignes = <String>[
      q.enAttenteEnvoi ? 'Sur cet appareil — envoi au retour du réseau' : '${q.statut.libelle} · version ${q.versionTravail}',
      if (q.diffuseePendantModification) 'Version ${q.versionPubliee} servie aux élèves en attendant',
      if (q.suspendue) 'Suspendue après signalements',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final l in lignes) Text(l, style: TextStyle(fontWeight: FontWeight.w600, color: schema.primary)),
        if (q.remarqueRevision != null && q.statut == StatutContenu.brouillon)
          Text('À reprendre : ${q.remarqueRevision}', style: TextStyle(color: schema.error)),
      ]),
    );
  }
}
