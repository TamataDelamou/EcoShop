import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/planification_providers.dart';
import '../domain/salle.dart';
import 'ecran_emploi_du_temps.dart';

/// Salles de l'établissement (M11) — point d'entrée vers l'occupation
/// hebdomadaire de chacune (détection visuelle de conflits de réservation).
class EcranSalles extends ConsumerWidget {
  const EcranSalles({super.key, required this.etablissementId, required this.anneeId});

  final String etablissementId;
  final String anneeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salles = ref.watch(sallesEtablissementProvider(etablissementId));

    return Scaffold(
      appBar: AppBar(title: const Text('Salles')),
      body: salles.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: List.generate(4, (_) => const ShimmerCarteListe()),
        ),
        error: (erreur, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Salles indisponibles hors connexion pour le moment.'),
          ),
        ),
        data: (liste) => liste.isEmpty
            ? const Center(child: Text('Aucune salle enregistrée.'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: liste.length,
                itemBuilder: (context, i) => EntreeAnimee(index: i, enfant: _CarteSalle(salle: liste[i], anneeId: anneeId)),
              ),
      ),
    );
  }
}

class _CarteSalle extends StatelessWidget {
  const _CarteSalle({required this.salle, required this.anneeId});

  final Salle salle;
  final String anneeId;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(
          salle.actif ? Icons.meeting_room_outlined : Icons.block_outlined,
          color: salle.actif ? AppColors.bleuElectrique : AppColors.encreSecondaire,
        ),
        title: Text(salle.libelle),
        subtitle: salle.capacite != null ? Text('${salle.capacite} places') : null,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EcranEmploiSalle(salleId: salle.id, anneeId: anneeId, titre: salle.libelle),
          ),
        ),
      ),
    );
  }
}
