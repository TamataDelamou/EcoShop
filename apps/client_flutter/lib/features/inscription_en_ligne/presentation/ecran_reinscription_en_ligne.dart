import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../application/inscription_en_ligne_providers.dart';
import '../domain/inscription_en_ligne.dart';
import 'ecran_dossier_inscription.dart';
import 'widgets/elements_inscription.dart';

/// Réinscription en ligne d'un élève (par un parent, ou par l'élève
/// lui-même dès le collège). Fonctionne sans réseau : le dossier part au
/// retour du réseau.
class EcranReinscriptionEnLigne extends ConsumerStatefulWidget {
  const EcranReinscriptionEnLigne({super.key, required this.possible});

  final ReinscriptionPossible possible;

  @override
  ConsumerState<EcranReinscriptionEnLigne> createState() => _EcranReinscriptionEnLigneState();
}

class _EcranReinscriptionEnLigneState extends ConsumerState<EcranReinscriptionEnLigne> {
  String _intention = 'revient';
  late String _payeur;
  final _commentaire = TextEditingController();
  bool _enCours = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    final r = widget.possible;
    _payeur = r.niveauProposeIsced >= 2 ? (r.parLEleve ? 'eleve' : r.responsableFinancier) : 'parent';
  }

  @override
  void dispose() {
    _commentaire.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    final r = widget.possible;
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final resultat = await ref.read(inscriptionEnLigneRepositoryProvider).soumettre(SaisieDemandeInscription(
            campagneId: r.campagneId,
            type: 'reinscription',
            ficheEleveId: r.ficheEleveId,
            intention: _intention,
            nom: r.nom,
            prenom: r.prenom,
            niveauId: r.niveauProposeId,
            demandeurQualite: r.qualite,
            responsableFinancier: _payeur,
            commentaire: _commentaire.text.trim().isEmpty ? null : _commentaire.text.trim(),
            libelleEcole: r.etablissementNom,
            libelleNiveau: r.niveauProposeNom,
            niveauIsced: r.niveauProposeIsced,
            piecesRequises: r.piecesRequises,
          ));
      ref.invalidate(reinscriptionsPossiblesProvider);
      ref.invalidate(mesDemandesInscriptionProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(resultat.enAttenteEnvoi
            ? 'Réinscription enregistrée sur ce téléphone (${resultat.numeroDossier}) : elle partira au retour du réseau.'
            : _intention == 'ne_revient_pas'
                ? "C'est noté, merci de nous avoir prévenus."
                : 'Réinscription envoyée — dossier ${resultat.numeroDossier}.'),
      ));
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => EcranDossierInscription(demandeId: resultat.id)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _erreur = messageErreur(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final r = widget.possible;
    final revient = _intention == 'revient';

    return Scaffold(
      appBar: AppBar(title: Text(r.parLEleve ? 'Ma réinscription' : 'Réinscription')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.nomComplet, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  const SizedBox(height: 4),
                  Text(r.etablissementNom, style: TextStyle(color: palette.encreSecondaire)),
                  const Divider(height: 20),
                  _Ligne('Cette année', r.classeActuelle ?? '—'),
                  _Ligne('Année ${r.annee}', r.niveauProposeNom ?? '—'),
                  _Ligne("Frais d'inscription", r.fraisInscription > 0 ? montant(r.fraisInscription) : 'Aucun'),
                  _Ligne('Date limite', dateCourte(r.dateLimite)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Le niveau est proposé par l'école d'après les résultats de l'année ; elle peut l'ajuster.",
            style: TextStyle(color: palette.encreSecondaire, fontSize: 12),
          ),
          if (r.soldePrecedent > 0) ...[
            const SizedBox(height: 12),
            Encadre(
              icone: Icons.account_balance_wallet_outlined,
              couleur: palette.accent,
              texte: "Il reste ${montant(r.soldePrecedent)} à régler sur l'année en cours. La réinscription "
                  "n'est pas bloquée : l'école examinera le dossier et vous dira comment régulariser.",
            ),
          ],
          const SizedBox(height: 20),
          Text(r.parLEleve ? "L'an prochain, je…" : "L'an prochain, ${r.prenom}…",
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'revient', label: Text(r.parLEleve ? 'reviens' : 'revient'), icon: const Icon(Icons.check)),
              ButtonSegment(
                  value: 'ne_revient_pas', label: Text(r.parLEleve ? 'ne reviens pas' : 'ne revient pas'), icon: const Icon(Icons.close)),
            ],
            selected: {_intention},
            onSelectionChanged: _enCours ? null : (s) => setState(() => _intention = s.first),
          ),
          if (revient && r.niveauProposeIsced >= 2) ...[
            const SizedBox(height: 20),
            Text('Qui paie la scolarité ?', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              "Dès le collège, un élève à sa propre charge peut payer lui-même. Le parent comme l'élève voient le même solde.",
              style: TextStyle(color: palette.encreSecondaire, fontSize: 12),
            ),
            RadioGroup<String>(
              groupValue: _payeur,
              onChanged: (v) {
                if (_enCours || v == null) return;
                setState(() => _payeur = v);
              },
              child: Column(
                children: [
                  const RadioListTile<String>(value: 'parent', title: Text('Un parent ou tuteur')),
                  RadioListTile<String>(value: 'eleve', title: Text(r.parLEleve ? 'Moi-même' : "L'élève lui-même")),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _commentaire,
            enabled: !_enCours,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: "Message pour l'école (facultatif)",
              border: OutlineInputBorder(),
            ),
          ),
          if (_erreur != null) ...[
            const SizedBox(height: 12),
            Encadre(texte: _erreur!, icone: Icons.error_outline, couleur: palette.erreur),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          height: 52,
          child: FilledButton(
            key: const Key('envoyer_reinscription'),
            onPressed: _enCours ? null : _envoyer,
            child: _enCours
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text(revient ? 'Envoyer la réinscription' : "Prévenir l'école"),
          ),
        ),
      ),
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne(this.libelle, this.valeur);

  final String libelle;
  final String valeur;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(libelle, style: TextStyle(color: context.palette.encreSecondaire))),
          Text(valeur, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
