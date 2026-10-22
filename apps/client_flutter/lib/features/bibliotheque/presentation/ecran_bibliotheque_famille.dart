import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/bandeau_synchronisation.dart';
import '../application/bibliotheque_providers.dart';
import '../domain/bibliotheque.dart';

String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

/// Bibliothèque vue par l'élève ou ses parents (cahier 25.1) : catalogue
/// gratuit avec la disponibilité, emprunts en cours et leur échéance,
/// réservation d'un livre sorti. Consultable sans réseau (dernière liste).
class EcranBibliothequeFamille extends ConsumerStatefulWidget {
  const EcranBibliothequeFamille({
    super.key,
    required this.etablissementId,
    required this.ficheEleveId,
    required this.prenom,
  });

  final String etablissementId;
  final String ficheEleveId;
  final String prenom;

  @override
  ConsumerState<EcranBibliothequeFamille> createState() => _EcranBibliothequeFamilleState();
}

class _EcranBibliothequeFamilleState extends ConsumerState<EcranBibliothequeFamille> {
  String _texte = '';
  Timer? _attente;

  @override
  void dispose() {
    _attente?.cancel();
    super.dispose();
  }

  Future<void> _reserver(Livre l) async {
    try {
      await ref.read(bibliothequeRepositoryProvider).reserver(l.id, widget.ficheEleveId);
      ref.invalidate(empruntsEleveProvider(widget.ficheEleveId));
      ref.invalidate(catalogueProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('« ${l.titre} » réservé : vous serez prévenu(e) dès son retour.'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is ErreurBibliotheque ? e.messageUtilisateur : 'Réservation impossible pour le moment.'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final emprunts = ref.watch(empruntsEleveProvider(widget.ficheEleveId));
    final livres = ref.watch(catalogueProvider((etablissementId: widget.etablissementId, texte: _texte)));
    final reserves = {for (final r in emprunts.valueOrNull?.reservations ?? const <ReservationEleve>[]) r.livreId};

    return Scaffold(
      appBar: AppBar(title: const Text('Bibliothèque')),
      body: Column(
        children: [
          const BandeauSynchronisation(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Emprunts de ${widget.prenom}', style: Theme.of(context).textTheme.titleMedium),
                ...emprunts.when<List<Widget>>(
                  loading: () => [const LinearProgressIndicator()],
                  error: (e, _) => [const Text('Indisponible pour le moment.')],
                  data: (d) {
                    final enCours = d.emprunts.where((e) => e.statut != StatutEmprunt.rendu).toList();
                    return [
                      if (enCours.isEmpty) Text('Aucun livre emprunté.', style: TextStyle(color: palette.encreSecondaire)),
                      for (final e in enCours)
                        ListTile(
                          leading: Icon(
                            Icons.book_outlined,
                            color: e.statut == StatutEmprunt.enCours ? palette.primaire : palette.erreur,
                          ),
                          title: Text(e.titre),
                          subtitle: Text(e.statut == StatutEmprunt.enCours
                              ? 'À rendre le ${_date(e.echeance)}'
                              : '${e.statut.libelle} — devait être rendu le ${_date(e.echeance)}'),
                        ),
                      for (final r in d.reservations)
                        ListTile(
                          leading: Icon(r.prete ? Icons.notifications_active_outlined : Icons.bookmark_outline, color: palette.accent),
                          title: Text(r.titre),
                          subtitle: Text(r.prete
                              ? 'Disponible : à retirer avant le ${r.gardeeJusquAu == null ? '' : _date(r.gardeeJusquAu!)}'
                              : 'Réservé — vous serez prévenu(e) à son retour'),
                        ),
                    ];
                  },
                ),
                const SizedBox(height: 20),
                Text('Catalogue', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Titre, auteur, catégorie',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    _attente?.cancel();
                    _attente = Timer(const Duration(milliseconds: 400), () => setState(() => _texte = v.trim()));
                  },
                ),
                const SizedBox(height: 8),
                ...livres.when<List<Widget>>(
                  loading: () => [const LinearProgressIndicator()],
                  error: (e, _) => [const Text('Catalogue indisponible pour le moment.')],
                  data: (liste) => liste.isEmpty
                      ? [Text('Aucun livre trouvé.', style: TextStyle(color: palette.encreSecondaire))]
                      : [
                          for (final l in liste)
                            Card(
                              child: ListTile(
                                title: Text(l.titre),
                                subtitle: Text([
                                  if (l.auteurs != null) l.auteurs!,
                                  if (l.niveau != null) l.niveau!,
                                  l.disponibles > 0 ? '${l.disponibles} disponible(s)' : 'tous empruntés',
                                ].join(' · ')),
                                trailing: l.disponibles > 0
                                    ? Icon(Icons.check_circle_outline, color: palette.succes)
                                    : reserves.contains(l.id)
                                        ? const Chip(label: Text('Réservé'))
                                        : TextButton(onPressed: () => _reserver(l), child: const Text('Réserver')),
                              ),
                            ),
                        ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
