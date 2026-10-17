// ============================================================================
// EcoShop — Edge Function « kernel-control-plane » (KER-MUT K2/K3)
// docs/REGISTRE.md REG-01.3 — contrat : docs/contrats/KERNEL_CONTROL_PLANE.md
//
// Point d'accès EN LECTURE SEULE du tableau de bord central du Kernel GSG :
//
//   GET /kernel-control-plane/jwks.json   public — clé publique EcoShop
//   GET /kernel-control-plane/sante       santé de la base
//   GET /kernel-control-plane/metriques   métriques clés (agrégats)
//   GET /kernel-control-plane/audit       journaux d'audit minimisés, paginés
//   GET /kernel-control-plane/metriques-techniques   journal_metriques, paginé
//
// Pagination : ?apres_horodatage=…&apres_id=…&limite=… (max 1000) ; la
// réponse renvoie `suivant` à repasser tel quel.
//
// Toutes les routes sauf jwks.json exigent un JWT ES256 émis par le Kernel
// (GSG_KERNEL_JWKS_URL, GSG_KERNEL_ISSUER), audience « ecoshop », scope
// « ecoshop:lecture », durée de vie ≤ 5 min. Aucune route d'écriture.
// ============================================================================

import { createRemoteJWKSet } from "npm:jose@5.9.6";
import { clientService } from "../_shared/supabase_client.ts";
import {
  chargerClePrivee,
  ErreurInterServices,
  jetonPorteur,
  jeuDeClesPublic,
  verifierJetonEntrant,
} from "../_shared/interservices.ts";

const KERNEL_JWKS_URL = Deno.env.get("GSG_KERNEL_JWKS_URL");
const KERNEL_ISSUER = Deno.env.get("GSG_KERNEL_ISSUER");

// Instance réutilisée : jose gère cache et rotation des clés du Kernel.
const jwksKernel = KERNEL_JWKS_URL ? createRemoteJWKSet(new URL(KERNEL_JWKS_URL)) : null;

function json(status: number, corps: unknown, cache = "no-store"): Response {
  return new Response(JSON.stringify(corps), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": cache },
  });
}

function route(url: URL): string {
  // pathname = /kernel-control-plane/<route> (ou /functions/v1/kernel-control-plane/<route>)
  const segments = url.pathname.split("/").filter(Boolean);
  const i = segments.lastIndexOf("kernel-control-plane");
  return i >= 0 ? segments.slice(i + 1).join("/") : segments.join("/");
}

async function lecturePaginee(flux: "audit" | "metriques", url: URL): Promise<Response> {
  const apresHorodatage = url.searchParams.get("apres_horodatage");
  const apresId = url.searchParams.get("apres_id");
  if ((apresHorodatage === null) !== (apresId === null)) {
    return json(400, { success: false, error: "CURSEUR_INCOMPLET" });
  }
  if (apresHorodatage !== null && Number.isNaN(Date.parse(apresHorodatage))) {
    return json(400, { success: false, error: "CURSEUR_INVALIDE" });
  }
  const limite = Number(url.searchParams.get("limite") ?? "500");

  const { data, error } = await clientService().rpc("kernel_lecture", {
    p_flux: flux,
    p_apres_horodatage: apresHorodatage,
    p_apres_id: apresId,
    p_limite: Number.isFinite(limite) ? limite : 500,
  });
  if (error) {
    console.error(JSON.stringify({ fn: "kernel-control-plane", flux, detail: error.message }));
    return json(400, { success: false, error: "LECTURE_REFUSEE" });
  }
  const lignes = (data ?? []) as Array<{ id: string; horodatage: string }>;
  const dernier = lignes[lignes.length - 1];
  return json(200, {
    success: true,
    lignes,
    suivant: dernier ? { apres_horodatage: dernier.horodatage, apres_id: dernier.id } : null,
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "GET") return json(405, { success: false, error: "method_not_allowed" });

  const url = new URL(req.url);
  const chemin = route(url);

  // --- Route publique : clé publique EcoShop (vérification par le Kernel) ---
  if (chemin === "jwks.json") {
    const jwkPrive = Deno.env.get("KERNEL_INTERSERVICES_CLE_PRIVEE_JWK");
    if (!jwkPrive) return json(503, { success: false, error: "NON_CONFIGURE" });
    try {
      return json(200, jeuDeClesPublic(await chargerClePrivee(jwkPrive)), "public, max-age=300");
    } catch {
      return json(500, { success: false, error: "CLE_INTERSERVICES_INVALIDE" });
    }
  }

  // --- Toutes les autres routes : jeton du Kernel obligatoire ---
  if (!jwksKernel || !KERNEL_ISSUER) {
    return json(503, { success: false, error: "NON_CONFIGURE" });
  }
  try {
    await verifierJetonEntrant(jetonPorteur(req), jwksKernel, { emetteur: KERNEL_ISSUER });
  } catch (erreur) {
    const code = erreur instanceof ErreurInterServices ? erreur.code : "JETON_INVALIDE";
    const status = code === "SCOPE_INSUFFISANT" ? 403 : 401;
    return json(status, { success: false, error: code });
  }

  switch (chemin) {
    case "sante": {
      const { data, error } = await clientService().rpc("indicateurs_sante_base");
      return error
        ? json(500, { success: false, error: "erreur_interne" })
        : json(200, { success: true, produit: "ecoshop", sante: data });
    }
    case "metriques": {
      const { data, error } = await clientService().rpc("kernel_metriques_cles");
      return error
        ? json(500, { success: false, error: "erreur_interne" })
        : json(200, { success: true, metriques: data });
    }
    case "audit":
      return await lecturePaginee("audit", url);
    case "metriques-techniques":
      return await lecturePaginee("metriques", url);
    default:
      return json(404, { success: false, error: "route_inconnue" });
  }
});
