import '../../../core/auth/role_racine.dart';

/// Persona IA affiché côté client (M16, sous-livrable 3/7) — purement
/// cosmétique pour le choix du titre/de l'icône d'écran. Le rôle RÉEL est
/// toujours re-dérivé côté serveur par `determiner_role_ia` (Edge Functions
/// `envoyer_message_ia`/`demarrer_analyse_risque_echec`) : ce que le client
/// affiche ici n'est jamais transmis ni approuvé sur cette seule foi.
enum PersonaIa {
  eleve('Tuteur-IA'),
  enseignant('Prof-Assistant'),
  direction('Directeur-Adviser');

  const PersonaIa(this.libelle);

  /// Nom affiché de l'assistant — cohérent avec `libelleAssistantPour` côté
  /// serveur (`_shared/prompts.ts`).
  final String libelle;

  /// Seuls ces 3 rôles racine ont un persona IA (M16 étend volontairement
  /// le périmètre du cahier — 5 rôles listés — à Prof-Assistant, coût
  /// marginal nul sur une infra déjà partagée ; voir le rapport d'écart).
  static PersonaIa? depuisRoleRacine(RoleRacine? role) => switch (role) {
        RoleRacine.eleve => PersonaIa.eleve,
        RoleRacine.enseignant => PersonaIa.enseignant,
        RoleRacine.direction => PersonaIa.direction,
        _ => null,
      };
}
