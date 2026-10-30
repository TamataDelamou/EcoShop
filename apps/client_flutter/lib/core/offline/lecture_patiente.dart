/// Attente maximale du serveur quand une copie existe déjà sur l'appareil
/// (feuille de route hors connexion, lot 1 — « appareil d'abord »).
///
/// Au-delà, la copie du téléphone est affichée tout de suite et la réponse
/// du serveur, si elle arrive, est gardée en arrière-plan pour la prochaine
/// ouverture. Sans copie, l'écran attend le serveur comme avant (délai du
/// client HTTP : 20 s).
///
/// Repère : Linear sert sa copie locale sans attendre le réseau. La valeur
/// de 3 s est un premier réglage, à ajuster d'après les mesures faites sur
/// téléphone au pilote.
const delaiPatienceLecture = Duration(seconds: 3);

/// Copie gardée sur l'appareil et date de son enregistrement.
typedef CopieAppareil<T> = ({T valeur, DateTime date});

/// Résultat d'une lecture : la valeur affichée et, si elle vient de
/// l'appareil, la date de la copie (`null` : réponse fraîche du serveur).
typedef ResultatLecture<T> = ({T valeur, DateTime? depuisAppareil});

/// Lecture « serveur si rapide, appareil sinon ».
///
/// - Le serveur répond dans le délai [patience] : réponse gardée ([garder])
///   puis renvoyée.
/// - Le serveur tombe en panne ([estPanne]) : la copie de l'appareil est
///   servie ; sans copie, l'erreur remonte.
/// - Le serveur répond autre chose qu'une panne (refus, droits) : l'erreur
///   remonte, jamais masquée par la copie.
/// - Le serveur est lent et une copie existe : la copie est servie tout de
///   suite ; la réponse du serveur continue d'arriver et est gardée en
///   arrière-plan ([garder]), puis [apresActualisation] est appelé. Un refus
///   arrivé après coup n'est pas affiché : il le sera à la lecture suivante.
/// - Le serveur est lent et aucune copie n'existe : on attend le serveur.
///
/// Aucune erreur de l'actualisation en arrière-plan ne s'échappe (pas
/// d'erreur asynchrone non traitée).
Future<ResultatLecture<T>> lireAvecPatience<T>({
  required Future<T> Function() serveur,
  required Future<CopieAppareil<T>?> Function() appareil,
  required Future<void> Function(T valeur) garder,
  required bool Function(Object erreur) estPanne,
  Duration patience = delaiPatienceLecture,
  void Function()? apresActualisation,
}) async {
  // Future.sync : une exception levée avant le premier `await` de [serveur]
  // suit le même chemin qu'une erreur asynchrone.
  final enCours = Future.sync(serveur);

  // Garde toujours la réponse du serveur, même si l'écran a déjà affiché la
  // copie. La garde ne doit jamais faire échouer la lecture.
  var abandonne = false;
  final garde = enCours.then<void>((valeur) async {
    try {
      await garder(valeur);
    } catch (_) {
      // Le stockage local est un plus : son échec ne bloque rien.
    }
    if (abandonne) apresActualisation?.call();
  }, onError: (Object _) {});

  final Object? premier;
  try {
    premier = await enCours.then<Object?>((v) => _Recu<T>(v)).timeout(patience, onTimeout: () => _patienceEcoulee);
  } catch (e) {
    if (!estPanne(e)) rethrow;
    final copie = await _lireSansErreur(appareil);
    if (copie == null) rethrow;
    return (valeur: copie.valeur, depuisAppareil: copie.date);
  }

  if (premier is _Recu<T>) {
    await garde;
    return (valeur: premier.valeur, depuisAppareil: null);
  }

  // Serveur lent : la copie de l'appareil, s'il y en a une.
  final copie = await _lireSansErreur(appareil);
  if (copie != null) {
    abandonne = true;
    return (valeur: copie.valeur, depuisAppareil: copie.date);
  }

  // Pas de copie : on attend le serveur, comme avant le lot 1 ; une panne
  // ou un refus remonte tel quel (rien sur l'appareil pour le remplacer).
  final valeur = await enCours;
  await garde;
  return (valeur: valeur, depuisAppareil: null);
}

Future<CopieAppareil<T>?> _lireSansErreur<T>(Future<CopieAppareil<T>?> Function() appareil) async {
  try {
    return await appareil();
  } catch (_) {
    // Base locale illisible : comme s'il n'y avait pas de copie.
    return null;
  }
}

class _Recu<T> {
  const _Recu(this.valeur);
  final T valeur;
}

const Object _patienceEcoulee = Object();
