import 'dart:async';
import 'dart:collection';

import 'lecture_hors_ligne.dart' show estErreurReseau;

/// Amorçage hors connexion (REG-35, lot 2) : à la connexion et à chaque
/// changement d'espace, l'application lit d'avance ce que le rôle consulte
/// le plus, pour que ces écrans s'ouvrent ensuite sans réseau.
///
/// Inspiré du « bootstrap » de Linear (données marquées « au démarrage »,
/// les autres chargées à la demande) et du téléchargement initial des
/// applications de terrain (DHIS2, CommCare). Ici, chaque tâche appelle un
/// dépôt existant, qui garde déjà sa réponse sur l'appareil : l'amorçage ne
/// crée aucun nouveau format de copie.
///
/// Une tâche peut en produire d'autres (la liste des classes donne une tâche
/// par classe). Les tâches tournent par petits paquets ([parallele]) pour ne
/// pas saturer un réseau mobile ; après [pannesMax] pannes de réseau de
/// suite, l'amorçage s'arrête et sera repris à la prochaine connexion.
class TacheAmorcage {
  const TacheAmorcage(this.libelle, this.executer);

  /// Ce qui est lu, pour le journal (« Élèves de 6e A »).
  final String libelle;

  /// Lit la donnée (et la garde, via le dépôt) ; renvoie les tâches qui en
  /// découlent.
  final Future<List<TacheAmorcage>> Function() executer;

  /// Tâche simple, sans suite.
  static TacheAmorcage lire(String libelle, Future<Object?> Function() lecture) =>
      TacheAmorcage(libelle, () async {
        await lecture();
        return const [];
      });
}

/// Fin d'un amorçage.
enum IssueAmorcage {
  /// Toutes les tâches ont été tentées (certaines ont pu être refusées).
  termine,

  /// Arrêté faute de réseau : à reprendre.
  interrompu,

  /// Arrêté parce que la session ou l'espace a changé.
  annule,
}

/// Avancement, pour la barre de progression.
class EtatAmorcage {
  const EtatAmorcage({
    this.enCours = false,
    this.faites = 0,
    this.total = 0,
    this.refusees = 0,
    this.issue,
  });

  final bool enCours;

  /// Tâches terminées (réussies ou refusées).
  final int faites;

  /// Tâches connues à ce stade (le total grandit quand une tâche en produit
  /// d'autres).
  final int total;

  /// Tâches refusées par le serveur (droits, donnée absente) : ignorées.
  final int refusees;

  final IssueAmorcage? issue;

  double? get progression => total == 0 ? null : faites / total;

  EtatAmorcage copierAvec({bool? enCours, int? faites, int? total, int? refusees, IssueAmorcage? issue}) =>
      EtatAmorcage(
        enCours: enCours ?? this.enCours,
        faites: faites ?? this.faites,
        total: total ?? this.total,
        refusees: refusees ?? this.refusees,
        issue: issue ?? this.issue,
      );
}

/// Exécute une liste de tâches d'amorçage.
///
/// [continuer] est consulté avant chaque tâche : faux (déconnexion,
/// changement d'espace) → arrêt [IssueAmorcage.annule]. [progres] reçoit
/// l'état après chaque tâche.
Future<EtatAmorcage> executerAmorcage(
  List<TacheAmorcage> taches, {
  int parallele = 4,
  int pannesMax = 3,
  bool Function()? continuer,
  void Function(EtatAmorcage etat)? progres,
  bool Function(Object erreur) estPanne = estErreurReseau,
}) async {
  final file = Queue<({TacheAmorcage tache, int pannes})>.of([for (final t in taches) (tache: t, pannes: 0)]);
  var etat = EtatAmorcage(enCours: true, total: taches.length);
  var pannesDeSuite = 0;
  IssueAmorcage? arret;

  void publier(EtatAmorcage nouvel) {
    etat = nouvel;
    progres?.call(etat);
  }

  progres?.call(etat);

  Future<void> ouvrier() async {
    while (arret == null && file.isNotEmpty) {
      if (continuer != null && !continuer()) {
        arret = IssueAmorcage.annule;
        return;
      }
      final (:tache, :pannes) = file.removeFirst();
      try {
        final suites = await tache.executer();
        pannesDeSuite = 0;
        file.addAll([for (final t in suites) (tache: t, pannes: 0)]);
        publier(etat.copierAvec(faites: etat.faites + 1, total: etat.total + suites.length));
      } catch (e) {
        if (estPanne(e) && pannes + 1 < pannesMax) {
          pannesDeSuite++;
          // Remise en fin de file : retentée après les autres.
          file.addLast((tache: tache, pannes: pannes + 1));
          if (pannesDeSuite >= pannesMax) {
            arret ??= IssueAmorcage.interrompu;
            return;
          }
        } else if (estPanne(e)) {
          // Toujours en panne après [pannesMax] essais : abandonnée pour
          // cette fois (lue à la demande plus tard), comptée à part.
          pannesDeSuite++;
          publier(etat.copierAvec(faites: etat.faites + 1, refusees: etat.refusees + 1));
          if (pannesDeSuite >= pannesMax) {
            arret ??= IssueAmorcage.interrompu;
            return;
          }
        } else {
          publier(etat.copierAvec(faites: etat.faites + 1, refusees: etat.refusees + 1));
        }
      }
    }
  }

  // Les ouvriers piochent dans la même file : quand une tâche ajoute des
  // suites, un ouvrier inoccupé ne les verrait pas s'il était déjà sorti —
  // on relance donc des tournées tant que la file n'est pas vide.
  while (arret == null && file.isNotEmpty) {
    await Future.wait([for (var i = 0; i < parallele; i++) ouvrier()]);
  }

  final fin = etat.copierAvec(enCours: false, issue: arret ?? IssueAmorcage.termine);
  publier(fin);
  return fin;
}
