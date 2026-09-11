// ============================================================================
// EcoShop — grounding « risque d'échec », couche 3 (M16, Edge Functions IA)
//
// Porté depuis ecoshop_flutter/functions/ai_chat_grounding_helpers.js —
// même discipline de pseudonymisation. La SQL (`obtenir_detail_risque_
// echec_interne`) fait tout le travail d'autorisation (propriété de la
// conversation, grounding actif, rôle direction re-vérifié) et retourne
// les données RÉELLES (nom/matricule) — ce module ne fait QUE la
// pseudonymisation, jamais l'autorisation.
// ============================================================================

import { genererPseudonymes } from "./pseudonymisation.ts";

export const PLAFOND_DETAIL_NOMINATIF_RISQUE_ECHEC = 60;

export interface EleveARisqueBrut {
  fiche_id: string;
  matricule: string;
  nom: string;
  prenom: string;
  classe_id: string | null;
  score: number;
}

export interface EntreePseudonymisee {
  pseudonyme: string;
  risqueEchecActuel: number;
}

export interface PayloadPseudonymise {
  payloadAnthropic: EntreePseudonymisee[];
  mappingComplet: Record<string, { matricule: string; nom: string; prenom: string; classeId: string | null }>;
  troncature: number;
}

/**
 * Tri déterministe par matricule (jamais par risque décroissant — la seule
 * POSITION du pseudonyme ne doit jamais révéler un classement implicite),
 * plafonné, puis séparation STRICTE — chaque entrée de `payloadAnthropic`
 * est un objet LITTÉRAL construit à la main, jamais un spread `{...eleve}`
 * qui recopierait `nom`/`prenom`/`matricule` par inadvertance. Il n'existe
 * donc structurellement aucun chemin de code où un champ nominatif
 * pourrait atterrir dans `payloadAnthropic`.
 */
export function construirePayloadPseudonymise(elevesARisque: EleveARisqueBrut[]): PayloadPseudonymise {
  const tries = [...elevesARisque].sort((a, b) => a.matricule.localeCompare(b.matricule));
  const limites = tries.slice(0, PLAFOND_DETAIL_NOMINATIF_RISQUE_ECHEC);
  const pseudonymes = genererPseudonymes(limites.length);

  const mappingComplet: PayloadPseudonymise["mappingComplet"] = {};
  const payloadAnthropic: EntreePseudonymisee[] = [];

  limites.forEach((eleve, i) => {
    const pseudo = pseudonymes[i];
    mappingComplet[pseudo] = {
      matricule: eleve.matricule,
      nom: eleve.nom,
      prenom: eleve.prenom,
      classeId: eleve.classe_id,
    };
    payloadAnthropic.push({
      pseudonyme: pseudo,
      risqueEchecActuel: eleve.score,
    });
  });

  return {
    payloadAnthropic,
    mappingComplet,
    troncature: tries.length > limites.length ? tries.length - limites.length : 0,
  };
}
