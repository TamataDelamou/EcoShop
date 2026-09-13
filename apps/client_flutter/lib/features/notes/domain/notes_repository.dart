import 'appreciation.dart';
import 'bulletin.dart';
import 'classement_eleve.dart';
import 'enums_notes.dart';
import 'evaluation.dart';
import 'note.dart';

/// Erreur métier de Notes & Évaluations, à code stable.
class ErreurNotes implements Exception {
  const ErreurNotes(this.code, [this.detail]);

  final String code;
  final String? detail;

  @override
  String toString() => 'ErreurNotes($code)';
}

/// Port du module Notes & Évaluations (M6).
///
/// Règle d'or (contrat M06 §5) : **aucune moyenne n'est calculée côté
/// client** — [moyenneEleve] et [moyenneClasse] délèguent systématiquement
/// aux RPC serveur `calculer_moyenne_*`. La seule écriture tolérée hors
/// connexion est [saisirNote] (file `sync_queue`, LWW par `device_id`).
abstract interface class NotesRepository {
  /// Évaluations d'une classe (personnel, ou enseignant affecté), triées par
  /// date décroissante.
  Future<List<Evaluation>> evaluationsDeClasse(String classeId, {String? periodeId});

  /// Notes d'une évaluation (fiche embarquée) — grille de saisie enseignant.
  Future<List<Note>> notesDeEvaluation(String evaluationId);

  /// Notes d'une fiche (évaluation embarquée), pour le carnet élève/parent.
  Future<List<Note>> notesDeFiche(String ficheEleveId, {String? periodeId});

  /// Moyenne pondérée d'un élève, ramenée sur 20 (RPC `calculer_moyenne_eleve`).
  Future<double?> moyenneEleve(String ficheEleveId, {String? programmeMatiereId, String? periodeId});

  /// Moyenne d'une classe, moyenne des moyennes élèves (RPC `calculer_moyenne_classe`).
  Future<double?> moyenneClasse(String classeId, {String? programmeMatiereId, String? periodeId});

  /// Appréciations d'une fiche pour une période.
  Future<List<Appreciation>> appreciationsDeFiche(String ficheEleveId, {String? periodeId});

  /// Bulletins publiés d'une fiche.
  Future<List<Bulletin>> bulletinsDeFiche(String ficheEleveId);

  /// Classement d'une classe (moyenne + rang de chaque élève inscrit), RPC
  /// serveur `classer_eleves_classe` (D5) — même règle d'or que [moyenneEleve]
  /// : aucun classement n'est calculé côté client.
  Future<List<ClassementEleve>> classerElevesClasse(
    String classeId, {
    String? programmeMatiereId,
    String? periodeId,
  });

  /// Génère (ou régénère) les bulletins de toute une classe pour une période
  /// donnée (D5, cahier §12.4) : recopie tel quel le classement déjà calculé
  /// côté serveur ([classerElevesClasse]) dans un bulletin par élève,
  /// aussitôt publié (voir docstring de l'implémentation Supabase pour le
  /// choix de publication immédiate). Idempotent : régénérer écrase le
  /// bulletin existant de la même fiche/période.
  Future<List<Bulletin>> genererBulletinsClasse({
    required String classeId,
    required String etablissementId,
    required String anneeScolaireId,
    String? periodeId,
    TypeBulletin type,
  });

  /// Crée une évaluation (enseignant affecté ou permission scolarité).
  Future<Evaluation> creerEvaluation(Evaluation evaluation);

  /// Publie une évaluation (rend les notes visibles élève/parent).
  Future<void> publierEvaluation(String evaluationId);

  /// Saisit ou corrige une note. Fonctionne hors connexion : si l'écriture
  /// réseau échoue pour une raison non bloquante (pas de réseau), la note est
  /// enfilée dans `sync_queue` et rejouée à la reconnexion. Renvoie `true` si
  /// la note a été synchronisée immédiatement, `false` si elle a été mise en
  /// file d'attente.
  Future<bool> saisirNote(Note note);
}
