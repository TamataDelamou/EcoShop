// ============================================================================
// EcoShop — Edge Function « recevoir_notification_orange_money » (REG-02, L3)
//
// Appelée par Orange (verify_jwt = false) sur notif_url :
//   POST …/recevoir_notification_orange_money?transaction=<uuid>
//   { "status": "SUCCESS" | "FAILED" | …, "notif_token": "…", "txnid": "…" }
//
// La notification n'est JAMAIS crue sur parole :
//   1. son notif_token doit correspondre à l'empreinte stockée à l'initiation
//      (sinon 401, rien n'est touché) ;
//   2. le statut est ensuite RECONFIRMÉ auprès d'Orange (consulterStatut) avec
//      les identifiants de l'établissement ; seul ce statut-là est utilisé ;
//   3. traiter_resultat_mobile_money() crédite de façon idempotente : une
//      notification rejouée ne crédite jamais deux fois.
// Réponse toujours 200 une fois la notification authentifiée (même si le
// statut n'est pas encore final), pour éviter des relances inutiles.
// ============================================================================

import { clientService } from "../_shared/supabase_client.ts";
import { egaliteTempsConstant } from "../_shared/interservices.ts";
import {
  consulterStatut,
  empreinte,
  type IdentifiantsOrange,
  obtenirJeton,
  resultatDepuisStatut,
} from "../_shared/orange_money_client.ts";

const MOTIF_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function json(status: number, corps: unknown): Response {
  return new Response(JSON.stringify(corps), { status, headers: { "Content-Type": "application/json" } });
}

function journal(niveau: "info" | "warn" | "error", message: string, extra: Record<string, unknown> = {}) {
  console[niveau === "info" ? "log" : niveau](
    JSON.stringify({ fn: "recevoir_notification_orange_money", niveau, message, ...extra }),
  );
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json(405, { success: false });

  const transactionId = new URL(req.url).searchParams.get("transaction") ?? "";
  if (!MOTIF_UUID.test(transactionId)) return json(400, { success: false });

  let notif: { status?: string; notif_token?: string; txnid?: string };
  try {
    notif = await req.json();
  } catch {
    return json(400, { success: false });
  }
  if (typeof notif.notif_token !== "string" || !notif.notif_token) return json(401, { success: false });

  const service = clientService();
  const { data: tx, error } = await service.rpc("lire_transaction_mobile_money_serveur", {
    p_transaction_id: transactionId,
  });
  if (error || !tx) return json(404, { success: false });

  // 1. Authentification de la notification.
  const attendue = tx.empreinte_jeton_notification as string | null;
  if (!attendue || !egaliteTempsConstant(await empreinte(notif.notif_token), attendue)) {
    journal("warn", "notification non authentifiée", { transactionId });
    return json(401, { success: false });
  }

  if (tx.statut !== "initie" && tx.statut !== "en_attente") {
    return json(200, { success: true, resultat: "deja_traitee" });
  }

  try {
    // 2. Reconfirmation auprès d'Orange.
    const { data: identifiants, error: errId } = await service.rpc("lire_identifiants_sous_compte", {
      p_sous_compte_id: tx.sous_compte_id,
    });
    if (errId || !identifiants) throw new Error("IDENTIFIANTS_INDISPONIBLES");
    const id = identifiants as IdentifiantsOrange;
    const jeton = await obtenirJeton(id);
    const statut = await consulterStatut(id, jeton, {
      referenceCommande: tx.reference_commande,
      montant: Number(tx.montant),
      payToken: tx.pay_token,
    });

    const resultat = resultatDepuisStatut(statut.statut);
    if (resultat === null) {
      return json(200, { success: true, resultat: "en_attente" });
    }

    // 3. Crédit idempotent. Le statut a été interrogé POUR ce montant précis :
    // un SUCCESS confirme donc le montant attendu.
    const { data: issue, error: errTraitement } = await service.rpc("traiter_resultat_mobile_money", {
      p_transaction_id: transactionId,
      p_resultat: resultat,
      p_montant_confirme: resultat === "reussi" ? Number(tx.montant) : null,
      p_reference_operateur: statut.referenceOperateur ?? notif.txnid ?? null,
      p_message: resultat === "echoue" ? `Orange: ${statut.statut}` : null,
    });
    if (errTraitement) throw new Error(`traitement: ${errTraitement.message}`);

    journal("info", "notification traitée", { transactionId, issue });
    return json(200, { success: true, resultat: issue });
  } catch (erreur) {
    // 500 => Orange relancera la notification ; rien n'a été crédité.
    journal("error", "traitement impossible", {
      transactionId,
      detail: erreur instanceof Error ? erreur.message : String(erreur),
    });
    return json(500, { success: false });
  }
});
