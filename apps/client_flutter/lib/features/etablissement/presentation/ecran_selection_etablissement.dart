import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../auth/application/connexion_controller.dart';
import '../../auth/domain/auth_repository.dart';
import '../domain/etablissement.dart';

/// Sélection de l'établissement actif (cahier v4.1, ch. 4).
///
/// Un enseignant peut être rattaché à plusieurs établissements ; toutes les
/// données affichées ensuite sont cadrées par ce choix. La sélection est
/// enregistrée côté serveur (RPC `definir_etablissement_actif`), qui refuse
/// tout établissement dont le compte n'est pas membre.
class EcranSelectionEtablissement extends ConsumerStatefulWidget {
  const EcranSelectionEtablissement({super.key});

  @override
  ConsumerState<EcranSelectionEtablissement> createState() =>
      _EcranSelectionEtablissementState();
}

class _EcranSelectionEtablissementState
    extends ConsumerState<EcranSelectionEtablissement> {
  String? _enCoursId;
  String? _codeErreur;

  Future<void> _selectionner(Etablissement etablissement) async {
    setState(() {
      _enCoursId = etablissement.id;
      _codeErreur = null;
    });

    try {
      await ref
          .read(authRepositoryProvider)
          .definirEtablissementActif(etablissement.id);
      if (!mounted) return;
      ref.rafraichirSession();
    } on ErreurAuth catch (e) {
      if (!mounted) return;
      setState(() => _codeErreur = e.code);
    } finally {
      if (mounted) setState(() => _enCoursId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final etablissements = ref.watch(mesEtablissementsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Choisir un établissement')),
      body: etablissements.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Text('Impossible de charger vos établissements.'),
        ),
        data: (liste) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_codeErreur != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  messageErreurAuth(_codeErreur!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            for (final etablissement in liste)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(_initiales(etablissement.nom)),
                  ),
                  title: Text(etablissement.nom),
                  subtitle: Text(etablissement.localisation),
                  trailing: _enCoursId == etablissement.id
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: _enCoursId != null
                      ? null
                      : () => _selectionner(etablissement),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _initiales(String nom) {
    final mots =
        nom.trim().split(RegExp(r'\s+')).where((m) => m.isNotEmpty).take(2);
    if (mots.isEmpty) return '?';
    return mots.map((m) => m.substring(0, 1)).join().toUpperCase();
  }
}
