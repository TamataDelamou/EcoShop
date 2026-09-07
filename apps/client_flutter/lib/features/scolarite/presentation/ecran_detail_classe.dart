import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/shimmer.dart';
import '../../notes/presentation/ecran_evaluations_classe.dart';
import '../../vie_scolaire/presentation/ecran_appel_classe.dart';
import '../application/scolarite_providers.dart';
import '../domain/affectation_enseignant.dart';
import '../domain/classe.dart';
import '../domain/inscription.dart';

/// Détail d'une classe : élèves inscrits et enseignants affectés (M5).
///
/// Visible par le personnel, et par tout élève/parent ayant un enfant inscrit
/// (`classe_visible`, contrat M05 §4) — l'écran ne présuppose donc pas un rôle.
class EcranDetailClasse extends StatelessWidget {
  const EcranDetailClasse({super.key, required this.classe});

  final Classe classe;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(classe.nom),
          actions: [
            IconButton(
              icon: const Icon(Icons.fact_check_outlined),
              tooltip: 'Appel',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => EcranAppelClasse(classe: classe)),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.assignment_outlined),
              tooltip: 'Évaluations',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => EcranEvaluationsClasse(classe: classe)),
              ),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Élèves', icon: Icon(Icons.groups_outlined)),
              Tab(text: 'Enseignants', icon: Icon(Icons.person_outline)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _OngletEleves(classeId: classe.id),
            _OngletEnseignants(classeId: classe.id),
          ],
        ),
      ),
    );
  }
}

class _OngletEleves extends ConsumerWidget {
  const _OngletEleves({required this.classeId});

  final String classeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inscriptions = ref.watch(inscriptionsDeClasseProvider(classeId));

    return inscriptions.when(
      loading: () => ListView(
        padding: const EdgeInsets.all(16),
        children: List.generate(5, (_) => const ShimmerCarteListe()),
      ),
      error: (erreur, _) => const _EtatErreur(
        message: "Impossible d'afficher les élèves de cette classe.",
      ),
      data: (liste) => liste.isEmpty
          ? const _EtatVide(message: 'Aucun élève inscrit pour le moment.')
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: liste.length,
              itemBuilder: (context, i) => EntreeAnimee(
                index: i,
                enfant: _CarteEleve(inscription: liste[i]),
              ),
            ),
    );
  }
}

class _CarteEleve extends StatelessWidget {
  const _CarteEleve({required this.inscription});

  final Inscription inscription;

  @override
  Widget build(BuildContext context) {
    final fiche = inscription.fiche;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.bleuElectrique.withValues(alpha: 0.12),
          child: Text(
            (fiche?.prenom.isNotEmpty ?? false) ? fiche!.prenom[0].toUpperCase() : '?',
            style: const TextStyle(color: AppColors.bleuElectrique, fontWeight: FontWeight.w700),
          ),
        ),
        title: Text(fiche?.nomComplet ?? 'Élève'),
        subtitle: Text('Matricule ${fiche?.matricule ?? '—'}'),
        trailing: _pastilleStatut(inscription.statut.code),
      ),
    );
  }

  Widget _pastilleStatut(String code) {
    final (couleur, libelle) = switch (code) {
      'active' => (AppColors.vertMenthe, 'Active'),
      'redoublante' => (AppColors.orangePop, 'Redouble'),
      'en_attente' => (AppColors.dore, 'En attente'),
      _ => (AppColors.encreSecondaire, 'Retirée'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(libelle, style: TextStyle(color: couleur, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _OngletEnseignants extends ConsumerWidget {
  const _OngletEnseignants({required this.classeId});

  final String classeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final affectations = ref.watch(affectationsDeClasseProvider(classeId));

    return affectations.when(
      loading: () => ListView(
        padding: const EdgeInsets.all(16),
        children: List.generate(4, (_) => const ShimmerCarteListe()),
      ),
      error: (erreur, _) => const _EtatErreur(
        message: 'Impossible d\'afficher les enseignants de cette classe.',
      ),
      data: (liste) => liste.isEmpty
          ? const _EtatVide(message: 'Aucun enseignant affecté pour le moment.')
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: liste.length,
              itemBuilder: (context, i) => EntreeAnimee(
                index: i,
                enfant: _CarteAffectation(affectation: liste[i]),
              ),
            ),
    );
  }
}

class _CarteAffectation extends StatelessWidget {
  const _CarteAffectation({required this.affectation});

  final AffectationEnseignant affectation;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: AppColors.bordure,
          child: Icon(Icons.person, color: AppColors.encreSecondaire),
        ),
        title: Text(affectation.nomEnseignant ?? 'Enseignant'),
        subtitle: Text(affectation.nomMatiere ?? 'Matière non précisée'),
        trailing: affectation.volumeHoraireHebdo != null
            ? Text('${affectation.volumeHoraireHebdo} h/sem.',
                style: const TextStyle(color: AppColors.encreSecondaire, fontSize: 12))
            : null,
      ),
    );
  }
}

class _EtatVide extends StatelessWidget {
  const _EtatVide({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

class _EtatErreur extends StatelessWidget {
  const _EtatErreur({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 40, color: AppColors.encreSecondaire),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
