import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/selecteur_vue.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/rh_providers.dart';
import '../domain/employe.dart';
import '../domain/enums_rh.dart';
import 'ecran_fiche_employe.dart';
import 'widgets/pastille_statut_employe.dart';

/// Tag Hero partagé par l'avatar d'un employé, ici et dans
/// [EcranFicheEmploye] — l'animation (D2) relie visuellement la galerie à la
/// fiche complète.
String heroAvatarEmploye(String employeId) => 'avatar-employe-$employeId';

String _formaterDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

/// Annuaire du personnel d'un établissement (M8, vue RH/direction) —
/// galerie interactive (D2) : bascule liste/grille/cartes, filtrage combiné
/// catégorie + statut, et animation Hero vers la fiche complète.
///
/// Filtrage ergonomique par catégorie et recherche par matricule/nom — la
/// visibilité réelle reste tranchée par RLS côté serveur (`employe_visible`) :
/// un profil non-RH qui atteindrait cet écran ne verrait jamais que sa
/// propre ligne.
class EcranAnnuairePersonnel extends ConsumerStatefulWidget {
  const EcranAnnuairePersonnel({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  ConsumerState<EcranAnnuairePersonnel> createState() => _EcranAnnuairePersonnelState();
}

class _EcranAnnuairePersonnelState extends ConsumerState<EcranAnnuairePersonnel> {
  final _rechercheCtrl = TextEditingController();
  CategorieEmploye? _filtreCategorie;

  // Filtre statut (D2) : restauré par rapport à `personnel_liste_screen.dart`
  // (source), qui le combinait déjà à un filtre type/catégorie via deux
  // rangées de `ChoiceChip` indépendantes — perdu dans la version initiale
  // de cet écran. `null` = "Toutes", pour ne pas masquer silencieusement des
  // employés visibles jusqu'ici (la source, elle, démarrait sur "Actifs"
  // seuls — un défaut plus strict qui aurait changé le comportement actuel
  // au premier lancement ; choix documenté, pas repris tel quel).
  StatutEmploye? _filtreStatut;

  ModeAffichage _mode = ModeAffichage.liste;

  @override
  void dispose() {
    _rechercheCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final employes = ref.watch(employesEtablissementProvider(widget.etablissementId));

    return Scaffold(
      appBar: AppBar(title: const Text('Personnel & RH')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _rechercheCtrl,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search),
                hintText: 'Rechercher un matricule ou un nom',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerRight,
              child: SelecteurVue(mode: _mode, onChanged: (m) => setState(() => _mode = m)),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _PucheFiltre(
                    libelle: 'Toutes',
                    selectionnee: _filtreCategorie == null,
                    onTap: () => setState(() => _filtreCategorie = null),
                  ),
                  for (final categorie in CategorieEmploye.values)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _PucheFiltre(
                        libelle: categorie.libelle,
                        selectionnee: _filtreCategorie == categorie,
                        onTap: () => setState(() => _filtreCategorie = categorie),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _PucheFiltre(
                    libelle: 'Tous statuts',
                    selectionnee: _filtreStatut == null,
                    onTap: () => setState(() => _filtreStatut = null),
                  ),
                  for (final statut in StatutEmploye.values)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _PucheFiltre(
                        libelle: statut.libelle,
                        selectionnee: _filtreStatut == statut,
                        onTap: () => setState(() => _filtreStatut = statut),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: employes.when(
              loading: () => ListView(
                padding: const EdgeInsets.all(16),
                children: List.generate(5, (_) => const ShimmerCarteListe()),
              ),
              error: (erreur, _) => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('Annuaire indisponible hors connexion pour le moment.'),
                ),
              ),
              data: (liste) {
                final filtres = _filtrer(liste);
                if (filtres.isEmpty) {
                  return const Center(child: Text('Aucun employé ne correspond à ce filtre.'));
                }
                return _corps(filtres);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _corps(List<Employe> filtres) {
    switch (_mode) {
      case ModeAffichage.liste:
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: filtres.length,
          itemBuilder: (context, i) => EntreeAnimee(
            index: i,
            enfant: _CarteEmployeAccordeon(employe: filtres[i]),
          ),
        );
      case ModeAffichage.grille:
        final colonnes = MediaQuery.sizeOf(context).width >= 720 ? 4 : 2;
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: colonnes,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.85,
          ),
          itemCount: filtres.length,
          itemBuilder: (context, i) => _TuileEmployeGrille(employe: filtres[i]),
        );
      case ModeAffichage.cartes:
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: filtres.length,
          itemBuilder: (context, i) => EntreeAnimee(
            index: i,
            enfant: _CarteEmployeRiche(employe: filtres[i]),
          ),
        );
    }
  }

  List<Employe> _filtrer(List<Employe> source) {
    final recherche = _rechercheCtrl.text.trim().toLowerCase();
    return source.where((e) {
      if (_filtreCategorie != null && e.categorie != _filtreCategorie) return false;
      if (_filtreStatut != null && e.statut != _filtreStatut) return false;
      if (recherche.isEmpty) return true;
      return e.matricule.toLowerCase().contains(recherche) ||
          (e.nomAffiche?.toLowerCase().contains(recherche) ?? false);
    }).toList(growable: false);
  }
}

class _PucheFiltre extends StatelessWidget {
  const _PucheFiltre({required this.libelle, required this.selectionnee, required this.onTap});

  final String libelle;
  final bool selectionnee;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(label: Text(libelle), selected: selectionnee, onSelected: (_) => onTap());
  }
}

/// Avatar à initiales, partagé par les trois modes d'affichage et par la
/// fiche complète (via [heroAvatarEmploye]).
class _AvatarEmploye extends StatelessWidget {
  const _AvatarEmploye({required this.employe, this.rayon = 20});

