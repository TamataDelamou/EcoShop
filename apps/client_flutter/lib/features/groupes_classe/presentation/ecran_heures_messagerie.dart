import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/groupes_classe_providers.dart';
import '../domain/groupe_classe.dart';

/// Direction : heures de messagerie de l'école (REG-34).
///
/// Pendant ces heures, les élèves écrivent dans les groupes et le personnel
/// est prévenu des messages des parents. En dehors, les messages partent
/// quand même mais personne n'est réveillé : la notification attend
/// l'ouverture. Par défaut : du lundi au samedi, de 7 h à 19 h.
class EcranHeuresMessagerie extends ConsumerStatefulWidget {
  const EcranHeuresMessagerie({super.key, required this.etablissementId, this.actuelles});

  final String etablissementId;
  final HeuresMessagerie? actuelles;

  @override
  ConsumerState<EcranHeuresMessagerie> createState() => _EcranHeuresMessagerieState();
}

class _EcranHeuresMessagerieState extends ConsumerState<EcranHeuresMessagerie> {
  late TimeOfDay _debut = _lire(widget.actuelles?.debut ?? '07:00');
  late TimeOfDay _fin = _lire(widget.actuelles?.fin ?? '19:00');
  late final Set<int> _jours = {...(widget.actuelles?.jours ?? const [1, 2, 3, 4, 5, 6])};
  bool _enCours = false;
  String? _erreur;

  static TimeOfDay _lire(String hhmm) {
    final p = hhmm.split(':');
    return TimeOfDay(hour: int.tryParse(p.first) ?? 0, minute: p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
  }

  static String _ecrire(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  HeuresMessagerie get _apercu => HeuresMessagerie(debut: _ecrire(_debut), fin: _ecrire(_fin), jours: [..._jours]);

  Future<void> _choisir(bool debut) async {
    final choisi = await showTimePicker(context: context, initialTime: debut ? _debut : _fin);
    if (choisi == null) return;
    setState(() {
      if (debut) {
        _debut = choisi;
      } else {
        _fin = choisi;
      }
    });
  }

  Future<void> _enregistrer() async {
    final d = _debut.hour * 60 + _debut.minute;
    final f = _fin.hour * 60 + _fin.minute;
    if (f <= d) {
      setState(() => _erreur = const ErreurGroupe('HEURES_INVALIDES').message);
      return;
    }
    if (_jours.isEmpty) {
      setState(() => _erreur = const ErreurGroupe('JOURS_INVALIDES').message);
      return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      await ref
          .read(groupesClasseRepositoryProvider)
          .definirHeures(widget.etablissementId, debut: _ecrire(_debut), fin: _ecrire(_fin), jours: [..._jours]..sort());
      if (mounted) Navigator.of(context).pop();
    } on ErreurGroupe catch (e) {
      if (mounted) setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Heures de messagerie')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Pendant ces heures, les élèves écrivent dans les groupes de classe et le personnel est prévenu des '
            'messages des parents. En dehors, les messages partent quand même, mais la notification attend '
            'l’ouverture : personne n’est dérangé le soir ou le dimanche.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('heure_debut'),
                onPressed: () => _choisir(true),
                icon: const Icon(Icons.wb_sunny_outlined),
                label: Text('De ${HeuresMessagerie.heure(_ecrire(_debut))}'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('heure_fin'),
                onPressed: () => _choisir(false),
                icon: const Icon(Icons.bedtime_outlined),
                label: Text('À ${HeuresMessagerie.heure(_ecrire(_fin))}'),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Text('Jours', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var j = 1; j <= 7; j++)
              FilterChip(
                key: Key('jour_$j'),
                label: Text(HeuresMessagerie.nomsJours[j - 1]),
                selected: _jours.contains(j),
                onSelected: (oui) => setState(() {
                  if (oui) {
                    _jours.add(j);
                  } else {
                    _jours.remove(j);
                  }
                }),
              ),
          ]),
          const SizedBox(height: 16),
          Text(
            key: const Key('apercu_heures'),
            'Les familles liront : « L’école lit ses messages ${_apercu.libelle}. »',
            style: theme.textTheme.bodySmall,
          ),
          if (_erreur != null) ...[
            const SizedBox(height: 8),
            Text(_erreur!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('enregistrer_heures'),
            onPressed: _enCours ? null : _enregistrer,
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}
