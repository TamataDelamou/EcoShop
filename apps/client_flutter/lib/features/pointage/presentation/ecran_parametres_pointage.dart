import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../application/pointage_providers.dart';
import '../domain/pointage.dart';

/// Réglages du pointage (Direction) : activation, heure limite d'arrivée,
/// fin des cours, jours de classe, avis envoyés aux familles.
class EcranParametresPointage extends ConsumerStatefulWidget {
  const EcranParametresPointage({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  ConsumerState<EcranParametresPointage> createState() => _EcranParametresPointageState();
}

class _EcranParametresPointageState extends ConsumerState<EcranParametresPointage> {
  ParametresPointage? _p;
  bool _enCours = false;
  String? _erreur;

  static const _jours = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

  Future<void> _choisirHeure(String actuelle, void Function(String) affecter) async {
    final morceaux = actuelle.split(':');
    final choisie = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(morceaux[0]), minute: int.parse(morceaux[1])),
    );
    if (choisie == null) return;
    setState(() => affecter('${choisie.hour.toString().padLeft(2, '0')}:${choisie.minute.toString().padLeft(2, '0')}'));
  }

  Future<void> _enregistrer() async {
    final p = _p;
    if (p == null) return;
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      await ref.read(pointageRepositoryProvider).enregistrerParametres(widget.etablissementId, p);
      ref.invalidate(parametresPointageProvider(widget.etablissementId));
      if (!mounted) return;
      final messager = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messager.showSnackBar(const SnackBar(content: Text('Réglages du pointage enregistrés.')));
    } on ErreurPointage catch (e) {
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _erreur = e.messageUtilisateur;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final charge = ref.watch(parametresPointageProvider(widget.etablissementId));
    _p ??= charge.value;
    final p = _p;

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages du pointage')),
      body: p == null
          ? Center(
              child: charge.hasError
                  ? Text((charge.error is ErreurPointage) ? (charge.error! as ErreurPointage).messageUtilisateur : 'Indisponible.')
                  : const CircularProgressIndicator(),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                SwitchListTile(
                  key: const Key('pointage_actif'),
                  contentPadding: EdgeInsets.zero,
                  value: p.actif,
                  onChanged: (v) => setState(() => _p = p.copier(actif: v)),
                  title: const Text('Pointage activé'),
                  subtitle: const Text('Avis aux familles et alertes d\'absence. Le portail fonctionne même désactivé.'),
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Heure limite d'arrivée"),
                  subtitle: const Text('Après elle, l\'élève est en retard ; les absents sont signalés à leur famille.'),
                  trailing: Text(p.heureLimiteArrivee, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  onTap: () => _choisirHeure(p.heureLimiteArrivee, (h) => _p = p.copier(heureLimiteArrivee: h)),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Fin des cours'),
                  subtitle: const Text('Une sortie avant cette heure, sans autorisation, est signalée à la famille.'),
                  trailing: Text(p.heureFinCours, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  onTap: () => _choisirHeure(p.heureFinCours, (h) => _p = p.copier(heureFinCours: h)),
                ),
                const SizedBox(height: 8),
                const Text('Jours de classe'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    for (var i = 1; i <= 7; i++)
                      FilterChip(
                        label: Text(_jours[i - 1]),
                        selected: p.joursClasse.contains(i),
                        onSelected: (oui) => setState(() {
                          final jours = {...p.joursClasse};
                          oui ? jours.add(i) : jours.remove(i);
                          _p = p.copier(joursClasse: jours.toList()..sort());
                        }),
                      ),
                  ],
                ),
                const Divider(height: 32),
                Text('Avis aux familles', style: Theme.of(context).textTheme.titleMedium),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: p.notifierArriveeSortie,
                  onChanged: (v) => setState(() => _p = p.copier(notifierArriveeSortie: v)),
                  title: const Text('Arrivée et sortie (push)'),
                  subtitle: const Text('Gratuit. Chaque parent peut aussi les couper pour lui-même.'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: p.smsAbsence,
                  onChanged: (v) => setState(() => _p = p.copier(smsAbsence: v)),
                  title: const Text('Absence : aussi par SMS'),
                  subtitle: const Text('Utilise un crédit SMS par parent prévenu. Le push part toujours.'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: p.smsSortieAnticipee,
                  onChanged: (v) => setState(() => _p = p.copier(smsSortieAnticipee: v)),
                  title: const Text('Sortie avant l\'heure : aussi par SMS'),
                  subtitle: const Text('Utilise un crédit SMS par parent prévenu.'),
                ),
                if (_erreur != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_erreur!, style: TextStyle(color: palette.erreur)),
                  ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: _enCours || p == null ? null : _enregistrer,
            child: _enCours
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Text('Enregistrer'),
          ),
        ),
      ),
    );
  }
}
