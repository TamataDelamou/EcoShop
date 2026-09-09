import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../auth/application/auth_providers.dart';
import '../../planification/presentation/ecran_choix_classe.dart';
import '../application/scolarite_providers.dart';
import '../domain/classe.dart';
import '../domain/fiche_eleve.dart';
import '../domain/scolarite_repository.dart';
import '../domain/verifications_reinscription.dart';

/// Réinscription annuelle d'une fiche existante (M15quater) — écart signalé
/// par l'audit (`docs/AUDIT_ECOSHOP_FLUTTER.md`, M4/M5 point 2).
///
/// Recherche par **matricule** plutôt que par téléphone parent (source) —
/// simplification assumée, documentée dans le rapport d'écart du module :
/// le matricule est déjà l'identifiant canonique de la fiche côté cible.
/// Les vérifications (impayé, sanction, statut boursier précédent) sont
/// **informatives** — la réinscription reste possible après lecture, comme
/// documenté côté source.
class EcranReinscription extends ConsumerStatefulWidget {
  const EcranReinscription({super.key});

  @override
  ConsumerState<EcranReinscription> createState() => _EcranReinscriptionState();
}

class _EcranReinscriptionState extends ConsumerState<EcranReinscription> {
  final _matriculeCtrl = TextEditingController();
  FicheEleve? _fiche;
  VerificationsReinscription? _verifications;
  Classe? _classe;
  bool _recherche = false;
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _matriculeCtrl.dispose();
    super.dispose();
  }

  Future<void> _rechercher() async {
    final etablissement = ref.read(etablissementActifProvider);
    if (etablissement == null || _matriculeCtrl.text.trim().isEmpty) return;

    setState(() {
      _recherche = true;
      _erreur = null;
      _fiche = null;
      _verifications = null;
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

      final historique = await repository.inscriptionsDeFiche(fiche.id);
      final derniere = historique.isEmpty ? null : historique.first;
      VerificationsReinscription? verifications;
      if (derniere != null) {
        verifications = await repository.verificationsReinscription(
          ficheEleveId: fiche.id,
          anneePrecedenteId: derniere.anneeScolaireId,
        );
      }

      setState(() {
        _fiche = fiche;
        _verifications = verifications;
      });
    } on ErreurScolarite catch (e) {
      setState(() => _erreur = e.code == 'PERMISSION_REFUSEE'
          ? "Vous n'avez pas le droit de consulter cette fiche."
          : 'Recherche impossible pour le moment.');
    } finally {
      if (mounted) setState(() => _recherche = false);
    }
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

    return Scaffold(
      appBar: AppBar(title: const Text('Réinscription')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _matriculeCtrl,
                    decoration: const InputDecoration(labelText: 'Matricule de l\'élève'),
                    onSubmitted: (_) => _rechercher(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _recherche ? null : _rechercher,
                  child: _recherche
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Chercher'),
                ),
              ],
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 12),
              Text(_erreur!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
