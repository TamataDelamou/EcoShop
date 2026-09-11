// ============================================================================
// EcoShop — client Anthropic brut PARTAGÉ (M16, Edge Functions IA)
//
// Porté depuis ecoshop_flutter/functions/anthropic_client.js — même
// discipline : PAS de @anthropic-ai/sdk (la structure content[]/tool_use/
// tool_result reste un JSON simple à un seul niveau, pas assez complexe
// pour justifier la dépendance), un seul point d'appel HTTP partagé par
// TOUTES les Edge Functions IA (jamais deux implémentations qui pourraient
// diverger).
//
// ⚠️ Modèle : "claude-sonnet-4-6" (la valeur codée en dur côté source) est
// un identifiant obsolète — jamais reporté ici tel quel. Le modèle par
// défaut ci-dessous est un identifiant Claude actuel ; `ANTHROPIC_MODEL`
// (secret Supabase) permet de le surcharger sans redéploiement si un
// modèle plus récent doit être utilisé en production.
//
// ⚠️ `ANTHROPIC_URL_OVERRIDE` (variable d'env, PAS un secret) : point
// d'extension UNIQUEMENT pour le développement/test local (`supabase
// functions serve`), permet de rediriger l'appel vers un faux serveur
// HTTP simulant l'API Anthropic — jamais utilisé/nécessaire en production
// (aucune clé API réelle requise pour ce sous-livrable, voir cadrage M16
// 3/7 point 5). Ignoré silencieusement si absent.
// ============================================================================

const ANTHROPIC_VERSION = "2023-06-01";
const ANTHROPIC_URL_DEFAUT = "https://api.anthropic.com/v1/messages";
export const ANTHROPIC_MODEL_DEFAUT = "claude-sonnet-5";

function resoudreUrlAnthropic(): string {
  return Deno.env.get("ANTHROPIC_URL_OVERRIDE") || ANTHROPIC_URL_DEFAUT;
}

export interface BlocContenu {
  type: string;
  text?: string;
  id?: string;
  name?: string;
  input?: Record<string, unknown>;
}

export interface ReponseAnthropic {
  content?: BlocContenu[];
  [cle: string]: unknown;
}

export interface OptionsAppelAnthropic {
  apiKey: string;
  systemPrompt: string;
  messages: unknown[];
  tools?: unknown[];
  maxTokens?: number;
  model?: string;
  /** Injectable pour les tests — remplace `fetch` global, jamais utilisé en production. */
  fetchImpl?: typeof fetch;
}

/**
 * Appel HTTP brut — retourne le JSON complet de la réponse (`content[]`
 * inclus, avec ses éventuels blocs `tool_use`).
 */
export async function appellerAnthropicApi(
  options: OptionsAppelAnthropic,
): Promise<ReponseAnthropic> {
  const { apiKey, systemPrompt, messages, tools, maxTokens = 1024, model, fetchImpl } = options;
  const executerFetch = fetchImpl ?? fetch;

  const response = await executerFetch(resoudreUrlAnthropic(), {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": ANTHROPIC_VERSION,
    },
    body: JSON.stringify({
      model: model ?? ANTHROPIC_MODEL_DEFAUT,
      max_tokens: maxTokens,
      system: systemPrompt,
      ...(tools ? { tools } : {}),
      messages,
    }),
  });

  if (!response.ok) {
    const errTxt = await response.text();
    console.error(JSON.stringify({
      fn: "anthropic_client",
      niveau: "error",
      message: "erreur API Anthropic",
      detail: errTxt,
    }));
    throw new Error("Erreur lors de l'appel à l'assistant IA.");
  }

  return response.json();
}

/**
 * Concatène tous les blocs `type: 'text'` de `content[]` — robuste à un
 * `tool_use` coexistant avec un bloc texte dans la même réponse (ex. un
 * commentaire avant l'appel d'outil), contrairement à un simple
 * `content?.[0]?.text` qui ne lirait que le premier bloc.
 */
export function extraireTexte(content: BlocContenu[] | undefined): string {
  return (content ?? [])
    .filter((bloc) => bloc.type === "text")
    .map((bloc) => bloc.text ?? "")
    .join("\n");
}

/** Tous les blocs `tool_use` d'une réponse (0 ou plusieurs, l'appelant décide quoi en faire). */
export function extraireBlocsToolUse(content: BlocContenu[] | undefined): BlocContenu[] {
  return (content ?? []).filter((bloc) => bloc.type === "tool_use");
}
