/// Moteur de synchronisation hors-ligne — pattern outbox (cahier v4.1, ch. 34-35).
///
/// Toute écriture locale est journalisée dans une file de synchronisation puis
/// rejouée vers Supabase au retour du réseau, avec backoff exponentiel et
/// plafonnement des tentatives.
///
/// Une erreur de réseau laisse l'entrée en file (nouvel essai plus tard). Un
/// REFUS MÉTIER du serveur ([RejetDefinitif] : période clôturée entre-temps,
/// droits retirés…) ne se corrigera pas en réessayant : l'entrée passe en
/// « rejetée », n'est plus rejouée, et l'utilisateur la voit avec la raison
/// (bonne pratique des caisses hors ligne : file de régularisation plutôt que
/// réessais sans fin).
library;

/// Statut de vie d'une entrée de la file de synchronisation.
enum SyncStatut { enAttente, enCours, termine, echec, rejete }

extension SyncStatutCode on SyncStatut {
  String get code => switch (this) {
        SyncStatut.enAttente => 'en_attente',
        SyncStatut.enCours => 'en_cours',
        SyncStatut.termine => 'termine',
        SyncStatut.echec => 'echec',
        SyncStatut.rejete => 'rejete',
      };

  static SyncStatut? depuisCode(String? code) {
    for (final statut in SyncStatut.values) {
      if (statut.code == code) return statut;
    }
    return null;
  }
}

/// Refus métier définitif d'une écriture rejouée : inutile de réessayer.
class RejetDefinitif implements Exception {
  const RejetDefinitif(this.code, this.message);

  /// Code serveur (ex. `PERIODE_CLOTUREE`).
  final String code;

  /// Explication lisible par l'utilisateur.
  final String message;

  @override
  String toString() => 'RejetDefinitif($code)';
}

/// Entrée de la file outbox (une écriture locale à rejouer).
class SyncEntree {
  const SyncEntree({
    required this.id,
    required this.entite,
    required this.operation,
    required this.payload,
    this.tentatives = 0,
    this.statut = SyncStatut.enAttente,
  });

  final String id;

  /// Entité métier concernée (ex. `notes`, `presences`, `paiements`).
  final String entite;

  /// Opération à rejouer : `insert`, `update` ou `delete`.
  final String operation;

  /// Corps de l'opération (JSON sérialisé).
  final String payload;

  /// Nombre de tentatives déjà effectuées.
  final int tentatives;

  final SyncStatut statut;

  SyncEntree copierAvec({int? tentatives, SyncStatut? statut}) => SyncEntree(
        id: id,
        entite: entite,
        operation: operation,
        payload: payload,
        tentatives: tentatives ?? this.tentatives,
        statut: statut ?? this.statut,
      );
}

/// Port de persistance de la file (implémenté par Drift en production).
abstract interface class SyncRepository {
  /// Entrées à traiter, dans l'ordre de création.
  Future<List<SyncEntree>> entreesEnAttente();

  /// Met à jour le statut et le compteur de tentatives d'une entrée.
  Future<void> marquer(SyncEntree entree);
}

/// Moteur de synchronisation.
class SyncEngine {
  SyncEngine({
    required this.repository,
    required this.estConnecte,
    required this.rejouer,
    this.surRejet,
    this.maxTentatives = 5,
    this.delaiBase = const Duration(seconds: 2),
    this.delaiMax = const Duration(minutes: 5),
  });

  final SyncRepository repository;
  final Future<bool> Function() estConnecte;
  final Future<void> Function(SyncEntree entree) rejouer;

  /// Appelé quand le serveur refuse définitivement une entrée (journal des
  /// refus présenté à l'utilisateur).
  final Future<void> Function(SyncEntree entree, RejetDefinitif rejet)? surRejet;
  final int maxTentatives;
  final Duration delaiBase;
  final Duration delaiMax;

  /// Délai d'attente avant une nouvelle tentative (backoff exponentiel plafonné).
  Duration delaiReessai(int tentatives) {
    final exposant = tentatives < 0 ? 0 : (tentatives > 31 ? 31 : tentatives);
    final ms = delaiBase.inMilliseconds * (1 << exposant);
    final plafonne = ms > delaiMax.inMilliseconds ? delaiMax.inMilliseconds : ms;
    return Duration(milliseconds: plafonne);
  }

  /// Rejoue les entrées en attente ; renvoie le nombre d'entrées traitées.
  Future<int> synchroniser() async {
    if (!await estConnecte()) return 0;

    final entrees = await repository.entreesEnAttente();
    var traitees = 0;

    for (final entree in entrees) {
      final prochainesTentatives = entree.tentatives + 1;

      if (entree.tentatives >= maxTentatives) {
        await repository.marquer(entree.copierAvec(statut: SyncStatut.echec));
        continue;
      }

      await repository.marquer(
        entree.copierAvec(
          tentatives: prochainesTentatives,
          statut: SyncStatut.enCours,
        ),
      );

      try {
        await rejouer(entree);
        await repository.marquer(
          entree.copierAvec(
            tentatives: prochainesTentatives,
            statut: SyncStatut.termine,
          ),
        );
        traitees++;
      } on RejetDefinitif catch (rejet) {
        await repository.marquer(
          entree.copierAvec(
            tentatives: prochainesTentatives,
            statut: SyncStatut.rejete,
          ),
        );
        await surRejet?.call(entree, rejet);
      } catch (_) {
        await repository.marquer(
          entree.copierAvec(
            tentatives: prochainesTentatives,
            statut: SyncStatut.echec,
          ),
        );
      }
    }

    return traitees;
  }
}
