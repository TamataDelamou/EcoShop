// ============================================================================
// EcoShop — Edge Function « gsg-id-federate » (M2, ch. 5.5 du cahier)
//
// Couche additive et NON bloquante de fédération d'identité GSG ID :
//   1. Vérifie la signature du JWT EcoShop (Supabase Auth) via JWKS.
//   2. Présente le jeton au GSG Platform Kernel (contrat de référence : src/).
//   3. Renseigne profiles.gsg_id sans jamais bloquer la connexion.
//
// Non bloquant signifie : toute défaillance du Kernel (indisponible, lent,
// réponse invalide) se traduit par un succès sans gsg_id, jamais par un échec
// d'authentification côté EcoShop.
// ============================================================================

import { createClient } from "npm:@supabase/supabase-js@2.48.1";
import { createRemoteJWKSet, jwtVerify } from "npm:jose@5.9.6";

// -- Configuration (secrets gérés par le coffre-fort Edge Functions) ---------
const SUPABASE_URL = requisSecret("SUPABASE_URL");
const SUPABASE_SERVICE_ROLE_KEY = requisSecret("SUPABASE_SERVICE_ROLE_KEY");
const SUPABASE_JWKS_URL = Deno.env.get("SUPABASE_JWKS_URL") ??
  `${SUPABASE_URL}/auth/v1/.well-known/jwks.json`;
const GSG_KERNEL_BASE_URL = Deno.env.get("GSG_KERNEL_BASE_URL");
const GSG_KERNEL_API_KEY = Deno.env.get("GSG_KERNEL_API_KEY");

/** Origines autorisées, séparées par des virgules. Vide = aucune origine web. */
const ORIGINES_AUTORISEES = (Deno.env.get("CORS_ORIGINES") ?? "")
  .split(",").map((o) => o.trim()).filter(Boolean);

/** Délai au-delà duquel le Kernel est considéré indisponible. */
const DELAI_KERNEL_MS = Number(Deno.env.get("GSG_KERNEL_TIMEOUT_MS") ?? "5000");

function requisSecret(nom: string): string {
  const valeur = Deno.env.get(nom);
  if (!valeur) {
    // Échec au démarrage plutôt qu'au premier appel : une fonction mal
    // configurée ne doit pas répondre 500 en silence à chaque requête.
    throw new Error(`Secret manquant : ${nom}`);
  }
  return valeur;
}

// Le jeu de clés est mis en cache au niveau du module : createRemoteJWKSet
// gère lui-même la rotation et le cooldown, mais seulement si l'instance est
// réutilisée. En recréer une par requête refait un appel réseau à chaque fois.
const jwks = createRemoteJWKSet(new URL(SUPABASE_JWKS_URL));

function enTetesCors(origine: string | null): Record<string, string> {
  const entetes: Record<string, string> = {
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    Vary: "Origin",
  };
  if (origine && ORIGINES_AUTORISEES.includes(origine)) {
    entetes["Access-Control-Allow-Origin"] = origine;
  }
  return entetes;
}

function json(
  status: number,
  body: unknown,
  origine: string | null,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...enTetesCors(origine), "Content-Type": "application/json" },
  });
}

function jetonPorteur(req: Request): string {
  const header = req.headers.get("authorization") ?? "";
  const [scheme, token] = header.split(" ");
  if (scheme?.toLowerCase() !== "bearer" || !token) {
    throw new Error("AUTH_REQUISE");
  }
  return token;
}

/** Vérifie la signature du JWT via le JWKS du projet Supabase d'EcoShop. */
async function verifierJwtEcoShop(token: string): Promise<string> {
  const { payload } = await jwtVerify(token, jwks, {
    issuer: `${SUPABASE_URL}/auth/v1`,
    audience: "authenticated",
  });
  if (!payload.sub) throw new Error("JETON_SANS_SUJET");
  return payload.sub;
}

/**
 * Présente l'identité au GSG Platform Kernel et récupère le gsg_id.
 * Contrat de référence : src/identity (external-identities, ch. KER-ID-02).
 *
 * Renvoie null — jamais une exception — dès que le Kernel ne répond pas comme
 * attendu : la fédération est additive, elle ne conditionne aucune connexion.
 */
async function federerVersKernel(userId: string): Promise<string | null> {
  if (!GSG_KERNEL_BASE_URL || !GSG_KERNEL_API_KEY) {
    console.warn(JSON.stringify({
      fn: "gsg-id-federate",
      niveau: "warn",
      message: "GSG_KERNEL_* non configurés — fédération ignorée",
    }));
    return null;
  }

  try {
    const res = await fetch(
      `${GSG_KERNEL_BASE_URL}/v1/identity/external-identities/link`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${GSG_KERNEL_API_KEY}`,
        },
        body: JSON.stringify({ produitId: "ecoshop", externalUserId: userId }),
        signal: AbortSignal.timeout(DELAI_KERNEL_MS),
      },
    );

    if (!res.ok) {
      console.error(JSON.stringify({
        fn: "gsg-id-federate",
        niveau: "error",
        message: "réponse Kernel non 2xx",
        status: res.status,
      }));
      return null;
    }

    const data = await res.json();
    const gsgId = data?.gsgId;
    // Le contrat annonce un uuid : on refuse tout ce qui n'en est pas un
    // plutôt que d'échouer plus loin sur un cast Postgres.
    return typeof gsgId === "string" && estUuid(gsgId) ? gsgId : null;
  } catch (erreur) {
    console.error(JSON.stringify({
      fn: "gsg-id-federate",
      niveau: "error",
      message: "Kernel injoignable",
      detail: erreur instanceof Error ? erreur.message : String(erreur),
    }));
    return null;
  }
}

const MOTIF_UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function estUuid(valeur: string): boolean {
  return MOTIF_UUID.test(valeur);
}

Deno.serve(async (req: Request) => {
  const origine = req.headers.get("origin");

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: enTetesCors(origine) });
  }
  if (req.method !== "POST") {
    return json(405, { success: false, error: "method_not_allowed" }, origine);
  }

  let userId: string;
  try {
    userId = await verifierJwtEcoShop(jetonPorteur(req));
  } catch (erreur) {
    const code = erreur instanceof Error && erreur.message === "AUTH_REQUISE"
      ? "AUTH_REQUISE"
      : "JETON_INVALIDE";
    return json(401, { success: false, error: code }, origine);
  }

  try {
    const gsgId = await federerVersKernel(userId);

    if (gsgId) {
      const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
        auth: { persistSession: false },
      });
      const { error } = await supabase
        .from("profiles")
        .update({ gsg_id: gsgId })
        .eq("id", userId);

      if (error) {
        // La fédération a abouti côté Kernel mais pas côté EcoShop : on le
        // journalise et on répond succès sans gsgId, la prochaine tentative
        // rattrapera. Rien de tout cela ne doit bloquer l'utilisateur.
        console.error(JSON.stringify({
          fn: "gsg-id-federate",
          niveau: "error",
          message: "écriture profiles.gsg_id échouée",
          detail: error.message,
        }));
        return json(200, { success: true, gsgId: null }, origine);
      }
    }

    return json(200, { success: true, gsgId }, origine);
  } catch (erreur) {
    // Aucun détail interne n'est renvoyé au client.
    console.error(JSON.stringify({
      fn: "gsg-id-federate",
      niveau: "error",
      message: "erreur inattendue",
      detail: erreur instanceof Error ? erreur.message : String(erreur),
    }));
    return json(500, { success: false, error: "erreur_interne" }, origine);
  }
});
