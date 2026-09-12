export '../../chat_ia/domain/chat_ia_repository.dart' show ErreurChatIa;

/// Résultat du démarrage d'un scan (Edge Function `demarrer_scan_exercice`,
/// M16 sous-livrable 5/7). Les tours de guidage suivants réutilisent
/// intégralement `ChatIaRepository.envoyerMessage`/`enregistrerMessage` —
/// voir l'en-tête de la migration `20260906001509` : ce port ne couvre que
/// le premier tour, spécifique au scan.
class ReponseScanExercice {
  const ReponseScanExercice({
    required this.conversationId,
    required this.matiere,
    required this.chapitre,
    required this.reply,
  });

  final String conversationId;
  final String? matiere;
  final String? chapitre;
  final String reply;
}

/// Port du scan et de la résolution guidée d'exercice (M16, sous-livrable
/// 5/7, cahier §21.5). N'accepte JAMAIS une photo — uniquement le texte déjà
/// reconnu sur l'appareil (ML Kit, embarqué) : voir l'en-tête de la migration
/// `20260906001509`, la photo elle-même ne quitte jamais l'appareil.
abstract interface class ScanExerciceRepository {
  /// Démarre un nouveau scan : crée la conversation + la ligne
  /// `scan_exercices` côté serveur, obtient l'identification matière/
  /// chapitre et le premier message de guidage. [consentement] doit être
  /// explicitement vrai — capturé à CHAQUE scan, jamais un verrou
  /// persistant (contrairement à Parent IA, voir la même migration).
  Future<ReponseScanExercice> demarrerScan({
    required String etablissementId,
    required String ficheEleveId,
    required String texteExtrait,
    required bool consentement,
  });
}
