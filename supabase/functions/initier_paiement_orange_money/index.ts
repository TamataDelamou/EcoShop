// ============================================================================
// EcoShop — Edge Function « initier_paiement_orange_money » (REG-02, lot L3)
//
// Appelée par le client Flutter (verify_jwt = true) avec le JWT du payeur.
//   1. initier_transaction_mobile_money (JWT relayé) : droits du payeur,
//      montant recalculé/borné serveur, sous-compte Orange de l'établissement.
//   2. Identifiants Orange de CET établissement (service_role, jamais vus
//      par le client).
//   3. Création du paiement chez Orange ; empreinte du notif_token stockée.
//   4. Renvoie l'URL Orange où rediriger le payeur.
//
// Corps : { objet: "scolarite" | "commande_marketplace", cibleId, montant? }
// ============================================================================

import { clientService, clientUtilisateur, entetesCors, reponseJson } from "../_shared/supabase_client.ts";
import {
  creerPaiement,
  empreinte,
  ErreurOrange,
  type IdentifiantsOrange,
  obtenirJeton,
} from "../_shared/orange_money_client.ts";

const CODES_METIER = new Set([
  "ACCES_REFUSE", "AUTH_REQUISE", "INSCRIPTION_INTROUVABLE", "COMMANDE_INTROUVABLE",
  "COMMANDE_NON_PAYABLE", "RIEN_A_PAYER", "MONTANT_SUPERIEUR_AU_SOLDE",
  "MONTANT_GNF_ENTIER_REQUIS", "PAIEMENT_DEJA_EN_COURS", "ORANGE_MONEY_NON_ACTIVE",
  "OBJET_INCONNU",
]);

Deno.serve(async (req: Request) => {
  const origine = req.headers.get("origin");
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: entetesCors(origine) });
  if (req.method !== "POST") return reponseJson(405, { success: false, error: "method_not_allowed" }, origine);

  let corps: { objet?: string; cibleId?: string; montant?: number };
  try {
    corps = await req.json();
  } catch {
    return reponseJson(400, { success: false, error: "CORPS_INVALIDE" }, origine);
  }
  if (!corps.objet || !corps.cibleId) {
    return reponseJson(400, { success: false, error: "PARAMETRES_MANQUANTS" }, origine);
  }

  // 1. Initiation côté SQL avec l'identité réelle du payeur.
  const { client } = clientUtilisateur(req);
  const { data: tx, error } = await client.rpc("initier_transaction_mobile_money", {
    p_objet: corps.objet,
    p_cible_id: corps.cibleId,
    p_montant: corps.montant ?? null,
  });
  if (error) {
    const code = CODES_METIER.has(error.message) ? error.message : "INITIATION_REFUSEE";
    const statut = code === "ACCES_REFUSE" ? 403 : code === "PAIEMENT_DEJA_EN_COURS" ? 409 : 400;
    return reponseJson(statut, { success: false, error: code }, origine);
  }

  const service = clientService();
  const transactionId: string = tx.transaction_id;

  try {
    // 2. Identifiants de l'établissement.
    const { data: identifiants, error: errId } = await service.rpc("lire_identifiants_sous_compte", {
      p_sous_compte_id: tx.sous_compte_id,
    });
    if (errId || !identifiants) throw new ErreurOrange("IDENTIFIANTS_INDISPONIBLES");

    // 3. Création chez Orange.
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const urlRetour = Deno.env.get("ORANGE_MONEY_URL_RETOUR") ?? "io.gsg.ecoshop://paiement/retour";
    const id = identifiants as IdentifiantsOrange;
    const jeton = await obtenirJeton(id);
    const paiement = await creerPaiement(id, jeton, {
      referenceCommande: tx.reference_commande,
      montant: Number(tx.montant),
      urlRetour: `${urlRetour}?transaction=${transactionId}`,
      urlAnnulation: `${urlRetour}?transaction=${transactionId}&annule=1`,
      urlNotification: `${supabaseUrl}/functions/v1/recevoir_notification_orange_money?transaction=${transactionId}`,
      reference: "EcoShop",
    });

    const { error: errFin } = await service.rpc("finaliser_initiation_mobile_money", {
      p_transaction_id: transactionId,
      p_pay_token: paiement.payToken,
      p_empreinte_jeton_notification: await empreinte(paiement.notifToken),
    });
    if (errFin) throw new ErreurOrange("FINALISATION_ECHOUEE");

    return reponseJson(200, {
      success: true,
      transactionId,
      urlPaiement: paiement.urlPaiement,
      montant: tx.montant,
      devise: tx.devise,
    }, origine);
  } catch (erreur) {
    const code = erreur instanceof ErreurOrange ? erreur.code : "ERREUR_INTERNE";
    console.error(JSON.stringify({ fn: "initier_paiement_orange_money", transactionId, code }));
    // Aucun argent n'a bougé : on libère la cible pour une nouvelle tentative.
    await service.rpc("abandonner_initiation_mobile_money", {
      p_transaction_id: transactionId,
      p_message: code,
    });
    return reponseJson(502, { success: false, error: "ORANGE_INDISPONIBLE" }, origine);
  }
});
