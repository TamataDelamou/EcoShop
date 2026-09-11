// ============================================================================
// EcoShop — client Supabase PARTAGÉ pour les Edge Functions IA (M16)
//
// Crée un client qui FORWARD le JWT de l'appelant (jamais la clé
// service_role) — RLS/`auth.uid()` s'appliquent donc normalement, exactement
// comme si l'appel venait du client Flutter lui-même. C'est ce qui permet
// aux fonctions SQL (`determiner_role_ia`, `preparer_analyse_risque_echec`,
// `obtenir_detail_risque_echec_interne`) de rester la SEULE autorité de
// rôle/permission — l'Edge Function n'invente aucune vérification
// parallèle, elle relaie l'identité réelle de l'appelant.
// ============================================================================

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.48.1";

export function requisEnv(nom: string): string {
  const valeur = Deno.env.get(nom);
  if (!valeur) {
    throw new Error(`Variable d'environnement manquante : ${nom}`);
  }
  return valeur;
}

/**
 * Client scopé à l'utilisateur authentifié — extrait le JWT de l'en-tête
 * `Authorization` de la requête entrante (déjà vérifié par la plateforme,
 * `verify_jwt = true` dans `config.toml`) et l'utilise comme credentials
 * PostgREST, jamais la clé anon seule ni service_role. Renvoie aussi le
 * jeton brut : `supabase.auth.getUser()` SANS argument s'appuie sur une
 * session interne au client (absente ici, `persistSession: false`) — il
 * faut lui passer le jeton explicitement (`getUser(jeton)`), sinon il
 * échoue silencieusement même avec l'en-tête `Authorization` déjà posé.
 */
export function clientUtilisateur(req: Request): { client: SupabaseClient; jeton: string } {
  const authorization = req.headers.get("Authorization");
  if (!authorization) {
    throw new Error("Authorization manquante.");
  }
  const jeton = authorization.replace(/^Bearer\s+/i, "");

  const SUPABASE_URL = requisEnv("SUPABASE_URL");
  const SUPABASE_ANON_KEY = requisEnv("SUPABASE_ANON_KEY");

  const client = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });

  return { client, jeton };
}

export function entetesCors(origine: string | null): Record<string, string> {
  return {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": origine ?? "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "content-type, authorization, x-client-info",
  };
}

export function reponseJson(
  statut: number,
  corps: Record<string, unknown>,
  origine: string | null,
): Response {
  return new Response(JSON.stringify(corps), { status: statut, headers: entetesCors(origine) });
}
