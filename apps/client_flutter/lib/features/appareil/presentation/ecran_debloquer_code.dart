import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/securite/gardien_actions_sensibles.dart';
import '../application/appareil_providers.dart';
import '../domain/etat_appareil.dart';
import 'ecran_code_compte.dart';

/// « Débloquer le code d'une personne » (REG-22, voie c).
///
/// Direction ([etablissementId] donné) : personnel, enseignants, élèves et
/// parents de l'école, la personne étant présente. Administrateur GSG
/// ([etablissementId] nul) : un compte retrouvé par son adresse ou son
/// identifiant EcoShop — direction et fondateurs, après vérification de leur
/// identité. La personne a ensuite 30 minutes pour choisir un nouveau code
/// sur son téléphone.
class EcranDebloquerCode extends ConsumerStatefulWidget {
  const EcranDebloquerCode({super.key, this.etablissementId});

  final String? etablissementId;

  bool get parGsg => etablissementId == null;

  @override
  ConsumerState<EcranDebloquerCode> createState() => _EcranDebloquerCodeState();
}

class _EcranDebloquerCodeState extends ConsumerState<EcranDebloquerCode> {
  final _recherche = TextEditingController();
  Timer? _attente;
  Future<List<PersonneDebloquable>>? _resultats;

  @override
  void initState() {
    super.initState();
    if (!widget.parGsg) _chercher();
  }

  @override
  void dispose() {
    _attente?.cancel();
    _recherche.dispose();
    super.dispose();
  }

  void _chercher() {
    final repo = ref.read(appareilRepositoryProvider);
    final texte = _recherche.text.trim();
    setState(() {
      _resultats = widget.parGsg
          ? repo.chercherCompteGsg(texte)
          : repo.personnesDebloquables(widget.etablissementId!, texte);
    });
  }

  Future<void> _debloquer(PersonneDebloquable p) async {
    final motif = await showDialog<String>(context: context, builder: (_) => _DialogueMotif(personne: p));
    if (motif == null || !mounted) return;
    final messager = ScaffoldMessenger.of(context);
    try {
      final echeance = await avecCode(
        'Débloquer le code de ${p.nomComplet}',
        () => ref.read(appareilRepositoryProvider).debloquer(
              compteId: p.profileId,
              motif: motif,
              etablissementId: widget.etablissementId,
            ),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          icon: const Icon(Icons.lock_open_outlined),
          title: const Text('Code débloqué'),
          content: Text(
            '${p.nomComplet} a jusqu’à ${heure(echeance)} pour choisir un nouveau code sur son téléphone : '
            '« Code oublié ? › Me présenter à l’école › J’ai été débloqué(e) ». L’action est inscrite au journal.',
          ),
          actions: [FilledButton(onPressed: () => Navigator.of(d).pop(), child: const Text('Compris'))],
        ),
      );
      _chercher();
    } on ActionSensibleAnnulee {
      // Rien.
    } catch (e) {
      messager.showSnackBar(SnackBar(content: Text(messageErreur(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.parGsg ? 'Débloquer un code (direction)' : 'Débloquer le code d’une personne')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.parGsg
                    ? 'Pour un membre de la direction ou un fondateur, après vérification de son identité. '
                        'Saisissez son adresse e-mail ou son identifiant EcoShop exacts.'
                    : 'La personne doit être présente. Vérifiez son identité avant de débloquer.'),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('champ_recherche_deblocage'),
                  controller: _recherche,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    labelText: widget.parGsg ? 'Adresse e-mail ou identifiant EcoShop' : 'Rechercher une personne',
                  ),
                  onSubmitted: (_) => _chercher(),
                  onChanged: widget.parGsg
                      ? null
                      : (_) {
                          _attente?.cancel();
                          _attente = Timer(const Duration(milliseconds: 400), _chercher);
                        },
                ),
                if (widget.parGsg)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(onPressed: _chercher, child: const Text('Chercher')),
                  ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<PersonneDebloquable>>(
              future: _resultats,
              builder: (context, s) {
                if (_resultats == null) return const SizedBox.shrink();
                if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                if (s.hasError) return Center(child: Text(messageErreur(s.error!)));
                final liste = s.data ?? const [];
                if (liste.isEmpty) return const Center(child: Text('Personne à afficher.'));
                return ListView.separated(
                  itemCount: liste.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final p = liste[i];
                    return ListTile(
                      key: Key('personne_${p.profileId}'),
                      leading: Icon(p.bloque ? Icons.block : Icons.person_outline),
                      title: Text(p.nomComplet),
                      subtitle: Text([
                        if (p.courriel != null) p.courriel!,
                        p.qualite,
                        if (!p.aUnCode) 'pas encore de code' else if (p.bloque) 'nouveaux appareils bloqués',
                      ].join(' · ')),
                      trailing: p.aUnCode
                          ? FilledButton.tonal(onPressed: () => _debloquer(p), child: const Text('Débloquer'))
                          : null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogueMotif extends StatefulWidget {
  const _DialogueMotif({required this.personne});

  final PersonneDebloquable personne;

  @override
  State<_DialogueMotif> createState() => _DialogueMotifState();
}

class _DialogueMotifState extends State<_DialogueMotif> {
  final _motif = TextEditingController();

  @override
  void dispose() {
    _motif.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valide = _motif.text.trim().length >= 5;
    return AlertDialog(
      title: Text('Débloquer ${widget.personne.nomComplet}'),
      content: TextField(
        key: const Key('champ_motif_deblocage'),
        controller: _motif,
        autofocus: true,
        maxLines: 2,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'Motif (obligatoire)',
          hintText: 'Ex. : téléphone perdu, présente au bureau, carte vérifiée',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          key: const Key('bouton_confirmer_deblocage'),
          onPressed: valide ? () => Navigator.of(context).pop(_motif.text.trim()) : null,
          child: const Text('Débloquer'),
        ),
      ],
    );
  }
}
