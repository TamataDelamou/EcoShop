import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/auth/e164_validator.dart';
import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../auth/application/auth_providers.dart';
import '../../planification/presentation/ecran_choix_classe.dart';
import '../application/scolarite_providers.dart';
import '../domain/classe.dart';
import '../domain/fiche_eleve.dart';
import '../domain/scolarite_repository.dart';
import '../domain/verifications_reinscription.dart';

/// Réinscription annuelle d'une fiche existante (M15quater, fast-track D6).
///
/// Point d'entrée principal : recherche par **téléphone du parent** (cahier
/// §7.1) — fait apparaître tous les enfants rattachés à ce numéro, avec une
/// vraie sélection quand plusieurs enfants le partagent (le prototype source
/// ne résolvait jamais ce cas : `eleves.first`, TODO jamais levé — corrigé
/// ici plutôt que reproduit). La recherche par **matricule** (ancien point
/// d'entrée unique, cf. rapport d'écart M15quater) reste disponible en
/// option secondaire, sans régression. Les vérifications (impayé, sanction,
/// statut boursier précédent) restent **informatives** — la réinscription
/// reste possible après lecture, comme documenté côté source.
class EcranReinscription extends ConsumerStatefulWidget {
  const EcranReinscription({super.key});

  @override
  ConsumerState<EcranReinscription> createState() => _EcranReinscriptionState();
}

class _EcranReinscriptionState extends ConsumerState<EcranReinscription> {
  final _indicatifCtrl = TextEditingController(text: '+224');
  final _telephoneCtrl = TextEditingController();
  final _matriculeCtrl = TextEditingController();
  bool _parMatricule = false;

