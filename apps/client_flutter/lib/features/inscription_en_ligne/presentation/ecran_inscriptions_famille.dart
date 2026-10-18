import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/bandeau_synchronisation.dart';
import '../application/inscription_en_ligne_providers.dart';
import '../domain/inscription_en_ligne.dart';
import 'ecran_dossier_inscription.dart';
import 'ecran_nouvelle_inscription.dart';
import 'ecran_reinscription_en_ligne.dart';
import 'widgets/elements_inscription.dart';

/// Espace « Inscriptions » des familles (REG-08) : réinscrire ses enfants
/// (ou soi-même dès le collège), demander l'inscription d'un nouvel élève,
/// suivre ses dossiers. Fonctionne sans réseau.
class EcranInscriptionsFamille extends ConsumerWidget {
  const EcranInscriptionsFamille({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reinscriptions = ref.watch(reinscriptionsPossiblesProvider);
    final dossiers = ref.watch(mesDemandesInscriptionProvider);

    Future<void> actualiser() async {
      ref.invalidate(reinscriptionsPossiblesProvider);
      ref.invalidate(mesDemandesInscriptionProvider);
      await ref.read(mesDemandesInscriptionProvider.future).catchError((_) => <DemandeInscription>[]);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Inscriptions')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('bouton_nouvel_eleve'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const EcranNouvelleInscription()),
        ),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Inscrire un nouvel élève'),
      ),
      body: Column(
        children: [
          const BandeauSynchronisation(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: actualiser,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: [
                  Text('Réinscriptions', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  reinscriptions.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => Encadre(texte: messageErreur(e), icone: Icons.cloud_off_outlined),
                    data: (liste) {
                      final dossiersConnus = dossiers.value ?? const <DemandeInscription>[];
                      if (liste.isEmpty) {
                        return const Encadre(
                          texte: "Aucune réinscription en cours pour le moment. Quand l'école ouvre ses "
                              'réinscriptions, vos enfants apparaissent ici.',
                        );
                      }
                      return Column(
                        children: [
                          for (final r in liste)
                            _CarteReinscription(
                              possible: r,
                              enAttente: dossiersConnus.where((d) => d.enAttenteEnvoi && d.ficheEleveId == r.ficheEleveId).firstOrNull,
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  Text('Mes dossiers', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  dossiers.when(
                    loading: () => const SizedBox.shrink(),
                    error: (e, _) => Encadre(texte: messageErreur(e), icone: Icons.cloud_off_outlined),
                    data: (liste) => liste.isEmpty
                        ? const Encadre(texte: 'Aucun dossier pour le moment.')
                        : Column(
                            children: [
                              for (final d in liste)
                                CarteDossier(
                                  demande: d,
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => EcranDossierInscription(demandeId: d.id)),
                                  ),
                                ),
                            ],
                          ),
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

class _CarteReinscription extends StatelessWidget {
  const _CarteReinscription({required this.possible, this.enAttente});

  final ReinscriptionPossible possible;

  /// Réinscription déjà saisie sur cet appareil, pas encore envoyée.
  final DemandeInscription? enAttente;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final r = possible;
    final demande = r.demande;
    final dossierId = enAttente?.id ?? demande?.id;

    Widget action;
    if (dossierId != null) {
      action = OutlinedButton.icon(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => EcranDossierInscription(demandeId: dossierId)),
        ),
        icon: const Icon(Icons.folder_open_outlined),
        label: const Text('Voir le dossier'),
      );
    } else if (!r.ouverte) {
      action = Text('Les réinscriptions ne sont pas encore ouvertes.', style: TextStyle(color: palette.encreSecondaire));
    } else if (!r.niveauOffert) {
      action = Text(
        "Le niveau suivant n'est pas ouvert dans cette école. Contactez l'école.",
        style: TextStyle(color: palette.encreSecondaire),
      );
    } else {
      action = FilledButton.icon(
        key: Key('reinscrire_${r.ficheEleveId}'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => EcranReinscriptionEnLigne(possible: r)),
        ),
        icon: const Icon(Icons.autorenew),
        label: Text(r.parLEleve ? 'Me réinscrire' : 'Réinscrire'),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.parLEleve ? 'Moi — ${r.nomComplet}' : r.nomComplet,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 2),
            Text(
              '${r.etablissementNom} · ${r.classeActuelle ?? '—'} → ${r.niveauProposeNom ?? '—'} (${r.annee})',
              style: TextStyle(color: palette.encreSecondaire),
            ),
            const SizedBox(height: 4),
            Text('Date limite : ${dateCourte(r.dateLimite)}', style: TextStyle(color: palette.encreSecondaire, fontSize: 12)),
            if (enAttente != null || demande != null) ...[
              const SizedBox(height: 8),
              PastilleStatut(
                statut: demande?.statut ?? StatutDemandeInscription.soumise,
                enAttenteEnvoi: enAttente != null,
              ),
            ],
            const SizedBox(height: 10),
            action,
          ],
        ),
      ),
    );
  }
}
