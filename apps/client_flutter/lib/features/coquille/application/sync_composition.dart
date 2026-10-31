import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/providers.dart';
import '../../justificatifs/data/justificatifs_repository.dart';
import '../../referentiel/back_office/referentiel_back_office_repository.dart';
import '../../revision/data/banque_questions_repository.dart';
import '../../revision/data/concours_repository.dart';
import '../../revision/data/revision_repository.dart';
import 'rejeu_actions_differees.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_providers.dart';
import '../../communication/application/comm_providers.dart';
import '../../../core/auth/supabase_auth_provider.dart';
import '../../annonces/data/supabase_annonces_repository.dart';
import '../../cahier_liaison/data/supabase_cahier_liaison_repository.dart';
import '../../groupes_classe/data/supabase_groupes_classe_repository.dart';
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
  // Cahier de liaison (REG-19) : mots, réponses et lectures faits sans réseau.
  final rejeuCahier = RejeuCahierLiaison(client);
  for (final entite in SupabaseCahierLiaisonRepository.entites) {
    gestionnaires[entite] = rejeuCahier.rejouer;
  }
  // Groupes de classe (REG-34) : messages écrits sans réseau.
  final rejeuGroupes = RejeuGroupesClasse(client);
  for (final entite in SupabaseGroupesClasseRepository.entites) {
    gestionnaires[entite] = rejeuGroupes.rejouer;
  }
  // Lot 4 (REG-35) : évaluations, sanctions, décisions de congé, statut
  // boursier, progression, panier — faits sans réseau.
  // Brouillons de la banque de questions (REG-37) gardés sans réseau.
  for (final entite in BanqueQuestionsRepository.entites) {
    gestionnaires[entite] = (entree) => BanqueQuestionsRepository.rejouer(client, entree);
  }
  // Quiz de révision et signalements faits sans réseau (REG-37 lot R2).
  for (final entite in RevisionRepository.entites) {
    gestionnaires[entite] = (entree) => RevisionRepository.rejouer(client, entree);
  }
  // Back-office du référentiel : écritures faites sans réseau (REG-38 E2b).
  for (final entite in ReferentielBackOfficeRepository.entites) {
    gestionnaires[entite] = (entree) => ReferentielBackOfficeRepository.rejouer(client, entree);
  }
  // Copies de concours remises sans réseau (REG-38 lot E2a).
  for (final entite in ConcoursRepository.entites) {
    gestionnaires[entite] = (entree) => ConcoursRepository.rejouer(client, entree);
  }
  // Justificatifs d'absence (REG-36) : dépôts et décisions faits sans réseau.
  for (final entite in JustificatifsRepository.entites) {
    gestionnaires[entite] = (entree) => JustificatifsRepository.rejouer(client, entree);
  }
  final rejeuDifferees = RejeuActionsDifferees(client);
  for (final entite in RejeuActionsDifferees.entites) {
    gestionnaires[entite] = rejeuDifferees.rejouer;
  }
  final journalRejets = ref.watch(journalRejetsProvider);

  return SyncEngine(
    repository: ref.watch(syncRepositoryProvider),
    estConnecte: () async => ref.read(estEnLigneProvider),
    estPanneReseau: estErreurReseau,
    rejouer: (entree) {
      final gestionnaire = gestionnaires[entree.entite];
      return gestionnaire == null ? Future.value() : gestionnaire(entree);
    },
    // Refus du serveur au retour du réseau : gardés pour l'utilisateur.
    surRejet: (entree, rejet) => journalRejets.enregistrer(
      entree,
      rejet,
      libelleOperation(entree),
    ),
  );
});

/// Libellé d'une opération de la file, en mots simples (journal des refus,
/// écran « État de la synchronisation »).
String libelleOperation(SyncEntree entree) {
  final simple = _libellesSimples[entree.entite];
  if (simple != null) return simple;
  if (JustificatifsRepository.entites.contains(entree.entite)) return JustificatifsRepository.libelle(entree);
  if (BanqueQuestionsRepository.entites.contains(entree.entite)) return BanqueQuestionsRepository.libelle(entree);
  if (RevisionRepository.entites.contains(entree.entite)) return RevisionRepository.libelle(entree);
  if (ConcoursRepository.entites.contains(entree.entite)) return ConcoursRepository.libelle(entree);
  if (ReferentielBackOfficeRepository.entites.contains(entree.entite)) return ReferentielBackOfficeRepository.libelle(entree);
  try {
    return entree.entite == RejeuTelephone.entite
          ? RejeuTelephone.libelle(entree)
          : RejeuActionsDifferees.entites.contains(entree.entite)
          ? RejeuActionsDifferees.libelle(entree)
          : SupabaseAnnoncesRepository.entites.contains(entree.entite)
          ? RejeuAnnonces.libelle(entree)
          : SupabaseCahierLiaisonRepository.entites.contains(entree.entite)
          ? RejeuCahierLiaison.libelle(entree)
          : SupabaseGroupesClasseRepository.entites.contains(entree.entite)
          ? RejeuGroupesClasse.libelle(entree)
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
                          : RejeuComptabilite.libelle(entree);
  } catch (_) {
    return 'Opération';
  }
}

/// Opérations des premiers modules (M6 à M14), sans libellé propre.
const _libellesSimples = {
  'notes': 'Note saisie',
  'presences': 'Appel (présence ou absence)',
  'retards': 'Retard',
  'conges': 'Demande de congé',
  'absences_personnel': 'Absence du personnel',
  'notifications_lecture': 'Notification lue',
  'preferences_canaux': 'Préférences de notification',
  'rapports': 'Demande de rapport',
  'emplois_du_temps': 'Séance d’emploi du temps',
  'evenements_agenda': 'Événement d’agenda',
  'progression_pedagogique': 'Progression pédagogique',
  'paniers': 'Panier',
  'lignes_paniers': 'Article du panier',
};

