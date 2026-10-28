import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/postes_providers.dart';
import '../data/postes_repository.dart';

/// Direction › Personnel › Postes (REG-22, partie C) : postes de l'école,
/// nombre de personnes, droits groupés par domaine ; « Créer à partir d'un
/// modèle ». Le serveur refuse le cumul encaissement + comptabilité.
class EcranPostes extends ConsumerWidget {
  const EcranPostes({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postes = ref.watch(postesEtablissementProvider(etablissementId));
    return Scaffold(
      appBar: AppBar(title: const Text('Postes')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('bouton_creer_poste'),
        onPressed: () async {
          final modele = await showModalBottomSheet<ModelePoste>(
            context: context,
            showDragHandle: true,
            isScrollControlled: true,
            builder: (_) => const _ChoixModele(),
          );
          if (modele == null || !context.mounted) return;
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => EcranEditionPoste(etablissementId: etablissementId, modele: modele),
          ));
          ref.invalidate(postesEtablissementProvider(etablissementId));
        },
        icon: const Icon(Icons.add),
        label: const Text('Créer à partir d’un modèle'),
      ),
      body: postes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e is ErreurPostes ? e.message : 'Pas de connexion.')),
        data: (liste) => ListView.separated(
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: liste.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final p = liste[i];
            return ListTile(
              key: Key('poste_${p.id}'),
              leading: const Icon(Icons.badge_outlined),
              title: Text(p.nom),
              subtitle: Text([
                p.membres == 0 ? 'Personne' : p.membres == 1 ? '1 personne' : '${p.membres} personnes',
                p.codes.isEmpty ? 'droits par affectation ou rôle' : '${p.codes.length} droit(s)',
                if (!p.actif) 'désactivé',
              ].join(' · ')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => EcranEditionPoste(etablissementId: etablissementId, poste: p),
                ));
                ref.invalidate(postesEtablissementProvider(etablissementId));
              },
            );
          },
        ),
      ),
    );
  }
}

class _ChoixModele extends ConsumerWidget {
  const _ChoixModele();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modeles = ref.watch(modelesPostesProvider).valueOrNull ?? const [];
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Modèle de départ', style: Theme.of(context).textTheme.titleMedium),
            for (final m in modeles.where((m) => m.role == 'personnel'))
              ListTile(
                key: Key('modele_${m.code}'),
                title: Text(m.nom),
                subtitle: Text(m.description),
                onTap: () => Navigator.of(context).pop(m),
              ),
          ],
        ),
      ),
    );
  }
}

/// Création (depuis un modèle) ou modification d'un poste : nom, droits
/// cochés, groupés par domaine.
class EcranEditionPoste extends ConsumerStatefulWidget {
  const EcranEditionPoste({super.key, required this.etablissementId, this.poste, this.modele});

  final String etablissementId;
  final Poste? poste;
  final ModelePoste? modele;

  @override
  ConsumerState<EcranEditionPoste> createState() => _EcranEditionPosteState();
}

