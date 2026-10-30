import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_providers.dart';
import '../../../core/widgets/choisir_date.dart';
import '../data/parametres_gsg_repository.dart';
import '../domain/parametre_global.dart';

final parametresGsgRepositoryProvider = Provider<ParametresGsgRepository>((ref) {
  return ParametresGsgRepository(
    ref.watch(supabaseClientProvider),
    LectureHorsLigne(
      CacheDocumentStore(ref.watch(databaseProvider), 'parametres_gsg_hl'),
      ref.watch(fraicheurHorsLigneProvider),
    ),
  );
});

final parametresGsgProvider = FutureProvider.autoDispose<List<ParametreGlobal>>(
  (ref) => ref.watch(parametresGsgRepositoryProvider).lister(),
);

final historiqueParametreProvider = FutureProvider.autoDispose.family<List<ChangementParametre>, String>(
  (ref, cle) => ref.watch(parametresGsgRepositoryProvider).historique(cle),
);

/// Administration GSG (REG-36) : régler les paramètres de la plateforme
/// (tarifs Premium, quotas IA, seuils) sans passer par la base. Chaque
/// changement est historisé ; le type d'une valeur ne change jamais.
class EcranParametresGsg extends ConsumerStatefulWidget {
  const EcranParametresGsg({super.key});

  @override
  ConsumerState<EcranParametresGsg> createState() => _EcranParametresGsgState();
}

class _EcranParametresGsgState extends ConsumerState<EcranParametresGsg> {
  String _filtre = '';

  @override
  Widget build(BuildContext context) {
    final liste = ref.watch(parametresGsgProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres de la plateforme')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(parametresGsgProvider),
        child: liste.when(
          data: (parametres) {
            final f = _filtre.toLowerCase();
            final visibles = [
              for (final p in parametres)
                if (f.isEmpty || p.cle.contains(f) || p.libelle.toLowerCase().contains(f)) p,
            ];
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                const Text('Ces réglages valent pour toutes les écoles. Chaque changement est gardé dans l’historique.'),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('parametres_filtre'),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Chercher (tarif, IA, seuil…)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _filtre = v.trim()),
                ),
                const SizedBox(height: 8),
                if (visibles.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Aucun paramètre.')),
                for (final p in visibles)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      key: ValueKey('parametre_${p.cle}'),
                      title: Text(p.libelle),
                      subtitle: Text([p.apercu, if (p.description != null && p.description!.isNotEmpty) p.description!]
                          .join('\n')),
                      isThreeLine: p.description != null && p.description!.isNotEmpty,
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => EcranModifierParametre(parametre: p)),
                      ),
                    ),
                  ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(children: const [
            Padding(padding: EdgeInsets.all(16), child: Text('Paramètres indisponibles pour le moment. Tirez pour réessayer.')),
          ]),
        ),
      ),
    );
  }
}

/// Modifier un paramètre : champ simple (nombre, texte, oui/non) ou JSON.
class EcranModifierParametre extends ConsumerStatefulWidget {
  const EcranModifierParametre({super.key, required this.parametre});

  final ParametreGlobal parametre;

  @override
  ConsumerState<EcranModifierParametre> createState() => _EcranModifierParametreState();
}

class _EcranModifierParametreState extends ConsumerState<EcranModifierParametre> {
  late final ParametreGlobal _p = widget.parametre;
  late final TextEditingController _texte = TextEditingController(
    text: _p.estSimple
        ? (_p.valeurSimple is bool ? '' : '${_p.valeurSimple}')
        : const JsonEncoder.withIndent('  ').convert(_p.valeur),
  );
  late bool _oui = _p.valeurSimple == true;
  bool _envoi = false;
  String? _erreur;

  @override
  void dispose() {
    _texte.dispose();
    super.dispose();
  }

  Object? _nouvelle() {
    if (_p.estSimple) return _p.valeurDepuisSaisie(_p.valeurSimple is bool ? _oui : _texte.text);
    return _p.jsonDeMemeForme(_texte.text);
  }

  Future<void> _enregistrer() async {
    final valeur = _nouvelle();
    if (valeur == null) {
      setState(() => _erreur = _p.estSimple && _p.valeurSimple is num
          ? 'Saisissez un nombre.'
          : const ErreurParametre('VALEUR_INVALIDE').message);
      return;
    }
    if (jsonEncode(valeur) == jsonEncode(_p.valeur)) {
      Navigator.of(context).pop();
      return;
    }
    final confirme = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Appliquer à toute la plateforme ?'),
        content: Text('${_p.libelle}\nAvant : ${_p.apercu}\nAprès : ${ParametreGlobal(cle: _p.cle, valeur: valeur).apercu}'),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Annuler')),
          FilledButton(
            key: const Key('parametre_confirmer'),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Appliquer'),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    try {
      await ref.read(parametresGsgRepositoryProvider).definir(_p.cle, valeur);
      ref
        ..invalidate(parametresGsgProvider)
        ..invalidate(historiqueParametreProvider(_p.cle));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Paramètre enregistré.')));
      Navigator.of(context).pop();
    } on ErreurParametre catch (e) {
      if (mounted) setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final historique = ref.watch(historiqueParametreProvider(_p.cle));
    final schema = Theme.of(context).colorScheme;
    final v = _p.valeurSimple;
    return Scaffold(
      appBar: AppBar(title: Text(_p.libelle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          SelectableText(_p.cle, style: TextStyle(color: schema.onSurfaceVariant, fontSize: 12)),
          if (_p.description != null && _p.description!.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text(_p.description!)),
          const SizedBox(height: 16),
          if (_p.estSimple && v is bool)
            SwitchListTile(
              key: const Key('parametre_oui_non'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Activé'),
              value: _oui,
              onChanged: (x) => setState(() => _oui = x),
            )
          else
            TextField(
              key: const Key('parametre_valeur'),
              controller: _texte,
              keyboardType: _p.estSimple && v is num
                  ? const TextInputType.numberWithOptions(decimal: true, signed: true)
                  : TextInputType.multiline,
              maxLines: _p.estSimple ? 1 : 12,
              style: _p.estSimple ? null : const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                labelText: _p.estSimple ? 'Valeur' : 'Valeur (JSON)',
                border: const OutlineInputBorder(),
              ),
            ),
          if (_erreur != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_erreur!, key: const Key('parametre_erreur'), style: TextStyle(color: schema.error)),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('parametre_enregistrer'),
            onPressed: _envoi ? null : _enregistrer,
            icon: const Icon(Icons.save_outlined),
            label: Text(_envoi ? 'Enregistrement…' : 'Enregistrer'),
          ),
          const SizedBox(height: 24),
          Text('Historique', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          historique.when(
            data: (liste) => liste.isEmpty
                ? const Text('Aucun changement depuis l’application.')
                : Column(children: [
                    for (final h in liste)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(ParametreGlobal(cle: _p.cle, valeur: h.nouvelle).apercu),
                        subtitle: Text('Le ${formaterDate(h.le.toLocal())}'
                            '${h.ancienne == null ? '' : ' — avant : ${ParametreGlobal(cle: _p.cle, valeur: h.ancienne!).apercu}'}'),
                      ),
                  ]),
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const Text('Historique visible en ligne seulement.'),
          ),
        ],
      ),
    );
  }
}
