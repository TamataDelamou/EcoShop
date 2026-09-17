import 'eleve_mention.dart';

/// Erreur métier ou réseau du port [ProclamationRepository]. Codes serveur
/// attendus : `PERMISSION_REFUSEE`, `CLASSE_NON_EXAMEN`,
/// `CLASSE_DEJA_PROCLAMEE`, `MENTION_MANQUANTE`.
class ErreurProclamation implements Exception {
  const ErreurProclamation(this.code, [this.detail]);

  final String code;
  final String? detail;

  @override
  String toString() => 'ErreurProclamation($code)';
}

/// Port du verrou définitif des notes + mention finale admis(e)/recalé(e)
/// pour les classes d'examen (cahier §12.3, §12.4, §7.3). Réservé à la
/// Direction (garantie serveur, pas seulement cet écran) ; sans exception
/// pour l'Administrateur GSG une fois la classe proclamée — verrou total.
abstract interface class ProclamationRepository {
  /// Vrai si la classe hérite du statut « classe d'examen » de son niveau.
  Future<bool> classeEstExamen(String classeId);

  /// Vrai si la classe a déjà été proclamée pour cette année scolaire.
  Future<bool> classeEstProclamee({
    required String classeId,
    required String anneeScolaireId,
  });

  /// Élèves activement inscrits dans la classe, avec leur mention finale
  /// éventuelle.
  Future<List<EleveMention>> elevesDeClasse(String classeId);

  /// Définit la mention finale d'un élève de classe d'examen. Refusée hors
  /// classe d'examen ou une fois la classe proclamée.
  Future<void> definirMentionFinale({
    required String inscriptionId,
    required String mention,
  });

  /// Proclame la classe pour l'année scolaire — verrouillage définitif,
  /// aucune annulation possible. Pour une classe d'examen, exige que chaque
  /// élève actif porte déjà une mention (`MENTION_MANQUANTE` sinon).
  Future<void> proclamerClasse({
    required String classeId,
    required String anneeScolaireId,
  });
}
