import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_providers.dart';
import '../../communication/application/comm_providers.dart';
import '../../../core/auth/supabase_auth_provider.dart';
import '../../annonces/data/supabase_annonces_repository.dart';
import '../../comptabilite/application/comptabilite_providers.dart';
import '../../comptabilite/data/rejeu_comptabilite.dart';
import '../../auth/data/rejeu_telephone.dart';
import '../../bibliotheque/data/supabase_bibliotheque_repository.dart';
import '../../inscription_en_ligne/data/inscription_hors_ligne_repository.dart';
import '../../inscription_en_ligne/data/rejeu_inscriptions.dart';
import '../../pointage/data/supabase_pointage_repository.dart';
import '../../reseau/data/supabase_reseau_repository.dart';
import '../../reseau/data/supabase_transferts_reseau_repository.dart';
import '../../transport/data/supabase_transport_repository.dart';
import '../../scolarite/data/rejeu_encaissements.dart';
import '../../marketplace/application/marketplace_providers.dart';
import '../../notes/application/notes_providers.dart';
import '../../planification/application/planification_providers.dart';
import '../../rapports/application/rapports_providers.dart';
import '../../rh_personnel/application/rh_providers.dart';
import '../../vie_scolaire/application/vie_scolaire_providers.dart';

/// Assemble le [SyncEngine] applicatif avec la fonction de rejeu de chaque
/// module d'écriture hors-ligne.
///
/// Composition volontairement centralisée ici (coquille = racine
/// applicative) plutôt que dans `core/sync` : le socle ne doit pas connaître
/// les entités métier (`notes`, puis `absences`, `paiements`…) qu'il rejoue —
/// seule la coquille, qui assemble déjà toutes les features pour la
/// navigation, a une vue d'ensemble légitime sur ce registre.
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final gestionnaires = <String, Future<void> Function(SyncEntree)>{
    'notes': ref.watch(notesRejeuProvider),
    'presences': ref.watch(presencesRejeuProvider),
    'retards': ref.watch(retardsRejeuProvider),
    'conges': ref.watch(congesRejeuProvider),
    'absences_personnel': ref.watch(absencesPersonnelRejeuProvider),
    'notifications_lecture': ref.watch(notificationsLectureRejeuProvider),
    'preferences_canaux': ref.watch(preferencesCanauxRejeuProvider),
    'rapports': ref.watch(rapportsRejeuProvider),
    'emplois_du_temps': ref.watch(emploisRejeuProvider),
    'evenements_agenda': ref.watch(evenementsAgendaRejeuProvider),
    'progression_pedagogique': ref.watch(progressionPedagogiqueRejeuProvider),
    'paniers': ref.watch(paniersRejeuProvider),
    'lignes_paniers': ref.watch(lignesPaniersRejeuProvider),
    'ecritures_comptables': ref.watch(ecrituresRejeuProvider),
  };
  // Comptabilité REG-03 (C7) : dons, donateurs, brouillards, notes annexes…
  final rejeuComptable = RejeuComptabilite(ref.watch(supabaseClientProvider));
  for (final entite in entitesComptabiliteHorsLigne) {
    gestionnaires[entite] = rejeuComptable.rejouer;
  }
  // Inscriptions en ligne REG-08 : dossiers, pièces, décisions, guichet…
  final rejeuInscriptions = RejeuInscriptions(ref.watch(supabaseClientProvider), ref.watch(syncRepositoryProvider));
  for (final entite in InscriptionHorsLigneRepository.entites) {
    gestionnaires[entite] = rejeuInscriptions.rejouer;
  }
  // Pointage au portail REG-09 : scans faits sans réseau.
  final client = ref.watch(supabaseClientProvider);
  gestionnaires[SupabasePointageRepository.entiteScan] = (entree) => SupabasePointageRepository.rejouer(client, entree);
  // Encaissements au guichet faits sans réseau (reçu provisoire).
  final rejeuEncaissements = RejeuEncaissements(client);
  for (final entite in RejeuEncaissements.entites) {
    gestionnaires[entite] = rejeuEncaissements.rejouer;
  }
  // Réseaux d'établissements (M19) : demande, circulaires, calendrier,
  // réponses aux invitations, accusés de lecture saisis sans réseau.
  final rejeuReseau = RejeuReseau(client);
  for (final entite in SupabaseReseauRepository.entites) {
    gestionnaires[entite] = rejeuReseau.rejouer;
  }
  // Transport scolaire (M18) : trajet, arrêts, position, scans du chauffeur.
  // Transferts d'élèves (REG-17) : même rejeu que le reste du réseau.
  for (final entite in SupabaseTransfertsReseauRepository.entites) {
    gestionnaires[entite] = rejeuReseau.rejouer;
  }

  final rejeuTransport = RejeuTransport(client);
  for (final entite in SupabaseTransportRepository.entites) {
    gestionnaires[entite] = rejeuTransport.rejouer;
  }
  // Bibliothèque (M17) : prêts et retours faits au guichet sans réseau.
  gestionnaires[RejeuTelephone.entite] = RejeuTelephone(client).rejouer;

  final rejeuBibliotheque = RejeuBibliotheque(client);
  for (final entite in SupabaseBibliothequeRepository.entites) {
    gestionnaires[entite] = rejeuBibliotheque.rejouer;
  }
  // Annonces de l'école (REG-19) : publications et lectures faites sans réseau.
  final rejeuAnnonces = RejeuAnnonces(client);
  for (final entite in SupabaseAnnoncesRepository.entites) {
    gestionnaires[entite] = rejeuAnnonces.rejouer;
  }
  final journalRejets = ref.watch(journalRejetsProvider);

  return SyncEngine(
    repository: ref.watch(syncRepositoryProvider),
    estConnecte: () async => ref.read(estEnLigneProvider),
    rejouer: (entree) {
      final gestionnaire = gestionnaires[entree.entite];
      return gestionnaire == null ? Future.value() : gestionnaire(entree);
    },
    // Refus du serveur au retour du réseau : gardés pour l'utilisateur.
    surRejet: (entree, rejet) => journalRejets.enregistrer(
      entree,
      rejet,
      entree.entite == RejeuTelephone.entite
          ? RejeuTelephone.libelle(entree)
          : SupabaseAnnoncesRepository.entites.contains(entree.entite)
          ? RejeuAnnonces.libelle(entree)
          : SupabaseTransfertsReseauRepository.entites.contains(entree.entite)
          ? SupabaseTransfertsReseauRepository.libelle(entree)
          : InscriptionHorsLigneRepository.entites.contains(entree.entite)
          ? RejeuInscriptions.libelle(entree)
          : RejeuEncaissements.entites.contains(entree.entite)
              ? RejeuEncaissements.libelle(entree)
              : SupabaseReseauRepository.entites.contains(entree.entite)
                  ? RejeuReseau.libelle(entree)
                  : SupabaseTransportRepository.entites.contains(entree.entite)
                      ? RejeuTransport.libelle(entree)
                      : SupabaseBibliothequeRepository.entites.contains(entree.entite)
                          ? RejeuBibliotheque.libelle(entree)
                          : RejeuComptabilite.libelle(entree),
    ),
  );
});
