import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/espace_providers.dart';
import '../application/cahier_liaison_providers.dart';
import '../domain/cahier_liaison.dart';
import 'ecran_cahier_liaison.dart';

/// Cahier de liaison : choix de l'élève. Parent : ses enfants. Personnel :
/// les élèves de l'école sur lesquels il peut écrire (sa classe ; toute
/// l'école pour la direction).
class EcranElevesLiaison extends ConsumerWidget {
  const EcranElevesLiaison({super.key, this.etablissementId, this.direction = false});

  /// Null : parent. Sinon : personnel de cette école.
  final String? etablissementId;
  final bool direction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eleves = ref.watch(elevesLiaisonProvider(etablissementId));
    final parent = etablissementId == null;
    // Parent : seulement ses enfants de l'école de l'espace choisi (REG-32).
    final ecole = parent ? ref.watch(ecoleEspaceParentProvider) : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Cahier de liaison')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(elevesLiaisonProvider(etablissementId)),
        child: eleves
            .whenData((tous) => [
                  for (final e in tous)
                    if (ecole == null || e.etablissementId == null || e.etablissementId == ecole) e,
                ])
            .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(padding: const EdgeInsets.all(24), children: [
            Text(e is ErreurCahier ? e.message : 'Cahier indisponible. Tirez pour réessayer.', textAlign: TextAlign.center),
          ]),
          data: (liste) => liste.isEmpty
              ? ListView(padding: const EdgeInsets.all(24), children: [
                  Text(
                    parent
                        ? 'Liez la fiche de votre enfant pour échanger avec son école.'
                        : 'Aucun élève dans vos classes pour l’année en cours.',
                    textAlign: TextAlign.center,
                  ),
                ])
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    for (final e in liste)
                      ListTile(
                        key: ValueKey('eleve_liaison_${e.ficheEleveId}'),
                        leading: const Icon(Icons.menu_book_outlined),
                        title: Text(e.nom),
                        subtitle: e.classe == null ? null : Text(e.classe!),
                        trailing: e.aLire > 0
                            ? Badge(
                                label: Text('${e.aLire}'),
                                child: const Icon(Icons.chevron_right),
                              )
                            : const Icon(Icons.chevron_right),
                        onTap: () async {
                          await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => EcranCahierLiaison(
                              ficheEleveId: e.ficheEleveId,
                              nomEleve: e.nom,
                              personnel: !parent,
                              direction: direction,
                            ),
                          ));
                          ref.invalidate(elevesLiaisonProvider(etablissementId));
                        },
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
