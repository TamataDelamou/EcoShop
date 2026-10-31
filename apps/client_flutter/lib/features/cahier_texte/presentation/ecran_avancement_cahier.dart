import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/cahier_repository.dart';
import 'elements_cahier.dart';

/// Avancement du cahier de texte (REG-40), pour la direction : par classe et
/// matière, séances renseignées sur 14 jours comparées aux cours prévus à
/// l'emploi du temps, dernière séance et travail donné.
class EcranAvancementCahier extends ConsumerStatefulWidget {
  const EcranAvancementCahier({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  ConsumerState<EcranAvancementCahier> createState() => _EcranAvancementCahierState();
}

class _EcranAvancementCahierState extends ConsumerState<EcranAvancementCahier> {
  bool _seulementEnRetard = false;

  @override
  Widget build(BuildContext context) {
    final avancement = ref.watch(avancementCahierProvider(widget.etablissementId));
    final schema = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Avancement du cahier de texte')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(avancementCahierProvider(widget.etablissementId)),
        child: avancement.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(e is ErreurCahier ? e.message : 'Avancement indisponible pour le moment.', textAlign: TextAlign.center),
            ),
          ]),
          data: (lignes) {
            if (lignes.isEmpty) {
              return ListView(children: const [
                Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('Aucun cours à l’emploi du temps : l’avancement se calcule à partir des cours prévus.',
                      textAlign: TextAlign.center),
                ),
              ]);
            }
            final enRetard = [for (final l in lignes) if (l.taux < 0.5) l];
            final affichees = _seulementEnRetard ? enRetard : lignes;
            final total = lignes.fold<int>(0, (s, l) => s + l.prevues);
            final faites = lignes.fold<int>(0, (s, l) => s + l.renseignees.clamp(0, l.prevues));
            String? classe;
            return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
              Text(
                total == 0 ? '—' : '${(faites * 100 / total).round()} %',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Text('des cours des 14 derniers jours sont notés au cahier de texte', textAlign: TextAlign.center),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Seulement les retards (${enRetard.length})'),
                subtitle: const Text('Moins de la moitié des cours notés'),
                value: _seulementEnRetard,
                onChanged: (v) => setState(() => _seulementEnRetard = v),
              ),
              for (final l in affichees) ...[
                if (l.classe != classe) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
                    child: Text(classe = l.classe, style: Theme.of(context).textTheme.titleSmall),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text([l.matiere, if (l.enseignant != null && l.enseignant!.isNotEmpty) l.enseignant!].join(' · ')),
                      ),
                      Text('${l.renseignees}/${l.prevues}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: l.taux,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                      color: l.taux < 0.5 ? schema.error : null,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        l.derniere == null ? 'aucune séance notée' : 'dernière séance : ${dateLisible(l.derniere!).toLowerCase()}',
                        '${l.travaux} travail${l.travaux > 1 ? 'x' : ''} donné${l.travaux > 1 ? 's' : ''}',
                      ].join(' · '),
                      style: TextStyle(fontSize: 12, color: schema.onSurfaceVariant),
                    ),
                  ]),
                ),
              ],
            ]);
          },
        ),
      ),
    );
  }
}
