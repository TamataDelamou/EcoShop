// ============================================================================
// EcoShop — Edge Function « connexion_identifiant » (REG-18, partie D)
//
// Connexion avec l'identifiant EcoShop au lieu de l'adresse e-mail : le
// serveur retrouve l'adresse, y envoie le code, puis vérifie le code et
// renvoie la session. Le téléphone ne voit que l'adresse masquée.
// Appelée avant toute connexion : verify_jwt = false (config.toml).
// Logique et garde-fous : _shared/connexion_identifiant.ts.
// ============================================================================

import { clientService, entetesCors, reponseJson, requisEnv } from "../_shared/supabase_client.ts";
import { traiter } from "../_shared/connexion_identifiant.ts";

const SUPABASE_URL = requisEnv("SUPABASE_URL");
const CLE_ANON = Deno.env.get("SUPABASE_ANON_KEY") ?? requisEnv("SUPABASE_PUBLISHABLE_KEY");

async function appelAuth(chemin: string, corps: Record<string, unknown>): Promise<Response> {
  return await fetch(`${SUPABASE_URL}/auth/v1/${chemin}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", apikey: CLE_ANON },
    body: JSON.stringify(corps),
  });
}

Deno.serve(async (req: Request) => {
  const origine = req.headers.get("origin");
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: entetesCors(origine) });
  if (req.method !== "POST") return reponseJson(405, { success: false, error: "method_not_allowed" }, origine);

  let corps: { action?: string; identifiant?: string; code?: string };
  try {
    corps = await req.json();
  } catch {
    return reponseJson(400, { success: false, error: "CORPS_INVALIDE" }, origine);
  }

  const service = clientService();
  const adresseReseau = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || "inconnue";

  const reponse = await traiter(corps, adresseReseau, {
    emailPour: async (identifiant) => {
      const { data, error } = await service.rpc("email_pour_identifiant_ecoshop", { p_identifiant: identifiant });
      if (error) throw new Error(error.message);
      return (data as string | null) ?? null;
    },
    noterEssai: async (cle, nature, minutes, max) => {
      const { data, error } = await service.rpc("noter_essai_connexion_identifiant", {
        p_cle: cle, p_nature: nature, p_minutes: minutes, p_max: max,
      });
      if (error) throw new Error(error.message);
      return data === true;
    },
    envoyerCode: async (email) => {
      const r = await appelAuth("otp", { email, create_user: false });
      if (!r.ok) throw new Error(`otp ${r.status}`);
    },
    verifierCode: async (email, code) => {
      const r = await appelAuth("verify", { type: "email", email, token: code });
      if (!r.ok) return null;
      const session = await r.json();
      return session?.access_token ? session : null;
    },
    cleMasque: requisEnv("SUPABASE_SERVICE_ROLE_KEY"),
    attendre: (ms) => new Promise((ok) => setTimeout(ok, ms)),
    enArrierePlan: (tache) => {
      // deno-lint-ignore no-explicit-any
      const runtime = (globalThis as any).EdgeRuntime;
      if (runtime?.waitUntil) runtime.waitUntil(tache);
    },
    maintenant: () => Date.now(),
  });

  return reponseJson(reponse.statut, reponse.corps, origine);
});
