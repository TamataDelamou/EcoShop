import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/accueil_providers.dart';
import '../domain/catalogue_fonctions.dart';
import '../domain/fonction.dart';
import 'pastille.dart';

/// Une ligne « À faire » : compteur du résumé serveur → fonction à ouvrir.
class LigneAFaire {
  const LigneAFaire(this.cle, this.fonctionId, this.texte, {this.icone = Icons.radio_button_unchecked});

  final String cle;
  final String fonctionId;
  final String Function(int n) texte;
  final IconData icone;
}

String _s(int n) => n > 1 ? 's' : '';

/// Ordre des maquettes : d'abord ce qui attend une décision.
final lignesAFaire = <LigneAFaire>[
  LigneAFaire('liaisons_a_valider', 'comptes_lies', (n) => '$n demande${_s(n)} de liaison à valider', icone: Icons.link),
  LigneAFaire('numeros_a_confirmer', 'numeros_a_confirmer', (n) => '$n numéro${_s(n)} à confirmer', icone: Icons.phone),
  LigneAFaire('familles_en_retard', 'relances', (n) => '$n famille${_s(n)} en retard de paiement',
      icone: Icons.payments_outlined),
  LigneAFaire('dossiers_inscription', 'inscriptions_en_ligne', (n) => '$n dossier${_s(n)} d’inscription à traiter',
      icone: Icons.how_to_reg_outlined),
  LigneAFaire('alertes_ouvertes', 'alertes_decrochage', (n) => '$n alerte${_s(n)} de décrochage',
      icone: Icons.warning_amber_outlined),
  LigneAFaire('appels_a_faire', 'faire_appel', (n) => n == 1 ? 'Un appel à faire aujourd’hui' : '$n appels à faire aujourd’hui',
      icone: Icons.fact_check_outlined),
  LigneAFaire('cahier_non_lu', 'cahier_liaison', (n) => '$n mot${_s(n)} du cahier à lire', icone: Icons.menu_book_outlined),
  LigneAFaire('notes_a_saisir', 'notes_enseignant', (n) => '$n évaluation${_s(n)} à compléter', icone: Icons.grade_outlined),
  LigneAFaire('tranches_a_payer', 'scolarite', (n) => 'Tranche de scolarité à payer', icone: Icons.payments_outlined),
  LigneAFaire('nouvelles_notes', 'notes_bulletins', (n) => n == 1 ? 'Nouvelle note' : '$n nouvelles notes',
      icone: Icons.grade_outlined),
  LigneAFaire('livres_a_rendre', 'bibliotheque_famille', (n) => '$n livre${_s(n)} à rendre à la bibliothèque',
      icone: Icons.local_library_outlined),
  LigneAFaire('annonces_non_lues', 'annonces', (n) => '$n annonce${_s(n)} à lire', icone: Icons.campaign_outlined),
];

/// Accueil en pastilles (REG-21) : « À faire », pastilles par thème.
class EcranAccueil extends ConsumerWidget {
  const EcranAccueil({super.key, this.catalogue});

  /// Catalogue des fonctions (surchargé en test).
  final List<Fonction>? catalogue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(contexteAccueilProvider);
    if (c == null) return const Center(child: CircularProgressIndicator());
    final resume = ref.watch(resumeAccueilProvider).valueOrNull ?? const {};
    final fonctions = fonctionsVisibles(c, catalogue: catalogue);
    final parId = {for (final f in fonctions) f.id: f};

    void ouvrir(Fonction f) => f.ouvrir(context, ref, c);

    final aFaire = [
      for (final l in lignesAFaire)
        if ((resume[l.cle] ?? 0) > 0 && parId.containsKey(l.fonctionId)) l,
    ];
    // Les annonces ont déjà leur badge ; elles ne viennent dans « À faire »
    // que s'il n'y a rien d'autre.
    final lignes = aFaire.length > 1 ? aFaire.where((l) => l.cle != 'annonces_non_lues').toList() : aFaire;

    Widget pastille(Fonction f) => Pastille(fonction: f, badge: f.badge == null ? 0 : resume[f.badge] ?? 0, onTap: () => ouvrir(f));

