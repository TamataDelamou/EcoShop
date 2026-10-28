import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../etablissement/domain/etablissement.dart';
import '../../referentiel/application/referentiel_providers.dart';
import '../../referentiel/domain/pays_pedagogique.dart';
import '../../referentiel/presentation/ecran_arborescence_pays.dart';
import '../../referentiel/presentation/ecran_pays_pedagogiques.dart';
import 'elements_configuration.dart';

/// Programme officiel du pays de l'établissement (REG-23) : cycles,
/// niveaux, matières, coefficients et volumes horaires — ouvert
/// directement sur le pays de l'école, sans passer par la liste des pays.
class EcranProgrammeEtablissement extends ConsumerWidget {
  const EcranProgrammeEtablissement({super.key, required this.etablissement});

  final Etablissement etablissement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = etablissement.paysCode;
    if (code == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Programme officiel')),
        body: EtatVide(
          icone: Icons.public_off_outlined,
          titre: 'Pays de l’établissement non renseigné',
          texte: 'Demandez à GSG de compléter la fiche de l’école. En attendant, consultez les programmes de tous les pays.',
          action: FilledButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EcranPaysPedagogiques())),
            child: const Text('Tous les programmes'),
          ),
        ),
      );
    }
    final pays = ref.watch(paysPedagogiquesProvider);
    return pays.when(
      loading: () => Scaffold(appBar: AppBar(title: const Text('Programme officiel')), body: const Center(child: CircularProgressIndicator())),
      error: (_, _) => Scaffold(
        appBar: AppBar(title: const Text('Programme officiel')),
        body: ErreurChargement(onReessayer: () => ref.invalidate(paysPedagogiquesProvider)),
      ),
      data: (liste) {
        final p = liste.cast<PaysPedagogique?>().firstWhere((x) => x!.codeIso == code, orElse: () => null);
        if (p == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Programme officiel')),
            body: const EtatVide(
              icone: Icons.hourglass_empty,
              titre: 'Programme pas encore publié',
              texte: 'Le programme officiel de ce pays est en préparation par GSG.',
            ),
          );
        }
        return EcranArborescencePays(pays: p);
      },
    );
  }
}
