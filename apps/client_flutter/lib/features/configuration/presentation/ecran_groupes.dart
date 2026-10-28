import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../etablissement/domain/etablissement.dart';
import '../../scolarite/application/scolarite_providers.dart';
import '../../scolarite/domain/classe.dart';
import '../../scolarite/domain/inscription.dart';
import '../application/configuration_providers.dart';
import '../domain/configuration.dart';
import 'elements_configuration.dart';

/// Groupes pédagogiques (REG-23) : demi-classes de TP, langues vivantes,
/// options, soutien. Deux groupes d'une même classe peuvent avoir cours au
/// même moment dans l'emploi du temps.
class EcranGroupes extends ConsumerWidget {
  const EcranGroupes({super.key, required this.etablissement, required this.anneeId, this.classe});

  final Etablissement etablissement;
  final String anneeId;

  /// Null : tous les groupes de l'année.
  final Classe? classe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupes = ref.watch(groupesProvider(anneeId));
    final classes = ref.watch(structureEtablissementProvider(anneeId)).valueOrNull?.classes ?? const <Classe>[];
    final nomsClasses = {for (final c in classes) c.id: c.nom};
    final liste = (groupes.valueOrNull ?? const <GroupePedagogique>[])
        .where((g) => classe == null || g.classeId == classe!.id)
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(classe == null ? 'Groupes pédagogiques' : 'Groupes — ${classe!.nom}')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('bouton_nouveau_groupe'),
        onPressed: () => _editer(context, ref, classes, null),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau groupe'),
      ),
      body: groupes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => ErreurChargement(onReessayer: () => ref.invalidate(groupesProvider(anneeId))),
        data: (_) => liste.isEmpty
            ? EtatVide(
                icone: Icons.groups_2_outlined,
                titre: 'Aucun groupe',
                texte: 'Créez un groupe quand une partie seulement de la classe suit un cours : '
                    'Anglais / Arabe, demi-classe de TP, option, soutien.',
                action: FilledButton.icon(
                  onPressed: () => _editer(context, ref, classes, null),
                  icon: const Icon(Icons.add),
                  label: const Text('Créer un groupe'),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  const Explication(
                    'Les groupes d’une même classe ont cours en même temps (Anglais pour un groupe, Arabe pour l’autre). '
                    'Indiquez le groupe dans « Cours et enseignants » : l’emploi du temps en tient compte.',
                  ),
                  for (final g in liste)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.groups_2_outlined)),
                        title: Text(g.nom, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text([
                          g.libelleType,
                          if (g.classeId != null) nomsClasses[g.classeId] ?? '',
                          '${g.effectif} élève${g.effectif > 1 ? 's' : ''}',
                        ].where((t) => t.isNotEmpty).join(' · ')),
                        onTap: g.classeId == null
                            ? null
                            : () => Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => _EcranMembres(etablissement: etablissement, groupe: g, anneeId: anneeId),
                                )),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'modifier') await _editer(context, ref, classes, g);
                            if (v == 'retirer' && context.mounted) {
                              final ok = await executer(context, () => ref.read(configurationRepositoryProvider).retirerGroupe(g.id),
                                  succes: 'Groupe retiré.');
                              if (ok) rafraichirConfiguration(ref.invalidate, etablissementId: etablissement.id, anneeId: anneeId);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'modifier', child: Text('Modifier')),
                            PopupMenuItem(value: 'retirer', child: Text('Retirer')),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _editer(BuildContext context, WidgetRef ref, List<Classe> classes, GroupePedagogique? groupe) async {
    final nom = TextEditingController(text: groupe?.nom ?? '');
    final capacite = TextEditingController(text: groupe?.capacite?.toString() ?? '');
    var type = groupe?.type ?? 'demi_classe';
    var classeId = groupe?.classeId ?? classe?.id ?? (classes.isEmpty ? null : classes.first.id);
    final enregistre = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(groupe == null ? 'Nouveau groupe' : 'Modifier le groupe'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nom,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Nom', hintText: 'Groupe Anglais, Demi-groupe 1…'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: [
                    for (final e in GroupePedagogique.types.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => type = v ?? type),
                ),
                if (classe == null) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: classeId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Classe'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Plusieurs classes')),
                      for (final c in classes) DropdownMenuItem<String?>(value: c.id, child: Text(c.nom)),
                    ],
                    onChanged: (v) => setState(() => classeId = v),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: capacite,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Places (facultatif)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (enregistre != true || !context.mounted) return;
    if (nom.text.trim().isEmpty) {
      signaler(context, 'Donnez un nom au groupe.');
      return;
    }
    final g = GroupePedagogique(
      id: groupe?.id ?? const Uuid().v4(),
      etablissementId: etablissement.id,
      anneeScolaireId: anneeId,
      classeId: classeId,
      nom: nom.text.trim(),
      type: type,
      capacite: int.tryParse(capacite.text.trim()),
    );
    final ok = await executer(context, () => ref.read(configurationRepositoryProvider).enregistrerGroupe(g),
        succes: 'Groupe enregistré.');
    if (ok) rafraichirConfiguration(ref.invalidate, etablissementId: etablissement.id, anneeId: anneeId);
  }
}

