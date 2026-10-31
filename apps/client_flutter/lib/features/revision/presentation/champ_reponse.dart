import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/question.dart';
import '../domain/quiz.dart';

/// Saisie de la réponse à une question, pour chaque type (quiz et examen).
/// Donne la réponse sous la forme attendue par [ContenuQuestion.corriger],
/// et si elle est assez remplie pour être validée.
class ChampReponse extends StatefulWidget {
  const ChampReponse({
    super.key,
    required this.question,
    required this.onChanged,
    this.initiale,
    this.petitesClasses = false,
    this.hasard,
  });

  final QuestionQuiz question;

  /// Réponse déjà donnée (examen : retour en arrière).
  final Object? initiale;
  final void Function(Object? donnee, bool complete) onChanged;
  final bool petitesClasses;
  final Random? hasard;

  @override
  State<ChampReponse> createState() => _ChampReponseState();
}

class _ChampReponseState extends State<ChampReponse> {
  late final Random _hasard = widget.hasard ?? Random();
  late final ContenuQuestion _c = widget.question.contenu;
  List<ItemQuestion> _ordreChoix = const [];
  List<ItemQuestion> _ordreDroite = const [];
  final _texte = TextEditingController();
  final Map<String, TextEditingController> _trous = {};
  Object? _donnee;

  @override
  void initState() {
    super.initState();
    final init = widget.initiale;
    switch (_c.type) {
      case TypeQuestion.qcmSimple:
      case TypeQuestion.qcmMultiple:
        _ordreChoix = melanger(_c.choix, _hasard);
        _donnee = <String>{...?(init as Iterable?)?.map((e) => '$e')};
      case TypeQuestion.vraiFaux:
        _donnee = init is bool ? init : null;
      case TypeQuestion.association:
        _ordreDroite = melanger(_c.droite, _hasard);
        _donnee = <String, String>{...?(init as Map?)?.map((k, v) => MapEntry('$k', '$v'))};
      case TypeQuestion.classement:
        _donnee = init is List
            ? [for (final e in init) '$e']
            : [for (final e in melanger(_c.elements, _hasard, eviterIdentite: true)) e.id];
      case TypeQuestion.texteATrous:
        final m = init is Map ? init : const {};
        for (final t in _c.trous) {
          _trous[t] = TextEditingController(text: '${m[t] ?? ''}');
        }
      case TypeQuestion.reponseCourte:
      case TypeQuestion.calcul:
        _texte.text = init is String ? init : '';
    }
    // Un classement est déjà « répondu » (ordre de départ) ; on le signale.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _signaler();
    });
  }

  @override
  void dispose() {
    _texte.dispose();
    for (final c in _trous.values) {
      c.dispose();
    }
    super.dispose();
  }

  Object? get _reponse => switch (_c.type) {
        TypeQuestion.reponseCourte || TypeQuestion.calcul => _texte.text,
        TypeQuestion.texteATrous => {for (final e in _trous.entries) e.key: e.value.text},
        _ => _donnee,
      };

  bool get _complete => switch (_c.type) {
        TypeQuestion.qcmSimple || TypeQuestion.qcmMultiple => (_donnee as Set).isNotEmpty,
        TypeQuestion.vraiFaux => _donnee is bool,
        TypeQuestion.reponseCourte || TypeQuestion.calcul => _texte.text.trim().isNotEmpty,
        TypeQuestion.texteATrous => _trous.values.any((t) => t.text.trim().isNotEmpty),
        TypeQuestion.association => (_donnee as Map).length == _c.gauche.length,
        TypeQuestion.classement => true,
      };

  void _signaler() => widget.onChanged(_reponse, _complete);

  void _maj(VoidCallback f) {
    setState(f);
    _signaler();
  }

  @override
  Widget build(BuildContext context) {
    switch (_c.type) {
      case TypeQuestion.qcmSimple:
      case TypeQuestion.qcmMultiple:
        final choisis = _donnee as Set<String>;
        final multiple = _c.type == TypeQuestion.qcmMultiple;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (multiple) const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Plusieurs réponses possibles.')),
          for (final x in _ordreChoix)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CaseChoix(
                cle: 'choix_${x.id}',
                texte: x.texte,
                choisi: choisis.contains(x.id),
                multiple: multiple,
                grand: widget.petitesClasses,
                onTap: () => _maj(() {
                  if (multiple) {
                    choisis.contains(x.id) ? choisis.remove(x.id) : choisis.add(x.id);
                  } else {
                    choisis
                      ..clear()
                      ..add(x.id);
                  }
                }),
              ),
            ),
        ]);
      case TypeQuestion.vraiFaux:
        return Row(children: [
          for (final v in [true, false]) ...[
            Expanded(
              child: CaseChoix(
                cle: 'vf_$v',
                texte: v ? 'Vrai' : 'Faux',
                choisi: _donnee == v,
                grand: true,
                onTap: () => _maj(() => _donnee = v),
              ),
            ),
            if (v) const SizedBox(width: 12),
          ],
        ]);
      case TypeQuestion.reponseCourte:
        return TextField(
          key: const Key('quiz_texte'),
          controller: _texte,
          autofocus: true,
          onChanged: (_) => _maj(() {}),
          decoration: const InputDecoration(labelText: 'Ta réponse', border: OutlineInputBorder()),
        );
      case TypeQuestion.calcul:
        final unite = _c.reponse['unite'];
        return TextField(
          key: const Key('quiz_texte'),
          controller: _texte,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.\- ]'))],
          onChanged: (_) => _maj(() {}),
          decoration: InputDecoration(
            labelText: 'Ton résultat',
            suffixText: unite == null || '$unite'.isEmpty ? null : '$unite',
            border: const OutlineInputBorder(),
          ),
        );
      case TypeQuestion.texteATrous:
        return Column(children: [
          for (final e in _trous.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                key: ValueKey('quiz_trou_${e.key}'),
                controller: e.value,
                onChanged: (_) => _maj(() {}),
                decoration: InputDecoration(labelText: 'Trou (${e.key})', border: const OutlineInputBorder()),
              ),
            ),
        ]);
      case TypeQuestion.association:
        final paires = _donnee as Map<String, String>;
        return Column(children: [
          for (final g in _c.gauche)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(child: Text(g.texte, style: const TextStyle(fontWeight: FontWeight.w600))),
                const Icon(Icons.arrow_forward, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String>(
                    key: ValueKey('quiz_paire_${g.id}'),
                    isExpanded: true,
                    hint: const Text('Choisir'),
                    value: paires[g.id],
                    items: [for (final d in _ordreDroite) DropdownMenuItem(value: d.id, child: Text(d.texte))],
                    onChanged: (v) => _maj(() {
                      if (v != null) paires[g.id] = v;
                    }),
                  ),
                ),
              ]),
            ),
        ]);
      case TypeQuestion.classement:
        final ordre = _donnee as List<String>;
        final textes = {for (final e in _c.elements) e.id: e.texte};
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Fais glisser pour mettre dans le bon ordre.'),
          const SizedBox(height: 8),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorderItem: (a, b) => _maj(() => ordre.insert(b, ordre.removeAt(a))),
            children: [
              for (final (i, id) in ordre.indexed)
                Card(
                  key: ValueKey('quiz_element_$id'),
                  child: ListTile(leading: Text('${i + 1}'), title: Text(textes[id] ?? ''), trailing: const Icon(Icons.drag_handle)),
                ),
            ],
          ),
        ]);
    }
  }
}

