// ============================================================================
// EcoShop — Edge Function « creer_profil_marketplace » (M15)
//
// Crée ou complète le profil PUBLIC d'un visiteur du marketplace, SANS mot de
// passe. Le profil vit dans `public.profils_publics` et porte un jeton opaque
// `token_acces` (UUID) qui corrèle le panier invité.
//
// Contrat (POST application/json) :
//   { "nom": string, "email"?: string, "telephone"?: string,
//     "role_voulu"?: string, "etablissement_id"?: string, "token_acces"?: string }
//
// Réponse :
//   200 { "success": true, "id": uuid, "token_acces": uuid, "complet": bool }
//   400 { "success": false, "error": "..." }
//   500 { "success": false, "error": "erreur_interne" }
//
// Sécurité : écriture via SERVICE ROLE (jamais de RLS anon en écriture) ;
// aucune donnée sensible n'est renvoyée ; le jeton n'ouvre aucun espace protégé.
// ============================================================================

import { createClient } from "npm:@supabase/supabase-js@2.48.1";

const SUPABASE_URL = requisSecret("SUPABASE_URL");
const SUPABASE_SERVICE_ROLE_KEY = requisSecret("SUPABASE_SERVICE_ROLE_KEY");

const ORIGINES_AUTORISEES = (Deno.env.get("CORS_ORIGINES") ?? "")
  .split(",").map((o) => o.trim()).filter(Boolean);

function requisSecret(nom: string): string {
  const valeur = Deno.env.get(nom);
  if (!valeur) {
    throw new Error(`Secret manquant : ${nom}`);
  }
  return valeur;
}

function entetes(origine: string | null): Record<string, string> {
  return {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": origine ?? "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "content-type, authorization, x-client-info",
  };
}

function json(
  statut: number,
  corps: Record<string, unknown>,
  origine: string | null,
): Response {
  return new Response(JSON.stringify(corps), { status: statut, headers: entetes(origine) });
}

Deno.serve(async (req) => {
  const origine = req.headers.get("origin");
  const autorisee = ORIGINES_AUTORISEES.length === 0 || ORIGINES_AUTORISEES.includes(origine ?? "");

  if (req.method === "OPTIONS") {
    return json(204, {}, autorisee ? origine : null);
  }
  if (req.method !== "POST") {
    return json(405, { success: false, error: "methode_non_autorisee" }, autorisee ? origine : null);
  }

  try {
    const corps = await req.json();

    const nom = typeof corps.nom === "string" ? corps.nom.trim() : "";
    const email = typeof corps.email === "string" ? corps.email.trim().toLowerCase() : "";
    const telephone = typeof corps.telephone === "string" ? corps.telephone.trim() : "";
    const roleVoulu = typeof corps.role_voulu === "string" && corps.role_voulu.trim()
      ? corps.role_voulu.trim()
      : "visiteur_marketplace";
    const etablissementId = typeof corps.etablissement_id === "string" && corps.etablissement_id
      ? corps.etablissement_id
      : null;
    const tokenAcces = typeof corps.token_acces === "string" && corps.token_acces
      ? corps.token_acces
      : null;

    if (!nom) {
      return json(400, { success: false, error: "nom_requis" }, autorisee ? origine : null);
    }
    if (!email && !telephone) {
      return json(400, { success: false, error: "contact_requis" }, autorisee ? origine : null);
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false },
    });

    const enregistrement = {
      nom,
      email: email || null,
      telephone: telephone || null,
      role_voulu: roleVoulu,
      etablissement_id: etablissementId,
    };

    let donnees = null;
    let erreur = null;

    if (tokenAcces) {
      // Complétion d'un profil invité existant.
      const resultat = await supabase
        .from("profils_publics")
        .update(enregistrement)
        .eq("token_acces", tokenAcces)
        .select("id, token_acces, complet")
        .maybeSingle();
      donnees = resultat.data;
      erreur = resultat.error;
    } else if (email) {
      // Upsert par email (le canal canonique du profil public).
      const resultat = await supabase
        .from("profils_publics")
        .upsert(enregistrement, { onConflict: "email" })
        .select("id, token_acces, complet")
        .single();
      donnees = resultat.data;
      erreur = resultat.error;
    } else {
      // Téléphone uniquement : nouvelle ligne (le client mémorise le token).
      const resultat = await supabase
        .from("profils_publics")
        .insert(enregistrement)
        .select("id, token_acces, complet")
        .single();
      donnees = resultat.data;
      erreur = resultat.error;
    }

    if (erreur || !donnees) {
      console.error(JSON.stringify({
        fn: "creer_profil_marketplace",
        niveau: "error",
        message: "echec enregistrement profil public",
        detail: erreur?.message ?? "aucune ligne",
      }));
      return json(500, { success: false, error: "erreur_interne" }, autorisee ? origine : null);
    }

    return json(200, {
      success: true,
      id: donnees.id,
      token_acces: donnees.token_acces,
      complet: donnees.complet,
    }, autorisee ? origine : null);
  } catch (erreur) {
    console.error(JSON.stringify({
      fn: "creer_profil_marketplace",
      niveau: "error",
      message: "erreur inattendue",
      detail: erreur instanceof Error ? erreur.message : String(erreur),
    }));
    return json(500, { success: false, error: "erreur_interne" }, autorisee ? origine : null);
  }
});
