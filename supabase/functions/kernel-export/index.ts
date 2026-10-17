// ============================================================================
// EcoShop — Edge Function « kernel-export » (KER-MUT K2)
// docs/REGISTRE.md REG-01.2 — contrat : docs/contrats/KERNEL_CONTROL_PLANE.md
//
// Pousse vers les endpoints d'agrégation du Control Plane du Kernel GSG :
//   1. les journaux d'audit (minimisés, sans valeurs — voir migration …1526),
//   2. les métriques techniques (journal_metriques),
//   3. un instantané des métriques clés (kernel_metriques_cles()).
//
// Déclenchement : appel POST planifié (pg_cron + pg_net, ou planificateur
// externe) portant l'en-tête `x-declencheur-secret`. Aucun utilisateur ne
// l'appelle jamais.
//
// Non bloquante et sans perte : le curseur d'un flux n'avance qu'après un
// acquittement 2xx du Kernel. Un échec est consigné
// (kernel_export_curseurs.derniere_erreur) et le même lot repart au passage
// suivant, avec la même clé d'idempotence.
// ============================================================================

import { clientService } from "../_shared/supabase_client.ts";
import {
  chargerClePrivee,
  cleIdempotenceLot,
  type ClePrivee,
  egaliteTempsConstant,
  signerJetonSortant,
} from "../_shared/interservices.ts";

const FLUX = [
  { flux: "audit", chemin: "audit-logs" },
  { flux: "metriques", chemin: "metrics" },
] as const;

const TAILLE_LOT = Number(Deno.env.get("KERNEL_EXPORT_TAILLE_LOT") ?? "500");
const LOTS_MAX_PAR_FLUX = Number(Deno.env.get("KERNEL_EXPORT_LOTS_MAX") ?? "20");
const DELAI_KERNEL_MS = Number(Deno.env.get("GSG_KERNEL_TIMEOUT_MS") ?? "10000");

function json(status: number, corps: unknown): Response {
  return new Response(JSON.stringify(corps), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function journal(niveau: "info" | "warn" | "error", message: string, extra: Record<string, unknown> = {}) {
  console[niveau === "info" ? "log" : niveau](JSON.stringify({ fn: "kernel-export", niveau, message, ...extra }));
}

async function envoyer(
  url: string,
  cle: ClePrivee,
  corps: unknown,
  idempotence: string,
): Promise<{ ok: boolean; detail: string }> {
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${await signerJetonSortant(cle)}`,
        "Idempotency-Key": idempotence,
      },
      body: JSON.stringify(corps),
      signal: AbortSignal.timeout(DELAI_KERNEL_MS),
    });
    // Le corps de réponse n'est jamais relayé : seul le statut compte.
    await res.body?.cancel();
    return { ok: res.ok, detail: `HTTP ${res.status}` };
  } catch (erreur) {
    return { ok: false, detail: erreur instanceof Error ? erreur.message : String(erreur) };
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json(405, { success: false, error: "method_not_allowed" });

  const secretAttendu = Deno.env.get("KERNEL_EXPORT_DECLENCHEUR_SECRET");
  const secretRecu = req.headers.get("x-declencheur-secret") ?? "";
  if (!secretAttendu || !egaliteTempsConstant(secretRecu, secretAttendu)) {
    return json(401, { success: false, error: "NON_AUTORISE" });
  }

  const baseKernel = Deno.env.get("GSG_KERNEL_AGGREGATION_URL");
  const jwkPrive = Deno.env.get("KERNEL_INTERSERVICES_CLE_PRIVEE_JWK");
  if (!baseKernel || !jwkPrive) {
    // Kernel pas encore raccordé : rien à faire, ce n'est pas une erreur.
    journal("warn", "GSG_KERNEL_AGGREGATION_URL ou clé inter-services absente — export ignoré");
    return json(200, { success: true, ignore: "KERNEL_NON_CONFIGURE" });
  }

  let cle: ClePrivee;
  try {
    cle = await chargerClePrivee(jwkPrive);
  } catch (erreur) {
    journal("error", "clé inter-services inutilisable", { code: (erreur as Error).message });
    return json(500, { success: false, error: "CLE_INTERSERVICES_INVALIDE" });
  }

  const base = baseKernel.replace(/\/+$/, "");
  const supabase = clientService();
  const bilan: Record<string, unknown> = {};

  for (const { flux, chemin } of FLUX) {
    let lignesEnvoyees = 0;
    let lots = 0;
    let erreur: string | null = null;

    while (lots < LOTS_MAX_PAR_FLUX) {
      const { data: lot, error } = await supabase.rpc("kernel_lot_export", {
        p_flux: flux,
        p_limite: TAILLE_LOT,
      });
      if (error) {
        erreur = `lecture: ${error.message}`;
        break;
      }
      const lignes = (lot?.lignes ?? []) as Array<{ id: string; horodatage: string }>;
      if (lignes.length === 0) break;

      const premier = lignes[0];
      const dernier = lignes[lignes.length - 1];
      const idempotence = await cleIdempotenceLot(flux, premier.id, dernier.id);

      const envoi = await envoyer(
        `${base}/v1/aggregation/produits/ecoshop/${chemin}`,
        cle,
        { produit: "ecoshop", flux, lot_id: idempotence, apres: lot.apres, lignes },
        idempotence,
      );
      if (!envoi.ok) {
        erreur = `envoi: ${envoi.detail}`;
        break;
      }

      const { error: errValidation } = await supabase.rpc("kernel_valider_lot", {
        p_flux: flux,
        p_horodatage: dernier.horodatage,
        p_id: dernier.id,
        p_nb_lignes: lignes.length,
      });
      if (errValidation) {
        // Le Kernel a reçu le lot mais le curseur n'a pas avancé : il sera
        // renvoyé avec la même clé d'idempotence, le Kernel le dédoublonne.
        erreur = `validation: ${errValidation.message}`;
        break;
      }

      lignesEnvoyees += lignes.length;
      lots++;
      if (lignes.length < TAILLE_LOT) break;
    }

    if (erreur) {
      journal("error", "export interrompu", { flux, erreur });
      await supabase.rpc("kernel_signaler_echec", { p_flux: flux, p_erreur: erreur });
    }
    bilan[flux] = { lots, lignes: lignesEnvoyees, erreur: erreur ? "voir_journal" : null };
  }

  // Instantané des métriques clés (une fois par passage).
  const { data: metriques, error: errMetriques } = await supabase.rpc("kernel_metriques_cles");
  if (errMetriques) {
    journal("error", "kernel_metriques_cles a échoué", { detail: errMetriques.message });
    bilan.instantane = { envoye: false };
  } else {
    const idempotence = await cleIdempotenceLot("instantane", metriques.collecte_le, metriques.collecte_le);
    const envoi = await envoyer(`${base}/v1/aggregation/produits/ecoshop/snapshots`, cle, metriques, idempotence);
    if (!envoi.ok) journal("error", "instantané non accepté", { detail: envoi.detail });
    bilan.instantane = { envoye: envoi.ok };
  }

  journal("info", "passage terminé", bilan);
  return json(200, { success: true, bilan });
});
