import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/scolarite_providers.dart';
import '../../notes/presentation/ecran_carnet_notes.dart';
import '../../vie_scolaire/presentation/ecran_suivi_vie_scolaire.dart';
import '../domain/fiche_eleve.dart';
import '../domain/inscription.dart';
import 'ecran_detail_classe.dart';

/// Détail d'une fiche élève : état civil et historique de classes (M5).
class EcranFicheEleve extends ConsumerWidget {
  const EcranFicheEleve({super.key, required this.fiche});

  final FicheEleve fiche;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historique = ref.watch(inscriptionsDeFicheProvider(fiche.id));

    return Scaffold(
      appBar: AppBar(title: Text(fiche.nomComplet)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: context.palette.primaire.withValues(alpha: 0.12),
                        child: Text(
                          fiche.prenom.isNotEmpty ? fiche.prenom[0].toUpperCase() : '?',
                          style: TextStyle(
                            color: context.palette.primaire,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(fiche.nomComplet,
                                style: Theme.of(context).textTheme.titleMedium),
                            Text('Matricule ${fiche.matricule}',
                                style: TextStyle(color: context.palette.encreSecondaire)),
                          ],
                        ),
                      ),
                      if (!fiche.estActive)
                        Icon(Icons.pause_circle_outline, color: context.palette.encreSecondaire),
                    ],
                  ),
                  const Divider(height: 28),
                  _LigneInfo(libelle: 'Date de naissance', valeur: _formatDate(fiche.dateNaissance)),
                  if (fiche.lieuNaissance != null)
                    _LigneInfo(libelle: 'Lieu de naissance', valeur: fiche.lieuNaissance!),
                  if (fiche.sexe != null)
                    _LigneInfo(libelle: 'Sexe', valeur: fiche.sexe == 'M' ? 'Masculin' : 'Féminin'),
                  if (fiche.nationalite != null)
                    _LigneInfo(libelle: 'Nationalité', valeur: fiche.nationalite!),
                  if (fiche.estSupervise)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: _BadgeSupervision(),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => EcranCarnetNotes(fiche: fiche)),
                  ),
                  icon: const Icon(Icons.grade_outlined),
                  label: const Text('Notes & bulletins'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => EcranSuiviVieScolaire(fiche: fiche)),
                  ),
                  icon: const Icon(Icons.event_available_outlined),
                  label: const Text('Vie scolaire'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Historique de classes', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          historique.when(
            loading: () => const ShimmerCarteListe(),
            error: (erreur, _) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text("Historique indisponible hors connexion pour l'instant."),
            ),
            data: (liste) => liste.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Aucune inscription enregistrée.'),
                  )
                : Column(children: [for (final i in liste) _CarteInscription(inscription: i)]),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _LigneInfo extends StatelessWidget {
  const _LigneInfo({required this.libelle, required this.valeur});

  final String libelle;
  final String valeur;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(libelle, style: TextStyle(color: context.palette.encreSecondaire)),
          ),
          Expanded(child: Text(valeur, style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

class _BadgeSupervision extends StatelessWidget {
  const _BadgeSupervision();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: context.palette.premium.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_outlined, size: 14, color: context.palette.premium),
          const SizedBox(width: 4),
          Text('Compte supervisé',
              style: TextStyle(color: context.palette.premium, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _CarteInscription extends StatelessWidget {
  const _CarteInscription({required this.inscription});

  final Inscription inscription;

  @override
  Widget build(BuildContext context) {
    final classe = inscription.classe;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(Icons.class_outlined, color: context.palette.primaire),
        title: Text(classe?.nom ?? 'Classe inconnue'),
        subtitle: Text('Inscrit le ${EcranFicheEleve._formatDate(inscription.dateInscription)}'),
        trailing: classe == null
            ? null
            : IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => EcranDetailClasse(classe: classe)),
                ),
              ),
      ),
    );
  }
}