    final sections = <Widget>[];
    if (c.direction) {
      for (final g in groupesDirection) {
        final duGroupe = [for (final f in fonctions) if (f.groupe == g) f];
        if (duGroupe.isEmpty) continue;
        sections
          ..add(TitreSection(g))
          ..add(GrillePastilles(enfants: [for (final f in duGroupe) pastille(f)]));
      }
    } else if (fonctions.isNotEmpty) {
      sections
        ..add(TitreSection(c.personnel ? 'Mon travail' : 'Tout EcoShop'))
        ..add(GrillePastilles(enfants: [for (final f in fonctions) pastille(f)]));
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(resumeAccueilProvider);
        ref.invalidate(aujourdhuiProvider);
      },
      child: ListView(
        key: const Key('accueil_pastilles'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (c.eleve) const _ProchainCours(),
          if (c.enseignant) const _Aujourdhui(),
          if (lignes.isNotEmpty) ...[
            TitreSection(c.eleve ? 'À ne pas manquer' : 'À faire'),
            for (final l in lignes)
              _LigneAFaireWidget(
                ligne: l,
                n: resume[l.cle]!,
                onTap: () => ouvrir(parId[l.fonctionId]!),
              ),
          ],
          ...sections,
        ],
      ),
    );
  }
}

class _LigneAFaireWidget extends StatelessWidget {
  const _LigneAFaireWidget({required this.ligne, required this.n, required this.onTap});

  final LigneAFaire ligne;
  final int n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final schema = Theme.of(context).colorScheme;
    final sombre = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: sombre ? schema.surfaceContainerHigh : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: Key('a_faire_${ligne.cle}'),
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(ligne.icone, color: const Color(0xFFB9480F)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(ligne.texte(n), style: const TextStyle(fontWeight: FontWeight.w600))),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Élève : « Mon prochain cours ».
class _ProchainCours extends ConsumerWidget {
  const _ProchainCours();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cours = ref.watch(aujourdhuiProvider).valueOrNull ?? const [];
    final maintenant = DateTime.now();
    final prochain = cours.where((x) => x.enCours(maintenant) || x.aVenir(maintenant)).firstOrNull;
    if (prochain == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TitreSection('Mon prochain cours'),
        _CarteCours(cours: prochain, enCours: prochain.enCours(maintenant), cle: 'prochain_cours'),
      ],
    );
  }
}

/// Enseignant : « Aujourd'hui » (cours en cours et suivant).
class _Aujourdhui extends ConsumerWidget {
  const _Aujourdhui();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cours = ref.watch(aujourdhuiProvider).valueOrNull ?? const [];
    final maintenant = DateTime.now();
    final restants = cours.where((x) => x.enCours(maintenant) || x.aVenir(maintenant)).take(2).toList();
    if (restants.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TitreSection('Aujourd’hui'),
        for (final x in restants) _CarteCours(cours: x, enCours: x.enCours(maintenant), cle: 'cours_${x.debut}'),
      ],
    );
  }
}

class _CarteCours extends StatelessWidget {
  const _CarteCours({required this.cours, required this.enCours, required this.cle});

  final CoursDuJour cours;
  final bool enCours;
  final String cle;

  @override
  Widget build(BuildContext context) {
    final schema = Theme.of(context).colorScheme;
    final lieu = [cours.classe, cours.salle].whereType<String>().join(' · ');
    return Card(
      key: Key(cle),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(enCours ? 'EN COURS · ${cours.creneau}' : cours.creneau,
                style: TextStyle(fontWeight: FontWeight.w700, color: enCours ? schema.primary : null)),
            const SizedBox(height: 4),
            Text(cours.matiere ?? 'Cours', style: Theme.of(context).textTheme.titleMedium),
            if (lieu.isNotEmpty || cours.enseignant != null)
              Text([lieu, if (cours.enseignant != null) cours.enseignant!].where((t) => t.isNotEmpty).join(' · ')),
          ],
        ),
      ),
    );
  }
}
