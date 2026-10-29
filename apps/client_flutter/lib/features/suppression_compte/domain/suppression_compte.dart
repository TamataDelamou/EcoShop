/// Suppression du compte par l'utilisateur (REG-31) : demande, délai de
/// réflexion de 7 jours, annulation. Le serveur anonymise le compte à
/// l'échéance (`effectuer_suppressions_comptes`).
library;

/// Délai pendant lequel l'utilisateur peut changer d'avis.
const delaiReflexionSuppression = Duration(days: 7);

class EtatSuppressionCompte {
  const EtatSuppressionCompte({required this.demandee, this.effectiveLe});

  const EtatSuppressionCompte.aucune() : this(demandee: false);

  final bool demandee;

  /// Date à laquelle le compte sera effacé.
  final DateTime? effectiveLe;

  factory EtatSuppressionCompte.depuisJson(Map<String, dynamic> json) => EtatSuppressionCompte(
        demandee: json['demandee'] == true,
        effectiveLe: json['effective_le'] == null ? null : DateTime.parse(json['effective_le'] as String).toLocal(),
      );
}

/// Réponse à une demande de suppression.
sealed class ReponseSuppression {
  const ReponseSuppression();

  factory ReponseSuppression.depuisJson(Map<String, dynamic> json) {
    if (json['erreur'] == 'DIRECTION_SEULE') {
      final ecoles = (json['ecoles'] as List? ?? const [])
          .map((e) => (e as Map)['nom']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
      return DirectionSeule(ecoles);
    }
    return SuppressionProgrammee(DateTime.parse(json['effective_le'] as String).toLocal());
  }
}

/// Demande enregistrée : le compte sera effacé à [effectiveLe].
class SuppressionProgrammee extends ReponseSuppression {
  const SuppressionProgrammee(this.effectiveLe);

  final DateTime effectiveLe;
}

/// Refus : l'utilisateur est la seule direction de ces écoles.
class DirectionSeule extends ReponseSuppression {
  const DirectionSeule(this.ecoles);

  final List<String> ecoles;
}

abstract interface class SuppressionCompteRepository {
  Future<EtatSuppressionCompte> etat();

  Future<ReponseSuppression> demander({String? motif});

  /// Vrai si une demande en attente a été annulée.
  Future<bool> annuler();
}