/// Une case à toucher (choix d'un QCM, Vrai ou Faux).
class CaseChoix extends StatelessWidget {
  const CaseChoix({
    super.key,
    required this.cle,
    required this.texte,
    required this.choisi,
    required this.onTap,
    this.multiple = false,
    this.grand = false,
  });

  final String cle;
  final String texte;
  final bool choisi;
  final bool multiple;
  final bool grand;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final schema = Theme.of(context).colorScheme;
    return Material(
      color: choisi ? schema.primaryContainer : schema.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: Key(cle),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: grand ? 20 : 14),
          child: Row(children: [
            Icon(
              multiple
                  ? (choisi ? Icons.check_box : Icons.check_box_outline_blank)
                  : (choisi ? Icons.radio_button_checked : Icons.radio_button_unchecked),
              color: choisi ? schema.primary : null,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(texte, style: TextStyle(fontSize: grand ? 20 : 16))),
          ]),
        ),
      ),
    );
  }
}

/// Texte d'une question tel qu'on le lit à voix haute : énoncé puis choix.
String texteQuestionALire(ContenuQuestion c) {
  final b = StringBuffer(c.enonce);
  switch (c.type) {
    case TypeQuestion.qcmSimple:
    case TypeQuestion.qcmMultiple:
      for (final x in c.choix) {
        b.write('. ${x.texte}');
      }
    case TypeQuestion.vraiFaux:
      b.write('. Vrai, ou faux ?');
    default:
      break;
  }
  return b.toString();
}
