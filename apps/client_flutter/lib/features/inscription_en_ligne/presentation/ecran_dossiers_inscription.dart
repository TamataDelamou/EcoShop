import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/bandeau_synchronisation.dart';
import '../../paiement_mobile/application/paiement_mobile_providers.dart';
import '../../scolarite/application/scolarite_providers.dart';
import '../../scolarite/domain/classe.dart';
import '../application/inscription_en_ligne_providers.dart';
import '../domain/inscription_en_ligne.dart';
import 'widgets/elements_inscription.dart';
import 'widgets/prise_piece.dart';

/// Dossiers d'une campagne (Direction) : tableau de bord, filtres par étape,
/// examen d'un dossier (pièces, alertes), décision, paiement au guichet.
/// Décisions et espèces encaissées sans réseau partent au retour du réseau.
class EcranDossiersInscription extends ConsumerStatefulWidget {
  const EcranDossiersInscription({
    super.key,
    required this.campagneId,
    required this.anneeScolaireId,
    this.devise = 'GNF',
  });

  final String campagneId;
  final String anneeScolaireId;
  final String devise;

  @override
  ConsumerState<EcranDossiersInscription> createState() => _EcranDossiersInscriptionState();
}

/// Regroupements proposés en filtre.
enum _Filtre {
  aTraiter('À traiter'),
  aRegler('À régler'),
  attente("Liste d'attente"),
  inscrits('Inscrits'),
  tous('Tous');

  const _Filtre(this.libelle);

  final String libelle;

  bool garde(DemandeInscription d) => switch (this) {
        _Filtre.aTraiter => const {
            StatutDemandeInscription.soumise,
            StatutDemandeInscription.aExaminer,
            StatutDemandeInscription.incomplete,
            StatutDemandeInscription.convoquee,
          }.contains(d.statut),
        _Filtre.aRegler => d.statut == StatutDemandeInscription.acceptee,
        _Filtre.attente => d.statut == StatutDemandeInscription.listeAttente,
        _Filtre.inscrits => d.statut == StatutDemandeInscription.inscrite,
        _Filtre.tous => true,
      };
}

class _EcranDossiersInscriptionState extends ConsumerState<EcranDossiersInscription> {
  _Filtre _filtre = _Filtre.aTraiter;
  String _recherche = '';

  void _actualiser() {
    ref.invalidate(dossiersCampagneProvider(widget.campagneId));
    ref.invalidate(tableauCampagneProvider(widget.campagneId));
  }