  final Employe employe;
  final double rayon;

  @override
  Widget build(BuildContext context) {
    final nom = employe.nomAffiche;
    final lettre = (nom != null && nom.trim().isNotEmpty)
        ? nom.trim().substring(0, 1).toUpperCase()
        : (employe.matricule.isEmpty ? '?' : employe.matricule.substring(0, 1).toUpperCase());
    return CircleAvatar(
      radius: rayon,
      backgroundColor: context.palette.primaire.withValues(alpha: 0.12),
      child: Text(
        lettre,
        style: TextStyle(color: context.palette.primaire, fontWeight: FontWeight.w700),
      ),
    );
  }
}

void _ouvrirFiche(BuildContext context, Employe employe) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EcranFicheEmploye(employe: employe)),
    );

/// Mode liste (D2) : ligne dense en accordéon — le tap sur l'en-tête ne fait
/// que déplier/replier ; ouvrir la fiche complète est une action explicite
/// dans le contenu déplié (pas de double sens au tap sur la ligne).
class _CarteEmployeAccordeon extends StatelessWidget {
  const _CarteEmployeAccordeon({required this.employe});

  final Employe employe;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: Hero(
          tag: heroAvatarEmploye(employe.id),
          child: _AvatarEmploye(employe: employe),
        ),
        title: Text(employe.nomAffiche ?? employe.matricule),
        subtitle: Row(
          children: [
            Expanded(child: Text('${employe.categorie.libelle} · ${employe.matricule}')),
            PastilleStatutEmploye(statut: employe.statut),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Pas de champ "poste" distinct de la catégorie ni de champ
                // contact (téléphone/email) dans le modèle `Employe` actuel
                // (public.employes) — l'aperçu se limite aux données réelles
                // disponibles plutôt que d'inventer un contenu.
                Text('Poste : ${employe.categorie.libelle}'),
                const SizedBox(height: 4),
                Text('Statut : ${employe.statut.libelle}'),
                const SizedBox(height: 4),
                Text(
                  'Aperçu : matricule ${employe.matricule} — '
                  'embauché le ${_formaterDate(employe.dateEmbauche)}',
                  style: TextStyle(color: context.palette.encreSecondaire),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _ouvrirFiche(context, employe),
                    icon: const Icon(Icons.badge_outlined),
                    label: const Text('Voir la fiche complète'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Mode grille (D2) : tuile compacte façon catalogue marketplace (D1).
class _TuileEmployeGrille extends StatelessWidget {
  const _TuileEmployeGrille({required this.employe});

  final Employe employe;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _ouvrirFiche(context, employe),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Hero(
                tag: heroAvatarEmploye(employe.id),
                child: _AvatarEmploye(employe: employe, rayon: 24),
              ),
              const SizedBox(height: 8),
              Text(
                employe.nomAffiche ?? employe.matricule,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                employe.categorie.libelle,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: context.palette.encreSecondaire),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mode cartes (D2) : format riche — c'est là que l'animation Hero est la
/// plus visible (carte pleine largeur, avatar plus grand).
class _CarteEmployeRiche extends StatelessWidget {
  const _CarteEmployeRiche({required this.employe});

  final Employe employe;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _ouvrirFiche(context, employe),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Hero(
                tag: heroAvatarEmploye(employe.id),
                child: _AvatarEmploye(employe: employe, rayon: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            employe.nomAffiche ?? employe.matricule,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                        ),
                        PastilleStatutEmploye(statut: employe.statut),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Poste : ${employe.categorie.libelle}',
                      style: TextStyle(color: context.palette.encreSecondaire),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Matricule ${employe.matricule} — '
                      'embauché le ${_formaterDate(employe.dateEmbauche)}',
                      style: TextStyle(fontSize: 12, color: context.palette.encreSecondaire),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
