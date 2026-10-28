import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../application/inscription_en_ligne_providers.dart';
import '../domain/inscription_en_ligne.dart';
import 'ecran_dossier_inscription.dart';
import 'widgets/elements_inscription.dart';
import 'widgets/prise_piece.dart';
import '../../../core/widgets/choisir_date.dart';

/// Demande d'inscription d'un nouvel élève (REG-08), en cinq étapes :
/// école, niveau, élève, demandeur et payeur, pièces. Sans réseau, le
/// dossier et les photos sont gardés sur le téléphone et partent seuls au
/// retour du réseau.
class EcranNouvelleInscription extends ConsumerStatefulWidget {
  const EcranNouvelleInscription({super.key});

  @override
  ConsumerState<EcranNouvelleInscription> createState() =>
      _EcranNouvelleInscriptionState();
}

class _EcranNouvelleInscriptionState
    extends ConsumerState<EcranNouvelleInscription> {
  int _etape = 0;
  String _recherche = '';
  Timer? _attenteRecherche;

  CampagneOuverte? _campagne;
  NiveauOffert? _niveau;

  final _nom = TextEditingController();
  final _prenom = TextEditingController();
  final _lieu = TextEditingController();
  final _ecolePrecedente = TextEditingController();
  final _telephone = TextEditingController();
  final _commentaire = TextEditingController();
  DateTime? _naissance;
  String? _sexe;
  String _qualite = 'parent';
  String _payeur = 'parent';
  final Map<String, PieceAEnvoyer> _pieces = {};

  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _attenteRecherche?.cancel();
    for (final c in [
      _nom,
      _prenom,
      _lieu,
      _ecolePrecedente,
      _telephone,
      _commentaire,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _collegeOuPlus => (_niveau?.isced ?? 0) >= 2;

  List<PieceRequise> get _piecesAttendues => [
    for (final p in _campagne?.piecesRequises ?? const <PieceRequise>[])
      if (p.concerne(_niveau?.isced ?? 0)) p,
  ];

  String? _blocageEtape(int etape) => switch (etape) {
    0 => _campagne == null ? "Choisissez l'école." : null,
    1 =>
      _niveau == null
          ? 'Choisissez le niveau demandé.'
          : !(_campagne?.nouvellesOuvertes ?? false)
          ? "L'école n'ouvre les demandes des nouveaux élèves qu'à partir du "
                "${_campagne?.ouvertureNouvelles == null ? '—' : dateCourte(_campagne!.ouvertureNouvelles!)}."
          : null,
    2 =>
      _nom.text.trim().isEmpty ||
              _prenom.text.trim().isEmpty ||
              _naissance == null
          ? "Renseignez le nom, le prénom et la date de naissance de l'élève."
          : null,
    _ => null,
  };

  void _continuer() {
    final blocage = _blocageEtape(_etape);
    if (blocage != null) {
      setState(() => _erreur = blocage);
      return;
    }
    setState(() {
      _erreur = null;
      if (_etape < 4) _etape++;
    });
    if (_etape == 4 && !_collegeOuPlus) {
      _qualite = 'parent';
      _payeur = 'parent';
    }
  }

  Future<void> _envoyer() async {
    final campagne = _campagne!;
    final niveau = _niveau!;
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    final depot = ref.read(inscriptionEnLigneRepositoryProvider);
    try {
      final resultat = await depot.soumettre(
        SaisieDemandeInscription(
          campagneId: campagne.campagneId,
          type: 'nouvelle',
          nom: _nom.text.trim().toUpperCase(),
          prenom: _prenom.text.trim(),
          dateNaissance: _naissance,
          sexe: _sexe,
          lieuNaissance: _lieu.text.trim().isEmpty ? null : _lieu.text.trim(),
          ecolePrecedente: _ecolePrecedente.text.trim().isEmpty
              ? null
              : _ecolePrecedente.text.trim(),
          niveauId: niveau.niveauId,
          demandeurQualite: _collegeOuPlus ? _qualite : 'parent',
          responsableFinancier: _collegeOuPlus ? _payeur : 'parent',
          telephone: _telephone.text.trim().isEmpty
              ? null
              : _telephone.text.trim(),
          commentaire: _commentaire.text.trim().isEmpty
              ? null
              : _commentaire.text.trim(),
          libelleEcole: campagne.etablissementNom,
          libelleNiveau: niveau.nom,
          niveauIsced: niveau.isced,
          piecesRequises: campagne.piecesRequises,
        ),
      );
      var piecesNonEnvoyees = 0;
      for (final piece in _pieces.values) {
        try {
          await depot.deposerPiece(resultat.id, piece);
        } catch (_) {
          piecesNonEnvoyees++;
        }
      }
      ref.invalidate(mesDemandesInscriptionProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            [
              resultat.enAttenteEnvoi
                  ? 'Demande enregistrée sur ce téléphone (${resultat.numeroDossier}) : elle partira au retour du réseau.'
                  : 'Demande envoyée — dossier ${resultat.numeroDossier}.',
              if (piecesNonEnvoyees > 0)
                '$piecesNonEnvoyees pièce(s) à rajouter depuis le dossier.',
            ].join(' '),
          ),
        ),
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => EcranDossierInscription(demandeId: resultat.id),
        ),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Inscrire un nouvel élève')),
      body: Stepper(
        currentStep: _etape,
        onStepTapped: _enCours
            ? null
            : (i) {
                if (i < _etape) setState(() => _etape = i);
              },
        onStepContinue: _enCours ? null : (_etape == 4 ? _envoyer : _continuer),
        onStepCancel: _enCours || _etape == 0
            ? null
            : () => setState(() => _etape--),
        controlsBuilder: (context, details) => Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_erreur != null) ...[
                Encadre(
                  texte: _erreur!,
                  icone: Icons.error_outline,
                  couleur: palette.erreur,
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  FilledButton(
                    key: Key('etape_suivante_$_etape'),
                    onPressed: details.onStepContinue,
                    child: _enCours
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _etape == 4 ? 'Envoyer la demande' : 'Continuer',
                          ),
                  ),
                  const SizedBox(width: 8),
                  if (details.onStepCancel != null)
                    TextButton(
                      onPressed: details.onStepCancel,
                      child: const Text('Retour'),
                    ),
                ],
              ),
            ],
          ),
        ),
        steps: [
          Step(
            title: const Text('École'),
            subtitle: _campagne == null
                ? null
                : Text(_campagne!.etablissementNom),
            isActive: _etape >= 0,
            content: _etapeEcole(),
          ),
          Step(
            title: const Text('Niveau demandé'),
            subtitle: _niveau == null ? null : Text(_niveau!.nom),
            isActive: _etape >= 1,
            content: _etapeNiveau(),
          ),
          Step(
            title: const Text("L'élève"),
            isActive: _etape >= 2,
            content: _etapeEleve(),
          ),
          Step(
            title: const Text('Demandeur et paiement'),
            isActive: _etape >= 3,
            content: _etapeDemandeur(),
          ),
          Step(
            title: const Text('Pièces du dossier'),
            isActive: _etape >= 4,
            content: _etapePieces(),
          ),
        ],
      ),
    );
  }

  Widget _etapeEcole() {
    final campagnes = ref.watch(campagnesOuvertesProvider(_recherche));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('recherche_ecole'),
          decoration: const InputDecoration(
            labelText: "Nom de l'école ou ville",
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          onChanged: (v) {
            _attenteRecherche?.cancel();
            _attenteRecherche = Timer(
              const Duration(milliseconds: 400),
              () => setState(() => _recherche = v.trim()),
            );
          },
        ),
        const SizedBox(height: 12),
        campagnes.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (e, _) =>
              Encadre(texte: messageErreur(e), icone: Icons.cloud_off_outlined),
          data: (liste) => liste.isEmpty
              ? const Encadre(
                  texte:
                      "Aucune école n'a d'inscriptions ouvertes sous ce nom pour le moment.",
                )
              : Column(
                  children: [
                    for (final c in liste)
                      Card(
                        color: _campagne?.campagneId == c.campagneId
                            ? context.palette.primaire.withValues(alpha: 0.08)
                            : null,
                        child: ListTile(
                          leading: const Icon(Icons.school_outlined),
                          title: Text(c.etablissementNom),
                          subtitle: Text(
                            [
                              if (c.ville != null) c.ville!,
                              'Année ${c.annee}',
                              "jusqu'au ${dateCourte(c.dateLimite)}",
                            ].join(' · '),
                          ),
                          trailing: _campagne?.campagneId == c.campagneId
                              ? const Icon(Icons.check_circle)
                              : null,
                          onTap: () => setState(() {
                            if (_campagne?.campagneId != c.campagneId) {
                              _niveau = null;
                            }
                            _campagne = c;
                            _erreur = null;
                          }),
                        ),
                      ),
                  ],
                ),
        ),
        if (_campagne?.consignes != null) ...[
          const SizedBox(height: 8),
          Encadre(texte: _campagne!.consignes!, icone: Icons.campaign_outlined),
        ],
      ],
    );
  }

  Widget _etapeNiveau() {
    final campagne = _campagne;
    if (campagne == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final n in campagne.niveaux)
              ChoiceChip(
                label: Text(n.nom),
                selected: _niveau?.niveauId == n.niveauId,
                onSelected: (_) => setState(() {
                  _niveau = n;
                  _erreur = null;
                }),
              ),
          ],
        ),
        if (_niveau != null) ...[
          const SizedBox(height: 12),
          Encadre(
            icone: _niveau!.complet
                ? Icons.hourglass_empty
                : Icons.event_seat_outlined,
            couleur: _niveau!.complet ? context.palette.accent : null,
            texte: [
              if (_niveau!.placesRestantes == null)
                'Places disponibles.'
              else if (_niveau!.complet)
                "Ce niveau est complet : la demande sera mise en liste d'attente si l'école l'accepte."
              else
                '${_niveau!.placesRestantes} place(s) restante(s).',
              _niveau!.fraisInscription > 0
                  ? "Frais d'inscription : ${montant(_niveau!.fraisInscription)}, à régler une fois la demande acceptée."
                  : "Pas de frais d'inscription.",
            ].join(' '),
          ),
        ],
      ],
    );
  }

  Widget _etapeEleve() {
    return Column(
      children: [
        TextField(
          key: const Key('nom_eleve'),
          controller: _nom,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Nom',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('prenom_eleve'),
          controller: _prenom,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Prénom(s)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.cake_outlined),
          title: Text(
            _naissance == null
                ? 'Date de naissance'
                : 'Né(e) le ${dateCourte(_naissance!)}',
          ),
          trailing: const Icon(Icons.edit_calendar_outlined),
          onTap: () async {
            final maintenant = DateTime.now();
            final choisie = await choisirDate(
              context: context,
              initialDate: _naissance ?? DateTime(maintenant.year - 10),
              firstDate: DateTime(maintenant.year - 30),
              lastDate: maintenant,
              helpText: 'Date de naissance',
            );
            if (choisie != null) setState(() => _naissance = choisie);
          },
        ),
        SegmentedButton<String>(
          emptySelectionAllowed: true,
          segments: const [
            ButtonSegment(value: 'F', label: Text('Fille')),
            ButtonSegment(value: 'M', label: Text('Garçon')),
          ],
          selected: {?_sexe},
          onSelectionChanged: (s) =>
              setState(() => _sexe = s.isEmpty ? null : s.first),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _lieu,
          decoration: const InputDecoration(
            labelText: 'Lieu de naissance (facultatif)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _ecolePrecedente,
          decoration: const InputDecoration(
            labelText: 'École fréquentée cette année (facultatif)',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _etapeDemandeur() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_collegeOuPlus) ...[
          const Text(
            'Qui fait la demande ?',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          RadioGroup<String>(
            groupValue: _qualite,
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                _qualite = v;
                if (v == 'eleve') _payeur = 'eleve';
              });
            },
            child: const Column(
              children: [
                RadioListTile<String>(
                  value: 'parent',
                  title: Text('Un parent ou tuteur'),
                ),
                RadioListTile<String>(
                  value: 'eleve',
                  title: Text("L'élève lui-même"),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Qui paie la scolarité ?',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          RadioGroup<String>(
            groupValue: _payeur,
            onChanged: (v) {
              if (v != null) setState(() => _payeur = v);
            },
            child: const Column(
              children: [
                RadioListTile<String>(
                  value: 'parent',
                  title: Text('Un parent ou tuteur'),
                ),
                RadioListTile<String>(
                  value: 'eleve',
                  title: Text("L'élève lui-même (à sa propre charge)"),
                ),
              ],
            ),
          ),
        ] else
          const Encadre(
            texte:
                "Avant le collège, c'est le parent qui fait la demande et qui paie la scolarité.",
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _telephone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Téléphone de contact (facultatif)',
            prefixIcon: Icon(Icons.phone_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _commentaire,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: "Message pour l'école (facultatif)",
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _etapePieces() {
    final attendues = _piecesAttendues;
    if (attendues.isEmpty) {
      return const Encadre(
        texte:
            "L'école ne demande aucune pièce en ligne. Vous pouvez envoyer la demande.",
      );
    }
    final manquantes = [
      for (final p in attendues)
        if (p.obligatoire && !_pieces.containsKey(p.code)) p,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in attendues)
          PrisePiece(
            piece: p,
            prise: _pieces.containsKey(p.code),
            onPrise: (piece) => setState(() => _pieces[p.code] = piece),
          ),
        if (manquantes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Encadre(
            icone: Icons.attach_file,
            couleur: context.palette.accent,
            texte:
                'Vous pouvez envoyer la demande maintenant et ajouter les pièces manquantes plus tard depuis le dossier.',
          ),
        ],
      ],
    );
  }
}
