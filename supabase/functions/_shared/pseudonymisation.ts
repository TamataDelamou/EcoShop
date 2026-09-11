// ============================================================================
// EcoShop — génération de pseudonymes PARTAGÉE (M16, Edge Functions IA)
//
// Porté depuis ecoshop_flutter/functions/pseudonymisation_helpers.js —
// fonction pure, aucun I/O, aucune modification de logique.
// ============================================================================

/**
 * "Élève A".."Élève Z", "Élève AA".."Élève AZ", ... — même principe que la
 * numérotation de colonnes d'un tableur, pour dépasser 26 sans ambiguïté.
 * Plafonné par l'appelant (voir `PLAFOND_DETAIL_NOMINATIF_RISQUE_ECHEC`).
 */
export function genererPseudonymes(n: number): string[] {
  const pseudonymes: string[] = [];
  for (let i = 0; i < n; i++) {
    let index = i;
    let lettres = "";
    do {
      lettres = String.fromCharCode(65 + (index % 26)) + lettres;
      index = Math.floor(index / 26) - 1;
    } while (index >= 0);
    pseudonymes.push(`Élève ${lettres}`);
  }
  return pseudonymes;
}
