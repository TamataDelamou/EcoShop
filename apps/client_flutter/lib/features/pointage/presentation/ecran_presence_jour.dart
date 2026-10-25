import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/bandeau_synchronisation.dart';
import '../../etablissement/domain/etablissement.dart';
import '../../export_pdf/data/cartes_eleves_pdf_builder.dart';
import '../../export_pdf/presentation/ecran_apercu_pdf.dart';
import '../../scolarite/application/scolarite_providers.dart';
import '../../themes/application/theme_providers.dart';
import '../application/pointage_providers.dart';
import '../domain/pointage.dart';
import 'ecran_credits_sms.dart';
import 'ecran_parametres_pointage.dart';
import 'ecran_portail.dart';
import 'ecran_relances_impayes.dart';

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

enum _Filtre {
  absents('Absents'),
  retards('Retards'),
  sortis('Sortis'),
  ecarts('Écarts avec l\'appel'),
  tous('Tous');

  const _Filtre(this.libelle);

  final String libelle;

  bool garde(EleveDuJour e) => switch (this) {
        _Filtre.absents => e.absent,
        _Filtre.retards => e.enRetard,
        _Filtre.sortis => e.sortie != null,
        _Filtre.ecarts => e.ecart,
        _Filtre.tous => true,
      };
}

/// Présence du jour (Direction, REG-09) : arrivées, retards, absents,
/// sorties, écarts avec l'appel, état du portail, alertes envoyées.
class EcranPresenceJour extends ConsumerStatefulWidget {
  const EcranPresenceJour({super.key, required this.etablissement});

  final Etablissement etablissement;

  @override
  ConsumerState<EcranPresenceJour> createState() => _EcranPresenceJourState();
}

class _EcranPresenceJourState extends ConsumerState<EcranPresenceJour> {
  _Filtre _filtre = _Filtre.absents;

  String get _etab => widget.etablissement.id;

  void _actualiser() => ref.invalidate(presenceDuJourProvider(_etab));