  List<FicheEleve>? _candidats;
  FicheEleve? _fiche;
  VerificationsReinscription? _verifications;
  Classe? _classe;
  bool _recherche = false;
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _indicatifCtrl.dispose();
    _telephoneCtrl.dispose();
    _matriculeCtrl.dispose();
    super.dispose();
  }

  void _basculerMode(bool parMatricule) {
    setState(() {
      _parMatricule = parMatricule;
      _erreur = null;
      _candidats = null;
    });
  }

  Future<void> _rechercherParTelephone() async {
    final etablissement = ref.read(etablissementActifProvider);
    final telephone = Validators.normalizeE164(
      indicatifPays: _indicatifCtrl.text,
      numeroLocal: _telephoneCtrl.text,
    );
    if (etablissement == null) return;
    if (telephone == null) {
      setState(() => _erreur = 'Numéro de téléphone invalide.');
      return;
    }

    setState(() {
      _recherche = true;
      _erreur = null;
      _fiche = null;
      _verifications = null;
      _candidats = null;
    });

    try {
      final repository = ref.read(scolariteRepositoryProvider);
      final enfants = await repository.rechercherEnfantsParTelephoneParent(
        etablissementId: etablissement.id,
        telephone: telephone,
      );
      if (enfants.isEmpty) {
        setState(() => _erreur = 'Aucun enfant trouvé pour ce numéro.');
        return;
      }
      if (enfants.length == 1) {
        await _selectionnerFiche(enfants.first);
        return;
      }
      setState(() => _candidats = enfants);
    } on ErreurScolarite catch (e) {
      setState(() => _erreur = e.code == 'PERMISSION_REFUSEE'
          ? "Vous n'avez pas le droit de consulter cette fiche."
          : 'Recherche impossible pour le moment.');
    } finally {
      if (mounted) setState(() => _recherche = false);
    }
  }

  Future<void> _rechercherParMatricule() async {
    final etablissement = ref.read(etablissementActifProvider);
    if (etablissement == null || _matriculeCtrl.text.trim().isEmpty) return;

    setState(() {
      _recherche = true;
      _erreur = null;
      _fiche = null;
      _verifications = null;
      _candidats = null;
    });

    try {
      final repository = ref.read(scolariteRepositoryProvider);
      final fiche = await repository.ficheParMatricule(
        etablissementId: etablissement.id,
        matricule: _matriculeCtrl.text,
      );
      if (fiche == null) {
        setState(() => _erreur = 'Aucun élève trouvé avec ce matricule.');
        return;
      }
      await _selectionnerFiche(fiche);
    } on ErreurScolarite catch (e) {
      setState(() => _erreur = e.code == 'PERMISSION_REFUSEE'
          ? "Vous n'avez pas le droit de consulter cette fiche."
          : 'Recherche impossible pour le moment.');
    } finally {
      if (mounted) setState(() => _recherche = false);
    }
  }

  Future<void> _selectionnerFiche(FicheEleve fiche) async {
    setState(() {
      _candidats = null;
      _fiche = fiche;
    });

    final repository = ref.read(scolariteRepositoryProvider);
    final historique = await repository.inscriptionsDeFiche(fiche.id);
    final derniere = historique.isEmpty ? null : historique.first;
    VerificationsReinscription? verifications;
    if (derniere != null) {
      verifications = await repository.verificationsReinscription(
        ficheEleveId: fiche.id,
        anneePrecedenteId: derniere.anneeScolaireId,
      );
    }
    if (!mounted) return;
    setState(() => _verifications = verifications);
  }

  Future<void> _choisirClasse() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EcranChoixClasse(
          titre: 'Classe de réinscription',
          onSelectionner: (context, classe) {
            setState(() => _classe = classe);
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  Future<void> _confirmer() async {
    final fiche = _fiche;
    final classe = _classe;
    final structure = ref.read(structureEtablissementProvider(null)).value;
    final anneeId = structure?.anneeCourante?.id;
    if (fiche == null || classe == null || anneeId == null) return;

    setState(() {
      _enCours = true;
      _erreur = null;
    });

    try {
      await ref.read(scolariteRepositoryProvider).creerReinscription(
            ficheEleveId: fiche.id,
            classeId: classe.id,
            anneeScolaireId: anneeId,
          );
      if (!mounted) return;
      ref.invalidate(inscriptionsDeFicheProvider(fiche.id));
      ref.invalidate(inscriptionsDeClasseProvider(classe.id));
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${fiche.nomComplet} réinscrit(e) en ${classe.nom}.')),
      );
    } on ErreurScolarite catch (e) {
      setState(() => _erreur = e.code == 'PERMISSION_REFUSEE'
          ? "Vous n'avez pas le droit de réinscrire cet élève."
          : 'Réinscription impossible — l\'élève est peut-être déjà inscrit pour cette année.');
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fiche = _fiche;
    final verifications = _verifications;
    final candidats = _candidats;

    return Scaffold(
      appBar: AppBar(title: const Text('Réinscription')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_parMatricule) ...[
              Text('Téléphone du parent', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: _indicatifCtrl,
                      decoration: const InputDecoration(labelText: 'Indicatif'),
                      keyboardType: TextInputType.phone,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _telephoneCtrl,
                      decoration: const InputDecoration(labelText: 'Numéro', hintText: '620 00 00 00'),
                      keyboardType: TextInputType.phone,
                      onSubmitted: (_) => _rechercherParTelephone(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _recherche ? null : _rechercherParTelephone,
                    child: _recherche
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Chercher'),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _basculerMode(true),
                  child: const Text('Rechercher plutôt par matricule'),
                ),
              ),
            ] else ...[
              Text('Matricule de l\'élève', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _matriculeCtrl,
                      decoration: const InputDecoration(labelText: 'Matricule de l\'élève'),
                      onSubmitted: (_) => _rechercherParMatricule(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _recherche ? null : _rechercherParMatricule,
                    child: _recherche
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Chercher'),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _basculerMode(false),
                  child: const Text('Rechercher plutôt par téléphone du parent'),
                ),
              ),
            ],
            if (_erreur != null) ...[
              const SizedBox(height: 12),
              Text(_erreur!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (candidats != null) ...[
              const SizedBox(height: 16),
              Text(
                'Plusieurs enfants partagent ce numéro — choisissez :',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              for (final candidat in candidats)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(candidat.nomComplet),
                    subtitle: Text('Matricule ${candidat.matricule}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _selectionnerFiche(candidat),
                  ),
                ),
            ],
            if (fiche != null) ...[
              const SizedBox(height: 20),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(fiche.nomComplet),
                  subtitle: Text('Matricule ${fiche.matricule}'),
                ),
              ),
              if (verifications != null && verifications.aDesAlertes) ...[
                const SizedBox(height: 8),
                if (verifications.impaye)
                  _Alerte(texte: 'Solde impayé sur l\'année précédente', couleur: context.palette.erreur),
                if (verifications.sanctionActive)
                  _Alerte(texte: 'Sanction disciplinaire active', couleur: context.palette.accent),
              ],
              if (verifications?.boursierPrecedent ?? false)
                _Alerte(texte: 'Boursier l\'année précédente', couleur: context.palette.premium),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Nouvelle classe'),
                subtitle: Text(_classe?.nom ?? 'Non choisie'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _choisirClasse,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _enCours || _classe == null ? null : _confirmer,
                child: _enCours
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Confirmer la réinscription'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Alerte extends StatelessWidget {
  const _Alerte({required this.texte, required this.couleur});

  final String texte;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(Icons.warning_amber_outlined, size: 18, color: couleur),
          const SizedBox(width: 8),
          Expanded(child: Text(texte, style: TextStyle(color: couleur, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
