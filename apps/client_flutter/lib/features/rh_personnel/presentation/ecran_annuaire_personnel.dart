import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/rh_providers.dart';
import '../domain/employe.dart';
import '../domain/enums_rh.dart';
import 'ecran_fiche_employe.dart';
import 'widgets/pastille_statut_employe.dart';

/// Annuaire du personnel d'un établissement (M8, vue RH/direction).
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
  CategorieEmploye? _filtre;

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
            child: SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _PucheFiltre(
                    libelle: 'Toutes',
                    selectionnee: _filtre == null,
                    onTap: () => setState(() => _filtre = null),
                  ),
                  for (final categorie in CategorieEmploye.values)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _PucheFiltre(
                        libelle: categorie.libelle,
                        selectionnee: _filtre == categorie,
                        onTap: () => setState(() => _filtre = categorie),
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
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtres.length,
                  itemBuilder: (context, i) => EntreeAnimee(
                    index: i,
                    enfant: _CarteEmploye(employe: filtres[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Employe> _filtrer(List<Employe> source) {
    final recherche = _rechercheCtrl.text.trim().toLowerCase();
    return source.where((e) {
      if (_filtre != null && e.categorie != _filtre) return false;
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

class _CarteEmploye extends StatelessWidget {
  const _CarteEmploye({required this.employe});

  final Employe employe;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: context.palette.primaire.withValues(alpha: 0.12),
          child: Text(
            employe.matricule.isEmpty ? '?' : employe.matricule.substring(0, 1).toUpperCase(),
            style: TextStyle(color: context.palette.primaire, fontWeight: FontWeight.w700),
          ),
        ),
        title: Text(employe.nomAffiche ?? employe.matricule),
        subtitle: Text('${employe.categorie.libelle} · ${employe.matricule}'),
        trailing: PastilleStatutEmploye(statut: employe.statut),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => EcranFicheEmploye(employe: employe)),
        ),
      ),
    );
  }
}