class _EcranEditionPosteState extends ConsumerState<EcranEditionPoste> {
  late final TextEditingController _nom;
  late final Set<String> _codes;
  String? _erreur;
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    _nom = TextEditingController(text: widget.poste?.nom ?? widget.modele?.nom ?? '');
    _codes = {...?widget.poste?.codes, ...?widget.modele?.codes};
  }

  @override
  void dispose() {
    _nom.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    final repo = ref.read(postesRepositoryProvider);
    try {
      if (widget.poste == null) {
        await repo.creerPoste(
          etablissementId: widget.etablissementId,
          modele: widget.modele?.code,
          nom: _nom.text.trim(),
          codes: _codes.toList(),
        );
      } else {
        await repo.modifierPoste(posteId: widget.poste!.id, nom: _nom.text.trim(), codes: _codes.toList());
      }
      if (mounted) Navigator.of(context).pop();
    } on ErreurPostes catch (e) {
      setState(() => _erreur = e.message);
    } catch (_) {
      setState(() => _erreur = 'Pas de connexion. Réessayez.');
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogue = ref.watch(catalogueDroitsProvider).valueOrNull ?? const [];
    final parDomaine = <String, List<DroitCatalogue>>{};
    for (final d in catalogue) {
      parDomaine.putIfAbsent(d.domaine, () => []).add(d);
    }
    final sensibles = catalogue.where((d) => d.sensible && _codes.contains(d.code)).length;
    final cumul = _codes.contains('scolarite.encaissement.gerer') &&
        (_codes.contains('comptabilite.ecrire') || _codes.contains('comptabilite.valider'));
    return Scaffold(
      appBar: AppBar(title: Text(widget.poste == null ? 'Nouveau poste' : 'Modifier le poste')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('champ_nom_poste'),
            controller: _nom,
            decoration: const InputDecoration(labelText: 'Nom du poste'),
          ),
          if (widget.modele != null || widget.poste?.description != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(widget.modele?.description ?? widget.poste!.description!),
            ),
          if (cumul)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Séparation des tâches : un même poste ne peut pas encaisser et tenir ou valider la comptabilité.',
                key: const Key('avertissement_cumul'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (catalogue.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '${_codes.length} droit${_codes.length > 1 ? 's' : ''} sur ${catalogue.length}'
              '${sensibles == 0 ? '' : ', dont $sensibles sensible${sensibles > 1 ? 's' : ''}'}',
              key: const Key('resume_droits_poste'),
            ),
          ],
          for (final entree in parDomaine.entries) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${libelleDomaine(entree.key)} '
                    '(${entree.value.where((d) => _codes.contains(d.code)).length}/${entree.value.length})',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                TextButton(
                  key: Key('tout_domaine_${entree.key}'),
                  onPressed: () => setState(() {
                    final tous = entree.value.every((d) => _codes.contains(d.code));
                    for (final d in entree.value) {
                      tous ? _codes.remove(d.code) : _codes.add(d.code);
                    }
                  }),
                  child: Text(entree.value.every((d) => _codes.contains(d.code)) ? 'Tout retirer' : 'Tout cocher'),
                ),
              ],
            ),
            for (final d in entree.value)
              CheckboxListTile(
                key: Key('droit_${d.code}'),
                value: _codes.contains(d.code),
                title: Row(
                  children: [
                    Flexible(child: Text(d.libelle)),
                    if (d.sensible) ...[
                      const SizedBox(width: 6),
                      Tooltip(
                        message: 'Droit sensible : argent, comptes ou résultats. À confier avec soin.',
                        child: Icon(Icons.shield_outlined, size: 16, color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                  ],
                ),
                subtitle: d.description == null ? null : Text(d.description!),
                onChanged: (v) => setState(() => v == true ? _codes.add(d.code) : _codes.remove(d.code)),
              ),
          ],
          if (_erreur != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_erreur!, key: const Key('erreur_poste'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('bouton_enregistrer_poste'),
            onPressed: _enCours || cumul ? null : _enregistrer,
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}

/// Direction › Personnel : chaque membre, son rôle et son poste.
class EcranPersonnel extends ConsumerWidget {
  const EcranPersonnel({super.key, required this.etablissementId});

  final String etablissementId;

  static String libelleRole(String role) => switch (role) {
    'direction' => 'Direction',
    'fondateur_reseau' => 'Fondateur du réseau',
    'enseignant' => 'Enseignant',
    'personnel' => 'Personnel',
    'vendeur' => 'Vendeur',
    _ => role,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membres = ref.watch(personnelEtablissementProvider(etablissementId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Personnel'),
        actions: [
          TextButton.icon(
            key: const Key('bouton_ouvrir_postes'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EcranPostes(etablissementId: etablissementId)),
            ),
            icon: const Icon(Icons.badge_outlined),
            label: const Text('Postes'),
          ),
        ],
      ),
      body: membres.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e is ErreurPostes ? e.message : 'Pas de connexion.')),
        data: (liste) => ListView.separated(
          itemCount: liste.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final m = liste[i];
            return ListTile(
              key: Key('membre_${m.profileId}'),
              leading: const Icon(Icons.person_outline),
              title: Text(m.nomComplet),
              subtitle: Text([libelleRole(m.role), if (m.poste != null) m.poste!].join(' · ')),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => _DialogueMembre(etablissementId: etablissementId, membre: m),
                );
                if (ok == true) ref.invalidate(personnelEtablissementProvider(etablissementId));
              },
            );
          },
        ),
      ),
    );
  }
}

class _DialogueMembre extends ConsumerStatefulWidget {
  const _DialogueMembre({required this.etablissementId, required this.membre});

  final String etablissementId;
  final MembrePersonnel membre;

  @override
  ConsumerState<_DialogueMembre> createState() => _DialogueMembreState();
}

class _DialogueMembreState extends ConsumerState<_DialogueMembre> {
  late String _role = ['direction', 'enseignant', 'personnel'].contains(widget.membre.role) ? widget.membre.role : 'personnel';
  late String? _poste = widget.membre.posteId;
  String? _erreur;

  @override
  Widget build(BuildContext context) {
    final postes = ref.watch(postesEtablissementProvider(widget.etablissementId)).valueOrNull ?? const [];
    return AlertDialog(
      title: Text(widget.membre.nomComplet),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            key: const Key('choix_role_membre'),
            isExpanded: true,
            initialValue: _role,
            decoration: const InputDecoration(labelText: 'Rôle'),
            items: const [
              DropdownMenuItem(value: 'personnel', child: Text('Personnel', overflow: TextOverflow.ellipsis)),
              DropdownMenuItem(value: 'enseignant', child: Text('Enseignant', overflow: TextOverflow.ellipsis)),
              DropdownMenuItem(value: 'direction', child: Text('Direction (tous les droits)', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _role = v ?? _role),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            key: const Key('choix_poste_membre'),
            isExpanded: true,
            initialValue: postes.any((p) => p.id == _poste) ? _poste : null,
            decoration: InputDecoration(labelText: _role == 'personnel' ? 'Poste (obligatoire)' : 'Poste'),
            items: [
              if (_role != 'personnel') const DropdownMenuItem<String?>(value: null, child: Text('Aucun')),
              for (final p in postes.where((p) => p.actif))
                DropdownMenuItem<String?>(value: p.id, child: Text(p.nom, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _poste = v),
          ),
          if (_erreur != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_erreur!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
        FilledButton(
          key: const Key('bouton_enregistrer_membre'),
          onPressed: () async {
            try {
              await ref.read(postesRepositoryProvider).modifierMembre(
                    etablissementId: widget.etablissementId,
                    compteId: widget.membre.profileId,
                    role: _role,
                    posteId: _poste,
                  );
              if (context.mounted) Navigator.of(context).pop(true);
            } on ErreurPostes catch (e) {
              setState(() => _erreur = e.message);
            }
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
