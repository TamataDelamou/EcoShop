// ============================================================================
// EcoShop — Edge Function « relancer_paiements_orange_money » (REG-02, L7)
//
// Filet de sécurité si une notification Orange se perd. Appel POST planifié
// (pg_cron + pg_net ou planificateur externe, toutes les 5 min recommandé)
// avec l'en-tête `x-declencheur-secret: <PAIEMENTS_DECLENCHEUR_SECRET>`.
//
//   1. Abandonne les initiations jamais présentées au payeur (> 30 min sans
//      jeton de paiement) — aucun argent n'a pu bouger.
//   2. Pour chaque transaction encore en cours, RE-INTERROGE Orange avec les
//      identifiants de l'établissement, puis crédite ou clôt de façon
//      idempotente via traiter_resultat_mobile_money() — exactement le même
//      chemin que la notification.
//   3. Au-delà de 24 h sans confirmation d'Orange : clôture « echoue »
//      (EXPIREE_SANS_CONFIRMATION), toujours APRÈS une dernière vérification.
//
// Un échec sur une transaction n'arrête jamais les suivantes.
// ============================================================================

import { clientService } from "../_shared/supabase_client.ts";
import { egaliteTempsConstant } from "../_shared/interservices.ts";
import {
  consulterStatut,
  type IdentifiantsOrange,
  obtenirJeton,
  resultatDepuisStatut,
} from "../_shared/orange_money_client.ts";

interface Candidate {
  id: string;
  sous_compte_id: string;
  reference_commande: string;
  montant: number;
  pay_token: string;
  a_expirer: boolean;
}

function json(status: number, corps: unknown): Response {
  return new Response(JSON.stringify(corps), { status, headers: { "Content-Type": "application/json" } });
}

function journal(niveau: "info" | "warn" | "error", message: string, extra: Record<string, unknown> = {}) {
  console[niveau === "info" ? "log" : niveau](
    JSON.stringify({ fn: "relancer_paiements_orange_money", niveau, message, ...extra }),
  );
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json(405, { success: false });

  const attendu = Deno.env.get("PAIEMENTS_DECLENCHEUR_SECRET");
  if (!attendu || !egaliteTempsConstant(req.headers.get("x-declencheur-secret") ?? "", attendu)) {
    return json(401, { success: false, error: "NON_AUTORISE" });
  }

  const service = clientService();
  const bilan = { abandonnees: 0, verifiees: 0, reussies: 0, echouees: 0, expirees: 0, encore_en_cours: 0, erreurs: 0 };

  const { data: abandonnees, error: errAbandon } = await service.rpc("abandonner_initiations_orphelines");
  if (errAbandon) journal("error", "abandon des initiations orphelines impossible", { detail: errAbandon.message });
  else bilan.abandonnees = Number(abandonnees ?? 0);

  const { data, error } = await service.rpc("transactions_mobile_money_a_relancer", { p_limite: 50 });
  if (error) {
    journal("error", "lecture des transactions à relancer impossible", { detail: error.message });
    return json(500, { success: false });
  }
  const candidates = (data ?? []) as Candidate[];

  // Un jeton OAuth par sous-compte (établissement) et par passage.
  const jetons = new Map<string, { id: IdentifiantsOrange; jeton: string }>();

  for (const tx of candidates) {
    try {
      let acces = jetons.get(tx.sous_compte_id);
      if (!acces) {
        const { data: identifiants, error: errId } = await service.rpc("lire_identifiants_sous_compte", {
          p_sous_compte_id: tx.sous_compte_id,
        });
        if (errId || !identifiants) throw new Error("IDENTIFIANTS_INDISPONIBLES");
        const id = identifiants as IdentifiantsOrange;
        acces = { id, jeton: await obtenirJeton(id) };
        jetons.set(tx.sous_compte_id, acces);
      }

      const statut = await consulterStatut(acces.id, acces.jeton, {
        referenceCommande: tx.reference_commande,
        montant: Number(tx.montant),
        payToken: tx.pay_token,
      });
      bilan.verifiees++;

      let resultat = resultatDepuisStatut(statut.statut);
      let message: string | null = resultat === "echoue" ? `Orange: ${statut.statut}` : null;
      if (resultat === null && tx.a_expirer) {
        resultat = "echoue";
        message = "EXPIREE_SANS_CONFIRMATION";
      }
      if (resultat === null) {
        bilan.encore_en_cours++;
        continue;
      }

      const { data: issue, error: errTraitement } = await service.rpc("traiter_resultat_mobile_money", {
        p_transaction_id: tx.id,
        p_resultat: resultat,
        p_montant_confirme: resultat === "reussi" ? Number(tx.montant) : null,
        p_reference_operateur: statut.referenceOperateur,
        p_message: message,
      });
      if (errTraitement) throw new Error(`traitement: ${errTraitement.message}`);

      if (issue === "reussi") bilan.reussies++;
      else if (message === "EXPIREE_SANS_CONFIRMATION") bilan.expirees++;
      else if (issue === "echoue" || issue === "ecart_montant") bilan.echouees++;
    } catch (erreur) {
      bilan.erreurs++;
      journal("error", "relance impossible pour une transaction", {
        transactionId: tx.id,
        detail: erreur instanceof Error ? erreur.message : String(erreur),
      });
    }
  }

  journal("info", "passage terminé", bilan);
  return json(200, { success: true, bilan });
});