  @override
  Widget build(BuildContext context) {
    final dossiers = ref.watch(dossiersCampagneProvider(widget.campagneId));
    final tableau = ref.watch(tableauCampagneProvider(widget.campagneId));
    final enAttente = ref.watch(dossiersActionEnAttenteProvider).valueOrNull ?? const <String>{};

    return Scaffold(
      appBar: AppBar(title: const Text("Dossiers d'inscription")),
      body: Column(
        children: [
          const BandeauSynchronisation(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _actualiser(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  tableau.when(
                    loading: () => const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
                    error: (e, _) => Encadre(texte: messageErreur(e), icone: Icons.cloud_off_outlined),
                    data: (t) => _Tableau(tableau: t, devise: widget.devise),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Nom ou numéro de dossier',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _recherche = v.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final f in _Filtre.values)
                        ChoiceChip(
                          label: Text(f.libelle),
                          selected: _filtre == f,
                          onSelected: (_) => setState(() => _filtre = f),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  dossiers.when(
                    loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
                    error: (e, _) => Encadre(texte: messageErreur(e), icone: Icons.cloud_off_outlined),
                    data: (liste) {
                      final vus = [
                        for (final d in liste)
                          if (_filtre.garde(d) &&
                              (_recherche.isEmpty ||
                                  d.nomComplet.toLowerCase().contains(_recherche) ||
                                  d.numeroDossier.toLowerCase().contains(_recherche)))
                            d,
                      ];
                      if (vus.isEmpty) return const Encadre(texte: 'Aucun dossier dans cette catégorie.');
                      return Column(
                        children: [
                          for (final d in vus)
                            CarteDossier(
                              demande: d,
                              actionEnAttente: enAttente.contains(d.id),
                              onTap: () async {
                                await showModalBottomSheet<void>(
                                  context: context,
                                  isScrollControlled: true,
                                  useSafeArea: true,
                                  builder: (_) => FeuilleDossier(
                                    demande: d,
                                    anneeScolaireId: widget.anneeScolaireId,
                                  ),
                                );
                                _actualiser();
                              },
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tableau extends StatelessWidget {
  const _Tableau({required this.tableau, required this.devise});

  final TableauCampagne tableau;
  final String devise;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final t = tableau;
    Widget tuile(String valeur, String libelle, {Color? couleur}) => Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Column(
                children: [
                  Text(valeur, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: couleur ?? palette.encre)),
                  const SizedBox(height: 2),
                  Text(libelle, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: palette.encreSecondaire)),
                ],
              ),
            ),
          ),
        );
    final aTraiter = t.nombre(StatutDemandeInscription.soumise) +
        t.nombre(StatutDemandeInscription.aExaminer) +
        t.nombre(StatutDemandeInscription.incomplete) +
        t.nombre(StatutDemandeInscription.convoquee);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          tuile('${(t.tauxReinscription * 100).round()} %', 'réinscrits\n(${t.reinscrits}/${t.elevesEligibles})', couleur: palette.succes),
          tuile('$aTraiter', 'à traiter', couleur: palette.accent),
          tuile('${t.nombre(StatutDemandeInscription.acceptee)}', 'acceptés\nà régler', couleur: palette.primaire),
        ]),
        Row(children: [
          tuile('${t.nombre(StatutDemandeInscription.listeAttente)}', "en liste\nd'attente"),
          tuile('${t.desistements}', 'ne reviennent\npas'),
          tuile(montant(t.fraisEncaisses, devise), 'frais\nencaissés'),
        ]),
        if (t.niveaux.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final n in t.niveaux)
                Chip(
                  avatar: Icon(
                    n.placesRestantes == 0 ? Icons.block : Icons.event_seat_outlined,
                    size: 16,
                    color: n.placesRestantes == 0 ? palette.erreur : palette.succes,
                  ),
                  label: Text(
                    '${n.nom} : ${n.placesRestantes == null ? 'places libres' : '${n.placesRestantes} place(s)'}'
                    '${n.enAttente > 0 ? ' · ${n.enAttente} en attente' : ''}',
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Examen d'un dossier et décision (Direction).
class FeuilleDossier extends ConsumerStatefulWidget {
  const FeuilleDossier({super.key, required this.demande, required this.anneeScolaireId});

  final DemandeInscription demande;
  final String anneeScolaireId;

  @override
  ConsumerState<FeuilleDossier> createState() => _FeuilleDossierState();
}

class _FeuilleDossierState extends ConsumerState<FeuilleDossier> {
  bool _enCours = false;
  String? _erreur;

  Future<String?> _demanderMotif(DecisionDossier decision) async {
    final controle = TextEditingController();
    final motif = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(decision.libelle),
        content: TextField(
          controller: controle,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: switch (decision) {
              DecisionDossier.incomplete => 'Pièces à fournir',
              DecisionDossier.convoquer => 'Date, heure et lieu (test, entretien…)',
              _ => 'Motif (la famille le verra)',
            },
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(c).pop(controle.text.trim()), child: const Text('Valider')),
        ],
      ),
    );
    controle.dispose();
    return motif;
  }

  Future<void> _decider(DecisionDossier decision, {bool forcer = false}) async {
    String? motif;
    if (decision.motifObligatoire) {
      motif = await _demanderMotif(decision);
      if (motif == null || motif.isEmpty) return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final statut = await ref
          .read(inscriptionEnLigneRepositoryProvider)
          .traiter(widget.demande.id, decision, motif: motif, forcer: forcer);
      if (!mounted) return;
      final messager = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messager.showSnackBar(SnackBar(
        content: Text(statut == null
            ? 'Décision enregistrée sur cet appareil : elle sera appliquée au retour du réseau.'
            : 'Dossier ${widget.demande.numeroDossier} : ${statut.libelle}.'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _erreur = messageErreur(e);
      });
    }
  }

  Future<void> _encaisser(List<Classe> classes) async {
    final d = widget.demande;
    final montantCtrl = TextEditingController(text: d.montantARegler > 0 ? d.montantARegler.round().toString() : '0');
    var moyen = 'especes';
    String? classeId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Paiement au guichet'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: montantCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: "Frais d'inscription reçus (${d.devise})", border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: moyen,
                decoration: const InputDecoration(labelText: 'Moyen', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'especes', child: Text('Espèces')),
                  DropdownMenuItem(value: 'mobile_money', child: Text('Mobile money (hors application)')),
                  DropdownMenuItem(value: 'virement', child: Text('Virement')),
                  DropdownMenuItem(value: 'cheque', child: Text('Chèque')),
                ],
                onChanged: (v) => set(() => moyen = v ?? 'especes'),
              ),
              if (classes.isNotEmpty) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: classeId,
                  decoration: const InputDecoration(labelText: 'Classe', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Automatique (la moins chargée)')),
                    for (final cl in classes) DropdownMenuItem<String?>(value: cl.id, child: Text(cl.nom)),
                  ],
                  onChanged: (v) => set(() => classeId = v),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.of(c).pop(true), child: const Text("Confirmer l'inscription")),
          ],
        ),
      ),
    );
    final montantRecu = double.tryParse(montantCtrl.text.trim()) ?? 0;
    montantCtrl.dispose();
    if (ok != true) return;
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final inscription = await ref
          .read(inscriptionEnLigneRepositoryProvider)
          .finaliserAuGuichet(d.id, classeId: classeId, montant: montantRecu, moyen: moyen);
      if (!mounted) return;
      final messager = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messager.showSnackBar(SnackBar(
        content: Text(inscription == null
            ? "Paiement noté sur cet appareil : l'inscription sera créée au retour du réseau."
            : '${d.nomComplet} est inscrit(e).'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _erreur = messageErreur(e);
      });
    }
  }

  Future<void> _ouvrirPiece(String chemin) async {
    try {
      final url = await ref.read(inscriptionEnLigneRepositoryProvider).lienPiece(chemin);
      await ref.read(lanceurUrlProvider).ouvrir(url);
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreur = messageErreur(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final d = widget.demande;
    final classes = [
      for (final c in ref.watch(structureEtablissementProvider(widget.anneeScolaireId)).valueOrNull?.classes ?? const <Classe>[])
        if (c.niveauId == d.niveauId && c.actif) c,
    ];
    final ouvert = !d.statut.estClos;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, defilement) => ListView(
        controller: defilement,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: palette.bordure, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Text(d.nomComplet, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(
            [
              d.estReinscription ? 'Réinscription' : 'Nouvel élève',
              d.niveauNom ?? '',
              'né(e) le ${dateCourte(d.dateNaissance)}',
            ].where((s) => s.isNotEmpty).join(' · '),
            style: TextStyle(color: palette.encreSecondaire),
          ),
          const SizedBox(height: 8),
          Row(children: [
            PastilleStatut(statut: d.statut),
            const Spacer(),
            Text('N° ${d.numeroDossier}', style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          if (d.impaye != null)
            Encadre(
              icone: Icons.money_off_outlined,
              couleur: palette.accent,
              texte: "Impayé de l'année en cours : ${montant(d.impaye!, d.devise)}. À vous de décider : accepter, "
                  'accepter avec un échéancier convenu avec la famille, ou refuser.',
            ),
          if (d.sanctionActive) ...[
            const SizedBox(height: 6),
            Encadre(icone: Icons.gavel_outlined, couleur: palette.accent, texte: "L'élève a une sanction en cours."),
          ],
          if (d.doublonPossible) ...[
            const SizedBox(height: 6),
            Encadre(
              icone: Icons.content_copy_outlined,
              couleur: palette.accent,
              texte: 'Un élève du même nom, né le même jour, est déjà inscrit dans une école : vérifiez avec la famille.',
            ),
          ],
          if (d.intention == 'ne_revient_pas') ...[
            const SizedBox(height: 6),
            const Encadre(icone: Icons.logout, texte: 'La famille a indiqué que l\'élève ne revient pas.'),
          ],
          const SizedBox(height: 12),
          _Info('Demandé par', d.demandeurQualite == 'eleve' ? "L'élève lui-même" : 'Un parent'),
          _Info('Payeur', d.responsableFinancier == 'eleve' ? "L'élève (à sa charge)" : 'Le parent'),
          if (d.telephone != null) _Info('Téléphone', d.telephone!),
          if (d.lieuNaissance != null) _Info('Lieu de naissance', d.lieuNaissance!),
          if (d.ecolePrecedente != null) _Info('École actuelle', d.ecolePrecedente!),
          if (d.rangAttente != null) _Info("Rang en liste d'attente", '${d.rangAttente}'),
          if (d.offreExpireLe != null && d.statut == StatutDemandeInscription.acceptee)
            _Info('Place réservée jusqu\'au', dateCourte(d.offreExpireLe!)),
          if (d.montantARegler > 0) _Info("Frais d'inscription", montant(d.montantARegler, d.devise)),
          if (d.commentaire != null) ...[
            const SizedBox(height: 8),
            Encadre(icone: Icons.chat_bubble_outline, texte: 'Message de la famille : ${d.commentaire}'),
          ],
          if (d.motif != null) ...[
            const SizedBox(height: 8),
            Encadre(icone: Icons.forum_outlined, texte: 'Dernier message envoyé : ${d.motif}'),
          ],
          if (d.piecesAttendues.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Pièces', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            for (final p in d.piecesAttendues)
              PrisePiece(
                piece: p,
                prise: d.pieces.containsKey(p.code),
                onPrise: null,
                onOuvrir: d.pieces[p.code] == null ? null : () => _ouvrirPiece(d.pieces[p.code]!),
              ),
          ],
          if (_erreur != null) ...[
            const SizedBox(height: 10),
            Encadre(texte: _erreur!, icone: Icons.error_outline, couleur: palette.erreur),
          ],
          if (ouvert) ...[
            const SizedBox(height: 16),
            Text('Décision', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_enCours)
              const Center(child: CircularProgressIndicator())
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (d.statut != StatutDemandeInscription.acceptee)
                    FilledButton.icon(
                      key: const Key('decision_accepter'),
                      onPressed: () => _decider(DecisionDossier.accepter),
                      icon: const Icon(Icons.check),
                      label: const Text('Accepter'),
                    ),
                  if (d.statut == StatutDemandeInscription.listeAttente)
                    OutlinedButton.icon(
                      onPressed: () => _decider(DecisionDossier.accepter, forcer: true),
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Accepter en surnombre'),
                    ),
                  OutlinedButton.icon(
                    key: const Key('decision_guichet'),
                    onPressed: () => _encaisser(classes),
                    icon: const Icon(Icons.point_of_sale_outlined),
                    label: const Text('Payé au guichet → inscrire'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _decider(DecisionDossier.incomplete),
                    icon: const Icon(Icons.attach_file),
                    label: const Text('Réclamer des pièces'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _decider(DecisionDossier.convoquer),
                    icon: const Icon(Icons.event_outlined),
                    label: const Text('Convoquer'),
                  ),
                  if (d.statut != StatutDemandeInscription.listeAttente)
                    OutlinedButton.icon(
                      onPressed: () => _decider(DecisionDossier.listeAttente),
                      icon: const Icon(Icons.hourglass_empty),
                      label: const Text("Liste d'attente"),
                    ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: palette.erreur),
                    onPressed: () => _decider(DecisionDossier.refuser),
                    icon: const Icon(Icons.close),
                    label: const Text('Refuser'),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.libelle, this.valeur);

  final String libelle;
  final String valeur;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 160, child: Text(libelle, style: TextStyle(color: context.palette.encreSecondaire))),
            Expanded(child: Text(valeur, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );
}
