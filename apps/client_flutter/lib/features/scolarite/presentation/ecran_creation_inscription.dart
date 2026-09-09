import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../planification/presentation/ecran_choix_classe.dart';
import '../application/scolarite_providers.dart';
import '../domain/classe.dart';
import '../domain/scolarite_repository.dart';

/// Création d'une inscription pour un nouvel élève (M15quater) — écart signalé
/// par l'audit : jusqu'ici, aucun écran ne permettait d'inscrire un élève
/// depuis l'app cible (`docs/AUDIT_ECOSHOP_FLUTTER.md`, M4/M5 point 1).
///
/// Le matricule est généré côté serveur (RPC `creer_inscription_nouvel_eleve`)
/// — jamais saisi ni calculé ici. Le doublon est vérifié avant l'envoi, mais
/// reste **informatif** : l'utilisateur peut continuer après confirmation,
/// cohérent avec le comportement documenté côté source (alerte, pas un refus
/// systématique).
class EcranCreationInscription extends ConsumerStatefulWidget {
  const EcranCreationInscription({super.key});

  @override
  ConsumerState<EcranCreationInscription> createState() => _EcranCreationInscriptionState();
}

class _EcranCreationInscriptionState extends ConsumerState<EcranCreationInscription> {
  final _nomCtrl = TextEditingController();
  final _prenomCtrl = TextEditingController();
  DateTime? _dateNaissance;
  String? _sexe;
  Classe? _classe;
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _nomCtrl.dispose();
    _prenomCtrl.dispose();
    super.dispose();
  }

  Future<void> _choisirDate() async {
    final maintenant = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(maintenant.year - 10),
      firstDate: DateTime(maintenant.year - 25),
      lastDate: maintenant,
      helpText: 'Date de naissance',
    );
    if (date != null) setState(() => _dateNaissance = date);
  }

  Future<void> _choisirClasse() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EcranChoixClasse(
          titre: 'Classe d\'inscription',
          onSelectionner: (context, classe) {
            setState(() => _classe = classe);
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  Future<void> _valider() async {
    final etablissement = ref.read(etablissementActifProvider);
    final structure = ref.read(structureEtablissementProvider(null)).value;
    final anneeId = structure?.anneeCourante?.id;
    final date = _dateNaissance;
    final classe = _classe;

    if (etablissement == null || anneeId == null) return;
    if (_nomCtrl.text.trim().isEmpty || _prenomCtrl.text.trim().isEmpty || date == null || classe == null) {
      setState(() => _erreur = 'Renseignez le nom, le prénom, la date de naissance et la classe.');
      return;
    }

    setState(() {
      _enCours = true;
      _erreur = null;
    });

    try {
      final repository = ref.read(scolariteRepositoryProvider);
      final doublon = await repository.verifierDoublonEleve(
        nom: _nomCtrl.text,
        prenom: _prenomCtrl.text,
        dateNaissance: date,
      );
      if (doublon && mounted) {
        final continuer = await _confirmerDoublon();
        if (continuer != true) {
          setState(() => _enCours = false);
          return;
        }
      }

      await repository.creerInscriptionNouvelEleve(
        etablissementId: etablissement.id,
        nom: _nomCtrl.text,
        prenom: _prenomCtrl.text,
        dateNaissance: date,
        classeId: classe.id,
        anneeScolaireId: anneeId,
        sexe: _sexe,
      );
      if (!mounted) return;
      ref.invalidate(inscriptionsDeClasseProvider(classe.id));
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Élève inscrit — matricule généré automatiquement.')),
      );
    } on ErreurScolarite catch (e) {
      setState(() => _erreur = _messageErreur(e.code));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<bool?> _confirmerDoublon() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Élève peut-être déjà inscrit'),
        content: const Text(
          'Un élève avec les mêmes nom, prénom et date de naissance semble déjà '
          'inscrit ailleurs. Voulez-vous continuer cette inscription ?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Continuer')),
        ],
      ),
    );
  }

  String _messageErreur(String code) => switch (code) {
        'PERMISSION_REFUSEE' => "Vous n'avez pas le droit d'inscrire un élève.",
        'CLASSE_AUTRE_ETABLISSEMENT' => 'Cette classe n\'appartient pas à cet établissement.',
        _ => 'Inscription impossible pour le moment.',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle inscription')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(controller: _nomCtrl, decoration: const InputDecoration(labelText: 'Nom')),
            const SizedBox(height: 12),
            TextField(controller: _prenomCtrl, decoration: const InputDecoration(labelText: 'Prénom')),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date de naissance'),
              subtitle: Text(_dateNaissance == null ? 'Non renseignée' : _formatDate(_dateNaissance!)),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: _choisirDate,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _sexe,
              decoration: const InputDecoration(labelText: 'Sexe (optionnel)'),
              items: const [
                DropdownMenuItem(value: 'M', child: Text('Masculin')),
                DropdownMenuItem(value: 'F', child: Text('Féminin')),
              ],
              onChanged: (v) => setState(() => _sexe = v),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Classe'),
              subtitle: Text(_classe?.nom ?? 'Non choisie'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _choisirClasse,
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 12),
              Text(_erreur!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _enCours ? null : _valider,
              child: _enCours
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Inscrire l\'élève'),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
