import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/amorcage.dart';
import '../../../core/providers.dart';
import '../../annonces/application/annonces_providers.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/application/espace_providers.dart';
import '../../cahier_liaison/application/cahier_liaison_providers.dart';
import '../../notes/application/notes_providers.dart';
import '../../planification/application/planification_providers.dart';
import '../../rh_personnel/application/rh_providers.dart';
import '../../scolarite/application/scolarite_providers.dart';
import '../../vie_scolaire/application/vie_scolaire_providers.dart';
import 'plan_amorcage.dart';

/// Délai au-delà duquel un espace déjà amorcé l'est de nouveau (à
/// l'ouverture ou au retour du réseau). En attendant la synchronisation par
/// différences (lot 3), un nouvel amorçage relit tout : on l'espace donc.
const delaiReamorcage = Duration(hours: 6);

/// Branche les lectures de l'amorçage sur les dépôts existants (chacun
/// garde sa réponse sur l'appareil).
SourcesAmorcage sourcesAmorcage(Ref ref) {
  final scolarite = ref.read(scolariteRepositoryProvider);
  final notes = ref.read(notesRepositoryProvider);
  final planification = ref.read(planificationRepositoryProvider);
  final vieScolaire = ref.read(vieScolaireRepositoryProvider);
  final rh = ref.read(rhRepositoryProvider);
  final annonces = ref.read(annoncesRepositoryProvider);
  final cahier = ref.read(cahierLiaisonRepositoryProvider);
  return SourcesAmorcage(
    structure: (etablissementId) async {
      final st = await scolarite.structureEtablissement(etablissementId);
      return (
        anneeId: st.anneeCourante?.id,
        classes: [
          for (final c in st.classes)
            if (c.actif) (id: c.id, nom: c.nom),
        ],
      );
    },
    inscriptionsDeClasse: scolarite.inscriptionsDeClasse,
    affectationsDeClasse: scolarite.affectationsDeClasse,
    emploisDeClasse: planification.emploisDeClasse,
    evaluationsDeClasse: (classeId) => notes.evaluationsDeClasse(classeId),
    mesAffectations: (etablissementId) async => [
      for (final a in await scolarite.mesAffectations())
        if (a.etablissementId == etablissementId) a.classeId,
    ],
    emploisDeEnseignant: planification.emploisDeEnseignant,
    mesEnfants: (etablissementId) async => [
      for (final r in await scolarite.mesEnfants())
        if (r.estActive && r.etablissementId == etablissementId) r.ficheEleveId,
    ],
    maFiche: () async => (await scolarite.maFiche())?.id,
    classeActuelleDeFiche: (ficheId) async {
      final inscriptions = await scolarite.inscriptionsDeFiche(ficheId);
      return inscriptions.isEmpty ? null : inscriptions.first.classeId;
    },
    notesDeFiche: (ficheId) => notes.notesDeFiche(ficheId),
    bulletinsDeFiche: notes.bulletinsDeFiche,
    presencesDeFiche: vieScolaire.presencesDeFiche,
    retardsDeFiche: vieScolaire.retardsDeFiche,
    sanctionsDeFiche: vieScolaire.sanctionsDeFiche,
    cahierDeFiche: cahier.cahier,
    annonces: annonces.mesAnnonces,
    personnel: rh.employesEtablissement,
    encaissementsRecents: (etablissementId) => scolarite.encaissementsRecents(etablissementId),
    fraisScolarite: (etablissementId, anneeId) =>
        scolarite.fraisScolariteConfig(etablissementId: etablissementId, anneeScolaireId: anneeId),
    agendaEtablissement: planification.evenementsEtablissement,
  );
}

final _suiviAmorcageProvider = Provider<CacheDocumentStore>(
  (ref) => CacheDocumentStore(ref.watch(databaseProvider), 'amorcage_suivi'),
);

/// Amorçage de l'espace utilisé (REG-35, lot 2).
///
/// Lancé par la coquille à l'ouverture, au changement d'espace et au retour
/// du réseau ; ne fait rien hors connexion, sans école, ou si l'espace a été
/// amorcé il y a moins de [delaiReamorcage]. Un changement d'espace ou de
/// compte pendant l'amorçage l'arrête.
class AmorcageController extends Notifier<EtatAmorcage> {
  int _generation = 0;
  String? _enCoursPour;

  @override
  EtatAmorcage build() => const EtatAmorcage();

  Future<void> lancerSiNecessaire() async {
    if (!ref.read(estEnLigneProvider)) return;
    final espace = ref.read(espaceUtiliseProvider);
    final profil = ref.read(profilProvider).valueOrNull;
    final ecole = espace?.etablissementId;
    if (espace == null || profil == null || ecole == null) return;

    final cle = '${profil.id}|${espace.cle}';
    if (_enCoursPour == cle) return;

    final suivi = ref.read(_suiviAmorcageProvider);
    try {
      final dernier = await suivi.lireDocumentDate('termine', cle);
      if (dernier != null && DateTime.now().difference(dernier.misAJourLe) < delaiReamorcage) return;
    } catch (_) {
      // Suivi illisible : on amorce.
    }

    final generation = ++_generation;
    _enCoursPour = cle;
    try {
      final fin = await executerAmorcage(
        planAmorcage(
          role: espace.role,
          etablissementId: ecole,
          profileId: profil.id,
          sources: sourcesAmorcage(ref),
        ),
        continuer: () =>
            generation == _generation &&
            ref.read(profilProvider).valueOrNull?.id == profil.id &&
            ref.read(espaceUtiliseProvider)?.cle == espace.cle,
        progres: (etat) {
          if (generation == _generation) state = etat;
        },
      );
      if (fin.issue == IssueAmorcage.termine) {
        try {
          await suivi.ecrireDocument('termine', cle, {'refusees': fin.refusees});
        } catch (_) {
          // Le suivi est un plus : il évite seulement de relire trop souvent.
        }
      }
    } finally {
      if (generation == _generation) _enCoursPour = null;
    }
  }

  /// Arrête l'amorçage en cours (déconnexion).
  void arreter() {
    _generation++;
    _enCoursPour = null;
    state = const EtatAmorcage();
  }
}

final amorcageProvider = NotifierProvider<AmorcageController, EtatAmorcage>(AmorcageController.new);
