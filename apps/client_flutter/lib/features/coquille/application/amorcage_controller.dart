import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/amorcage.dart';
import '../../../core/offline/lecture_hors_ligne.dart' show estErreurReseau;
import '../../../core/offline/suivi_portees.dart';
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
/// l'ouverture ou au retour du réseau). Depuis le lot 3, un nouvel amorçage
/// ne relit que les portées modifiées : il coûte quelques requêtes.
const delaiReamorcage = Duration(minutes: 30);

/// Portées modifiées depuis leur dernière lecture (fonction serveur
/// `portees_modifiees`, lot 3). Remplaçable dans les tests.
typedef VerifierPortees = Future<Object?> Function(List<Map<String, String>> demandes);

final verifierPorteesProvider = Provider<VerifierPortees>((ref) {
  return (demandes) => ref.read(supabaseClientProvider).rpc('portees_modifiees', params: {'p_portees': demandes});
});

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

  /// [force] (bouton « Synchroniser maintenant », lot 5) : ni le délai de
  /// [delaiReamorcage], ni la préférence « Wi-Fi seulement » ne s'appliquent
  /// — l'utilisateur le demande explicitement.
  Future<void> lancerSiNecessaire({bool force = false}) async {
    if (!ref.read(estEnLigneProvider)) return;
    final espace = ref.read(espaceUtiliseProvider);
    final profil = ref.read(profilProvider).valueOrNull;
    final ecole = espace?.etablissementId;
    if (espace == null || profil == null || ecole == null) return;

    final cle = '${profil.id}|${espace.cle}';
    if (_enCoursPour == cle) return;

    final suivi = ref.read(_suiviAmorcageProvider);
    if (!force) {
      final wifiSeulement = await ref.read(wifiSeulementProvider.future).catchError((_) => false);
      final connexions = ref.read(connectivityProvider).valueOrNull;
      if (!peutAmorcerSur(connexions, wifiSeulement: wifiSeulement)) return;
      try {
        final dernier = await suivi.lireDocumentDate('termine', cle);
        if (dernier != null && DateTime.now().difference(dernier.misAJourLe) < delaiReamorcage) return;
      } catch (_) {
        // Suivi illisible : on amorce.
      }
    }

    final generation = ++_generation;
    _enCoursPour = cle;
    try {
      // Lot 3 : ce qui a changé depuis la dernière lecture.
      var suiviPortees = SuiviPortees.vide;
      try {
        suiviPortees = SuiviPortees.depuisJson(await suivi.lireDocument('portees', cle));
      } catch (_) {
        // Suivi illisible : tout sera relu.
      }
      final maintenantLocal = DateTime.now();
      DateTime? luLe;
      var inchangees = const <String>{};
      try {
        final reponse = lireReponsePortees(await ref.read(verifierPorteesProvider)(suiviPortees.demandes(maintenantLocal)));
        luLe = reponse.maintenant;
        if (luLe != null) {
          inchangees = suiviPortees.inchangees(modifiees: reponse.modifiees, maintenant: maintenantLocal);
        }
      } catch (e) {
        // Sans réseau : inutile d'aller plus loin. Fonction absente du
        // serveur (pas encore déployée) : tout est relu, comme au lot 2.
        if (estErreurReseau(e)) return;
      }

      final vues = <String>{};
      final echouees = <String>{};
      final relues = <String>{};
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
        ignorer: (tache) {
          final p = tache.portee;
          if (p == null) return false;
          vues.add(p);
          return inchangees.contains(p);
        },
        apres: (tache, reussie) {
          final p = tache.portee;
          if (p == null) return;
          (reussie ? relues : echouees).add(p);
        },
      );
      if (fin.issue == IssueAmorcage.termine) {
        ref.invalidate(derniereAmorcageProvider);
        try {
          await suivi.ecrireDocument('termine', cle, {'refusees': fin.refusees, 'inchangees': fin.inchangees});
          // Une portée n'est notée lue que si toutes ses lectures ont réussi.
          if (luLe != null) {
            final nouveau = suiviPortees.apres(relues: relues.difference(echouees), vues: vues, luLe: luLe);
            await suivi.ecrireDocument('portees', cle, nouveau.versJson());
          }
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

/// Lot 5 : l'amorçage automatique attend-il le Wi-Fi ? Une connexion
/// inconnue (module réseau muet) ne bloque jamais : on ne sait pas, on
/// amorce. Le Wi-Fi seul est accepté, l'Ethernet aussi (tablette sur socle).
bool peutAmorcerSur(List<ConnectivityResult>? connexions, {required bool wifiSeulement}) {
  if (!wifiSeulement || connexions == null) return true;
  return connexions.contains(ConnectivityResult.wifi) || connexions.contains(ConnectivityResult.ethernet);
}

final _preferencesAppareilProvider = Provider<CacheDocumentStore>(
  (ref) => CacheDocumentStore(ref.watch(databaseProvider), 'preferences'),
);

/// Préférence de l'appareil « Préparer le hors connexion en Wi-Fi
/// seulement » (lot 5) — par défaut non : en Guinée, beaucoup d'écoles n'ont
/// que les données mobiles, et le lot 3 rend une mise à jour très légère.
class WifiSeulementController extends AsyncNotifier<bool> {
  static const _type = 'amorcage_wifi_seulement';

  @override
  Future<bool> build() async {
    try {
      final doc = await ref.read(_preferencesAppareilProvider).lireDocument(_type, 'appareil');
      return doc?['actif'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> definir(bool actif) async {
    state = AsyncData(actif);
    try {
      await ref.read(_preferencesAppareilProvider).ecrireDocument(_type, 'appareil', {'actif': actif});
    } catch (_) {
      // Préférence non gardée : elle vaut pour cette ouverture.
    }
  }
}

final wifiSeulementProvider = AsyncNotifierProvider<WifiSeulementController, bool>(WifiSeulementController.new);

/// Date de la dernière préparation complète de l'espace utilisé (lot 5).
final derniereAmorcageProvider = FutureProvider<DateTime?>((ref) async {
  final espace = ref.watch(espaceUtiliseProvider);
  final profil = ref.watch(profilProvider).valueOrNull;
  if (espace == null || profil == null) return null;
  try {
    final doc = await ref.read(_suiviAmorcageProvider).lireDocumentDate('termine', '${profil.id}|${espace.cle}');
    return doc?.misAJourLe;
  } catch (_) {
    return null;
  }
});