  Future<void> _imprimerCartes() async {
    final structure = ref.read(structureEtablissementProvider(null)).valueOrNull;
    final classes = structure?.classes.where((c) => c.actif).toList() ?? const [];
    if (classes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucune classe cette année.')));
      return;
    }
    final classe = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Cartes de quelle classe ?'),
        children: [
          for (final cl in classes) SimpleDialogOption(onPressed: () => Navigator.of(c).pop(cl.id), child: Text(cl.nom)),
        ],
      ),
    );
    if (classe == null) return;
    try {
      final cartes = await ref.read(pointageRepositoryProvider).cartesClasse(classe);
      final octets = await construireCartesElevesPdf(
        cartes: cartes,
        etablissement: widget.etablissement,
        annee: structure?.anneeCourante?.libelle ?? '',
        variante: ref.read(themeVariantProvider),
        identite: await ref.read(identitePdfProvider.future),
      );
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => EcranApercuPdf(titre: 'Cartes élèves', octets: octets, nomFichier: 'cartes-eleves.pdf'),
      ));
    } on ErreurPointage catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.messageUtilisateur)));
    }
  }

  Future<void> _actionsEleve(EleveDuJour e, DateTime jour) async {
    final choix = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(e.nomComplet, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(e.classe ?? '')),
            ListTile(
              leading: const Icon(Icons.exit_to_app),
              title: const Text("Autoriser une sortie aujourd'hui"),
              subtitle: const Text("Pas d'alerte aux parents si l'élève sort avant la fin des cours"),
              onTap: () => Navigator.of(c).pop('sortie'),
            ),
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Remplacer la carte (perdue, volée)'),
              subtitle: const Text("L'ancienne carte ne passera plus au portail"),
              onTap: () => Navigator.of(c).pop('carte'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choix == null) return;
    final depot = ref.read(pointageRepositoryProvider);
    try {
      if (choix == 'sortie') {
        final motif = TextEditingController();
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Sortie autorisée'),
            content: TextField(
              controller: motif,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Motif (rendez-vous, maladie…)', border: OutlineInputBorder()),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Annuler')),
              FilledButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Autoriser')),
            ],
          ),
        );
        final texte = motif.text.trim();
        motif.dispose();
        if (ok != true || texte.isEmpty) return;
        await depot.autoriserSortie(e.ficheEleveId, jour, texte);
      } else {
        await depot.remplacerCarte(e.ficheEleveId);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nouvelle carte créée : imprimez les cartes de la classe pour la remettre à l\'élève.'),
        ));
      }
      _actualiser();
    } on ErreurPointage catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.messageUtilisateur)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final presence = ref.watch(presenceDuJourProvider(_etab));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Présence du jour'),
        actions: [
          IconButton(
            tooltip: 'Ouvrir le portail',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EcranPortail(etablissementId: _etab)),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              final route = switch (v) {
                'cartes' => null,
                'parametres' => MaterialPageRoute<void>(builder: (_) => EcranParametresPointage(etablissementId: _etab)),
                'sms' => MaterialPageRoute<void>(
                    builder: (_) => EcranCreditsSms(etablissementId: _etab, devise: widget.etablissement.deviseCode)),
                _ => MaterialPageRoute<void>(
                    builder: (_) => EcranRelancesImpayes(etablissementId: _etab, devise: widget.etablissement.deviseCode)),
              };
              if (route == null) {
                _imprimerCartes();
              } else {
                Navigator.of(context).push(route).then((_) => _actualiser());
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'cartes', child: Text('Imprimer les cartes élèves')),
              PopupMenuItem(value: 'parametres', child: Text('Réglages du pointage')),
              PopupMenuItem(value: 'sms', child: Text('Crédits SMS')),
              PopupMenuItem(value: 'relances', child: Text('Relancer les impayés')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          const BandeauSynchronisation(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _actualiser(),
              child: presence.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ListView(children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(e is ErreurPointage ? e.messageUtilisateur : 'Indisponible pour le moment.',
                        textAlign: TextAlign.center),
                  ),
                ]),
                data: (p) {
                  final eleves = [for (final e in p.eleves) if (_filtre.garde(e)) e];
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      if (!p.actif)
                        Card(
                          color: palette.accent.withValues(alpha: 0.12),
                          child: ListTile(
                            leading: const Icon(Icons.info_outline),
                            title: const Text('Le pointage n\'est pas encore activé'),
                            subtitle: const Text('Les familles ne reçoivent aucun avis. Activez-le dans les réglages.'),
                            onTap: () => Navigator.of(context)
                                .push(MaterialPageRoute<void>(builder: (_) => EcranParametresPointage(etablissementId: _etab)))
                                .then((_) => _actualiser()),
                          ),
                        ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _Tuile('${p.arrives}/${p.effectif}', 'arrivés', palette.succes),
                          _Tuile('${p.absents}', 'absents', palette.erreur),
                          _Tuile('${p.enRetard}', 'retards', palette.accent),
                          _Tuile('${p.sortis}', 'sortis', palette.primaire),
                          _Tuile('${p.ecarts}', 'écarts appel', palette.premium),
                          _Tuile('${p.creditsSms}', 'crédits SMS', palette.encreSecondaire),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _EtatPortail(presence: p),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final f in _Filtre.values)
                            ChoiceChip(label: Text(f.libelle), selected: _filtre == f, onSelected: (_) => setState(() => _filtre = f)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (eleves.isEmpty)
                        const Padding(padding: EdgeInsets.all(16), child: Text('Personne dans cette catégorie.')),
                      for (final e in eleves)
                        Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            onTap: () => _actionsEleve(e, p.jour),
                            leading: Icon(
                              e.absent ? Icons.person_off_outlined : (e.sortie != null ? Icons.logout : Icons.how_to_reg),
                              color: e.absent ? palette.erreur : (e.enRetard ? palette.accent : palette.succes),
                            ),
                            title: Text(e.nomComplet),
                            subtitle: Text([
                              if (e.classe != null) e.classe!,
                              if (e.arrivee != null) 'arrivé(e) ${_hm(e.arrivee!)}${e.enRetard ? ' (retard)' : ''}',
                              if (e.sortie != null) 'sorti(e) ${_hm(e.sortie!)}${e.sortieAutorisee ? ' (autorisée)' : ''}',
                              if (e.absent && e.justifie) 'absence justifiée',
                              if (e.alerteAbsence) 'famille alertée',
                              if (e.alerteSortie) 'sortie signalée à la famille',
                              if (e.ecart) 'absent(e) à l\'appel en classe',
                            ].join(' · ')),
                            trailing: const Icon(Icons.more_vert),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tuile extends StatelessWidget {
  const _Tuile(this.valeur, this.libelle, this.couleur);

  final String valeur;
  final String libelle;
  final Color couleur;

  @override
  Widget build(BuildContext context) => Container(
        width: 104,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(color: couleur.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
        child: Column(
          children: [
            Text(valeur, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: couleur)),
            Text(libelle, style: TextStyle(fontSize: 11, color: context.palette.encreSecondaire)),
          ],
        ),
      );
}

class _EtatPortail extends StatelessWidget {
  const _EtatPortail({required this.presence});

  final PresenceDuJour presence;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final p = presence;
    final synchro = p.derniereSynchro;
    final String texte;
    final IconData icone;
    var couleur = palette.encreSecondaire;
    if (p.traiteLe != null) {
      texte = 'Absences vérifiées à ${_hm(p.traiteLe!)} : ${p.alertesEnvoyees} famille(s) prévenue(s).';
      icone = Icons.notifications_active_outlined;
    } else if (synchro == null) {
      texte = "Aucun portail n'a encore transmis de scans. Ouvrez le portail sur le téléphone de l'entrée.";
      icone = Icons.qr_code_scanner;
      couleur = palette.accent;
    } else {
      texte = 'Dernière transmission du portail à ${_hm(synchro)}. '
          "Les alertes d'absence partent après l'heure limite${p.heureLimiteArrivee == null ? '' : ' (${p.heureLimiteArrivee})'}, "
          'une fois les scans du portail reçus.';
      icone = Icons.cloud_sync_outlined;
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: couleur.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: couleur),
          const SizedBox(width: 10),
          Expanded(child: Text(texte)),
        ],
      ),
    );
  }
}
