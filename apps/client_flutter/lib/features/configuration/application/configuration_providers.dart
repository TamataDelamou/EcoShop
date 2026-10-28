import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_providers.dart';
import '../../planification/domain/emploi_du_temps.dart';
import '../../planification/domain/moteur_emploi_du_temps.dart';
import '../../scolarite/domain/classe.dart';
import '../data/configuration_repository.dart';
import '../domain/configuration.dart';

/// Copie de l'appareil (consultation sans réseau), purgée à la déconnexion.
final lectureConfigurationProvider = Provider<LectureHorsLigne>((ref) {
  return LectureHorsLigne(
    CacheDocumentStore(ref.watch(databaseProvider), 'configuration_hl'),
    ref.watch(fraicheurHorsLigneProvider),
  );
});

final configurationRepositoryProvider = Provider<ConfigurationRepository>((ref) {
  return ConfigurationRepository(ref.watch(supabaseClientProvider), ref.watch(lectureConfigurationProvider));
});

final etatConfigurationProvider = FutureProvider.autoDispose.family<EtatConfiguration, String>((ref, etablissementId) {
  return ref.watch(configurationRepositoryProvider).etat(etablissementId);
});

final groupesProvider = FutureProvider.autoDispose.family<List<GroupePedagogique>, String>((ref, anneeId) {
  return ref.watch(configurationRepositoryProvider).groupes(anneeId);
});

final membresGroupeProvider = FutureProvider.autoDispose.family<Set<String>, String>((ref, groupeId) {
  return ref.watch(configurationRepositoryProvider).membresGroupe(groupeId);
});

final personnelProvider = FutureProvider.autoDispose.family<List<MembrePersonnel>, String>((ref, etablissementId) {
  return ref.watch(configurationRepositoryProvider).personnel(etablissementId);
});

final affectationsAnneeProvider = FutureProvider.autoDispose.family<List<AffectationCours>, String>((ref, anneeId) {
  return ref.watch(configurationRepositoryProvider).affectations(anneeId);
});

final grilleHoraireProvider = FutureProvider.autoDispose.family<GrilleHoraire?, String>((ref, anneeId) {
  return ref.watch(configurationRepositoryProvider).grille(anneeId);
});

final indisponibilitesProvider = FutureProvider.autoDispose.family<List<Indisponibilite>, String>((ref, anneeId) {
  return ref.watch(configurationRepositoryProvider).indisponibilites(anneeId);
});

final seancesAnneeProvider = FutureProvider.autoDispose.family<List<EmploiDuTemps>, String>((ref, anneeId) {
  return ref.watch(configurationRepositoryProvider).seancesAnnee(anneeId);
});

/// Après une écriture : l'état de la mise en route et les listes sont relus.
/// Passer `ref.invalidate` (WidgetRef comme Ref).
void rafraichirConfiguration(
  void Function(ProviderOrFamily provider) invalider, {
  String? etablissementId,
  String? anneeId,
}) {
  if (etablissementId != null) invalider(etatConfigurationProvider(etablissementId));
  if (anneeId != null) {
    invalider(groupesProvider(anneeId));
    invalider(affectationsAnneeProvider(anneeId));
    invalider(grilleHoraireProvider(anneeId));
    invalider(indisponibilitesProvider(anneeId));
    invalider(seancesAnneeProvider(anneeId));
  }
}

// =================================================================== calcul

/// Tout ce qu'il faut pour calculer l'emploi du temps d'une année.
class EntreesCalcul {
  const EntreesCalcul({
    required this.grille,
    required this.classes,
    required this.affectations,
    required this.groupes,
    required this.indisponibilites,
    required this.seancesExistantes,
  });

  final GrilleHoraire grille;
  final List<Classe> classes;
  final List<AffectationCours> affectations;
  final List<GroupePedagogique> groupes;
  final List<Indisponibilite> indisponibilites;
  final List<EmploiDuTemps> seancesExistantes;

  /// Données du moteur. Les séances verrouillées restent à leur place.
  DonneesEmploi versDonnees({int graine = 42, Duration budget = const Duration(seconds: 8)}) {
    final nomsClasses = {for (final c in classes) c.id: c.nom};
    final nomsGroupes = {for (final g in groupes) g.id: g.nom};
    return DonneesEmploi(
      jours: [...grille.jours]..sort(),
      creneaux: [...grille.creneaux]..sort((a, b) => a.debutMinutes.compareTo(b.debutMinutes)),
      demiJourneesLibres: grille.demiJourneesLibres,
      regles: grille.regles,
      cours: [
        for (final a in affectations)
          if (nomsClasses.containsKey(a.classeId) && (a.heuresParSemaine ?? 0) > 0)
            CoursAPlacer(
              id: a.id,
              classeId: a.classeId,
              nomClasse: nomsClasses[a.classeId]!,
              groupeId: a.groupeId,
              nomGroupe: a.groupeId == null ? null : nomsGroupes[a.groupeId],
              enseignantId: a.enseignantId,
              nomEnseignant: a.nomEnseignant,
              matiereId: a.matiereId,
              nomMatiere: a.nomMatiere,
              salleId: a.salleId,
              minutesParSemaine: (a.heuresParSemaine ?? 0) * 60,
              dureeSeance: a.dureeSeance,
              coefficient: a.coefficient ?? 1,
            ),
      ],
      seancesFixes: [
        for (final s in seancesExistantes)
          if (s.verrouille)
            SeanceFixeEmploi(
              classeId: s.classeId,
              groupeId: s.groupeId,
              enseignantId: s.enseignantProfileId,
              salleId: s.salleId,
              jour: s.jourSemaine,
              debut: s.heureDebut,
              fin: s.heureFin,
            ),
      ],
      indisponibilites: [for (final i in indisponibilites) i.versMoteur()],
      graine: graine,
      budget: budget,
    );
  }
}

/// Calcul dans un isolat : l'écran reste fluide pendant le calcul.
Future<ResultatEmploi> calculerEmploiDuTemps(DonneesEmploi donnees) =>
    Isolate.run(() => MoteurEmploiDuTemps(donnees).resoudre());

/// Proposition calculée, gardée sur l'appareil jusqu'à son enregistrement
/// (calcul hors connexion, envoi au retour du réseau).
final storePropositionProvider = Provider<CacheDocumentStore>(
  (ref) => CacheDocumentStore(ref.watch(databaseProvider), 'configuration_hl'),
);