/// Élèves d'un groupe, choisis parmi les inscrits de sa classe.
class _EcranMembres extends ConsumerStatefulWidget {
  const _EcranMembres({required this.etablissement, required this.groupe, required this.anneeId});

  final Etablissement etablissement;
  final GroupePedagogique groupe;
  final String anneeId;

  @override
  ConsumerState<_EcranMembres> createState() => _EcranMembresState();
}

class _EcranMembresState extends ConsumerState<_EcranMembres> {
  Set<String>? _choisis;
  bool _enCours = false;

  @override
  Widget build(BuildContext context) {
    final inscriptions = ref.watch(inscriptionsDeClasseProvider(widget.groupe.classeId!));
    final actuels = ref.watch(membresGroupeProvider(widget.groupe.id)).valueOrNull;
    _choisis ??= actuels == null ? null : {...actuels};
    final choisis = _choisis ?? <String>{};
    final eleves = inscriptions.valueOrNull ?? const <Inscription>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.groupe.nom),
        actions: [
          IconButton(
            tooltip: 'Première moitié de la classe (ordre alphabétique)',
            icon: const Icon(Icons.vertical_split_outlined),
            onPressed: eleves.isEmpty
                ? null
                : () => setState(() => _choisis = {
                      for (final i in eleves.take((eleves.length + 1) ~/ 2)) i.ficheEleveId,
                    }),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          onPressed: _enCours || _choisis == null
              ? null
              : () async {
                  setState(() => _enCours = true);
                  final ok = await executer(
                    context,
                    () => ref.read(configurationRepositoryProvider).definirMembresGroupe(
                          groupeId: widget.groupe.id,
                          etablissementId: widget.etablissement.id,
                          fiches: choisis,
                        ),
                    succes: '${choisis.length} élève(s) dans le groupe.',
                  );
                  if (!mounted) return;
                  setState(() => _enCours = false);
                  if (ok) {
                    ref.invalidate(membresGroupeProvider(widget.groupe.id));
                    rafraichirConfiguration(ref.invalidate, anneeId: widget.anneeId);
                    Navigator.of(context).pop();
                  }
                },
          icon: const Icon(Icons.check),
          label: Text('Enregistrer (${choisis.length})'),
        ),
      ),
      body: inscriptions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => ErreurChargement(onReessayer: () => ref.invalidate(inscriptionsDeClasseProvider(widget.groupe.classeId!))),
        data: (_) => eleves.isEmpty
            ? const EtatVide(
                icone: Icons.person_off_outlined,
                titre: 'Aucun élève inscrit dans la classe',
                texte: 'Inscrivez d’abord les élèves ; vous pourrez ensuite composer le groupe.',
              )
            : ListView(
                children: [
                  for (final i in eleves)
                    CheckboxListTile(
                      value: choisis.contains(i.ficheEleveId),
                      title: Text(i.fiche?.nomComplet ?? 'Élève'),
                      subtitle: i.fiche == null ? null : Text(i.fiche!.matricule),
                      onChanged: (v) => setState(() {
                        _choisis = {...choisis};
                        v == true ? _choisis!.add(i.ficheEleveId) : _choisis!.remove(i.ficheEleveId);
                      }),
                    ),
                ],
              ),
      ),
    );
  }
}
