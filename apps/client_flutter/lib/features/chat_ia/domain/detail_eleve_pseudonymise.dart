/// Une entrée du mapping pseudonyme → identité réelle (couche 3, M16).
///
/// Reçue UNIQUEMENT en retour de `envoyer_message_ia`, jamais construite ni
/// devinée côté client, jamais renvoyée à Anthropic (voir
/// `_shared/grounding_risque_echec.ts` : `mappingComplet` reste strictement
/// serveur → client). Affichée seulement pour le persona Directeur-Adviser,
/// et gardée en mémoire locale seulement — jamais persistée dans
/// `ai_messages` (dont le contenu ne contient que le texte de l'IA, qui lui
/// n'emploie jamais que les pseudonymes).
class DetailElevePseudonymise {
  const DetailElevePseudonymise({
    required this.pseudonyme,
    required this.matricule,
    required this.nom,
    required this.prenom,
  });

  final String pseudonyme;
  final String matricule;
  final String nom;
  final String prenom;

  static List<DetailElevePseudonymise> depuisMapping(Map<String, dynamic>? mapping) {
    if (mapping == null || mapping.isEmpty) return const [];
    return mapping.entries.map((entree) {
      final valeur = entree.value as Map<String, dynamic>;
      return DetailElevePseudonymise(
        pseudonyme: entree.key,
        matricule: valeur['matricule'] as String,
        nom: valeur['nom'] as String,
        prenom: valeur['prenom'] as String,
      );
    }).toList(growable: false);
  }
}
