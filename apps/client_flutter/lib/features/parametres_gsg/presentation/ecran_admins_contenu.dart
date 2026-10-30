import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/offline/lecture_hors_ligne.dart';

/// Administrateur de contenu pédagogique (cahier 4.4) : nom et adresse.
class AdminContenu {
  const AdminContenu({required this.id, required this.nom, this.courriel});

  final String id;
  final String nom;
  final String? courriel;

  factory AdminContenu.depuisJson(Map<String, dynamic> j) => AdminContenu(
        id: j['profile_id'] as String,
        nom: '${j['prenom'] ?? ''} ${j['nom'] ?? ''}'.trim(),
        courriel: j['courriel'] as String?,
      );
}

String messageAdminContenu(Object e) {
  if (estErreurReseau(e)) return 'Pas de réseau : cette action se fait en ligne.';
  final texte = e is PostgrestException ? e.message : '$e';
  if (texte.contains('COMPTE_INTROUVABLE')) {
    return 'Aucun compte avec cette adresse. La personne doit d’abord s’inscrire dans l’application.';
  }
  if (texte.contains('COMPTE_DEJA_UTILISE')) {
    return 'Ce compte sert déjà dans une école, comme parent ou élève : utilisez une adresse dédiée au contenu.';
  }
  if (texte.contains('PERMISSION_REFUSEE')) return 'Réservé à l’Administrateur GSG.';
  return 'Action impossible pour le moment. Réessayez.';
}

final adminsContenuProvider = FutureProvider.autoDispose<List<AdminContenu>>((ref) async {
  final lignes = await ref.watch(supabaseClientProvider).rpc<dynamic>('admins_contenu');
  return [for (final l in (lignes as List?) ?? const []) AdminContenu.depuisJson((l as Map).cast<String, dynamic>())];
});

/// Plateforme GSG : désigner ou retirer les Administrateurs de contenu
/// pédagogique (banque de questions, cahier 30.5). Le compte doit être
/// dédié : ni membre d'une école, ni parent, ni élève.
class EcranAdminsContenu extends ConsumerWidget {
  const EcranAdminsContenu({super.key});

  Future<void> _designer(BuildContext context, WidgetRef ref) async {
    final c = TextEditingController();
    final courriel = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Désigner un administrateur de contenu'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('La personne s’inscrit d’abord dans l’application avec une adresse dédiée, '
              'puis vous la désignez ici. À sa prochaine ouverture, elle verra la banque de questions.'),
          const SizedBox(height: 12),
          TextField(
            key: const Key('courriel_admin_contenu'),
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Adresse e-mail du compte', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(), child: const Text('Annuler')),
          FilledButton(
            key: const Key('confirmer_admin_contenu'),
            onPressed: () {
              if (c.text.trim().contains('@')) Navigator.of(d).pop(c.text.trim());
            },
            child: const Text('Désigner'),
          ),
        ],
      ),
    );
    if (courriel == null) return;
    try {
      await ref.read(supabaseClientProvider).rpc<dynamic>('designer_admin_contenu', params: {'p_courriel': courriel});
      ref.invalidate(adminsContenuProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$courriel est Administrateur de contenu.')));
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(messageAdminContenu(e))));
    }
  }

  Future<void> _retirer(BuildContext context, WidgetRef ref, AdminContenu a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Retirer ${a.nom.isEmpty ? a.courriel : a.nom} ?'),
        content: const Text('Le compte perd l’accès à la banque de questions ; ses questions restent.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Retirer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(supabaseClientProvider).rpc<dynamic>('retirer_admin_contenu', params: {'p_profile': a.id});
      ref.invalidate(adminsContenuProvider);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(messageAdminContenu(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liste = ref.watch(adminsContenuProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Administrateurs de contenu')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('designer_admin_contenu'),
        onPressed: () => _designer(context, ref),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Désigner'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(adminsContenuProvider),
        child: liste.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            Padding(padding: const EdgeInsets.all(16), child: Text(messageAdminContenu(e))),
          ]),
          data: (admins) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              const Text('Ils créent, valident et publient les questions de révision. Ils ne voient '
                  'aucune donnée des écoles ni des élèves.'),
              const SizedBox(height: 12),
              if (admins.isEmpty) const Text('Aucun pour le moment.', key: Key('admins_contenu_vide')),
              for (final a in admins)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.school_outlined),
                    title: Text(a.nom.isEmpty ? (a.courriel ?? '—') : a.nom),
                    subtitle: a.courriel == null ? null : Text(a.courriel!),
                    trailing: IconButton(
                      tooltip: 'Retirer',
                      onPressed: () => _retirer(context, ref, a),
                      icon: const Icon(Icons.person_remove_outlined),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
