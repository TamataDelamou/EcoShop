// ============================================================================
// EcoShop — Edge Function « initier_paiement_cinetpay »
// (Facturation/Quota IA — brique CinetPay générique, étape (b) ; flux
// individuel abonnement_premium_eleve depuis l'étape (c))
//
// Point d'entrée UNIQUE pour démarrer un paiement CinetPay, quel que soit le
// type d'objet payé (licence_pro_etablissement, frais_ia_admin_etablissement,
// abonnement_premium_eleve depuis l'étape (c) ; scolarite chapitre 17 plus
// tard, sans réécriture de cette fonction).
//
//   1. Relaie le JWT de l'appelant vers `initier_transaction_cinetpay`
//      (SQL) — recalcule le montant SERVEUR, jamais une valeur du client.
//      Toute la garde d'accès (personnel de l'établissement concerné ou
//      admin GSG) et les règles métier (déjà payé, rien à facturer, etc.)
//      vivent là, pas ici.
//   2. Lit la configuration CinetPay via un client service_role
//      (`parametres_secrets_integration`, RLS deny-all pour tout rôle
//      client -- voir migration 20260906001515).
//   3. SEUL appel sortant réel vers l'API CinetPay dans tout ce projet,
//      isolé dans `_shared/cinetpay_client.ts` — frontière volontairement
//      étroite, pour être branchée sur de vrais identifiants plus tard sans
//      toucher au reste.
//   4. Enregistre la référence CinetPay via `finaliser_initiation_cinetpay`
//      (service_role) — n'affecte jamais statut ni montant_attendu.
//
// Aucun identifiant CinetPay disponible à ce jour : si la configuration est
// absente (api_key/site_id null), renvoie 503 CINETPAY_NON_CONFIGURE plutôt
// que d'échouer sur un appel HTTP voué à l'échec. `CINETPAY_URL_OVERRIDE`
// permet de simuler l'API en local (voir _shared/cinetpay_client.ts).
// ============================================================================

import { initierPaiementCinetpayReel } from "../_shared/cinetpay_client.ts";
import { clientService, clientUtilisateur, entetesCors, reponseJson } from "../_shared/supabase_client.ts";

interface CorpsRequete {
  typeObjetPaye?: string;
  etablissementId?: string;
  anneeScolaireId?: string;
  // Flux individuel (étape c, abonnement_premium_eleve) — jamais
  // etablissementId pour ce type, voir migration 20260906001519.
  beneficiaireFicheEleveId?: string;
  formule?: string;
}

const STATUT_PAR_ERRCODE: Record<string, number> = {
  "42501": 403,
  "22023": 400,
  "23514": 400,
  "0A000": 400,
};

Deno.serve(async (req) => {
  const origine = req.headers.get("origin");

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: entetesCors(origine) });
  }
  if (req.method !== "POST") {
    return reponseJson(405, { error: "methode_non_autorisee" }, origine);
  }

  try {
    const corps = (await req.json()) as CorpsRequete;
    if (!corps.typeObjetPaye) {
      return reponseJson(400, { error: "typeObjetPaye_requis" }, origine);
    }

    // Flux individuel : ni etablissementId ni anneeScolaireId ne
    // s'appliquent (voir migration 20260906001519) — bénéficiaire/formule
    // requis à la place. Le contrôle définitif reste côté SQL
    // (initier_transaction_cinetpay) ; cette vérification n'est qu'un
    // retour d'erreur plus lisible avant l'appel réseau.
    if (corps.typeObjetPaye === "abonnement_premium_eleve") {
      if (!corps.beneficiaireFicheEleveId || !corps.formule) {
        return reponseJson(400, { error: "beneficiaireFicheEleveId_et_formule_requis" }, origine);
      }
    } else if (!corps.etablissementId) {
      return reponseJson(400, { error: "etablissementId_requis" }, origine);
    }

    const { client: supabase } = clientUtilisateur(req);

    const { data: transaction, error: erreurInitiation } = await supabase
      .rpc("initier_transaction_cinetpay", {
        p_type_objet_paye: corps.typeObjetPaye,
        p_etablissement: corps.etablissementId ?? null,
        p_annee_scolaire: corps.anneeScolaireId ?? null,
        p_beneficiaire_fiche_eleve: corps.beneficiaireFicheEleveId ?? null,
        p_formule: corps.formule ?? null,
      })
      .single();

    if (erreurInitiation || !transaction) {
      const statut = STATUT_PAR_ERRCODE[erreurInitiation?.code ?? ""] ?? 500;
      return reponseJson(statut, { error: erreurInitiation?.message ?? "erreur_initiation" }, origine);
    }

    const service = clientService();
    const { data: config, error: erreurConfig } = await service
      .from("parametres_secrets_integration")
      .select("valeur")
      .eq("cle", "cinetpay_config")
      .single();

    const apiKey = config?.valeur?.api_key as string | null | undefined;
    const siteId = config?.valeur?.site_id as string | null | undefined;
    const notifyUrl = config?.valeur?.notify_url as string | null | undefined;

    if (erreurConfig || !apiKey || !siteId) {
      return reponseJson(503, { error: "CINETPAY_NON_CONFIGURE" }, origine);
    }

    let reponseCinetpay;
    try {
      reponseCinetpay = await initierPaiementCinetpayReel({
        apiKey,
        siteId,
        transactionId: transaction.id,
        montant: transaction.montant_attendu,
        devise: transaction.devise,
        description: `EcoShop — ${corps.typeObjetPaye}`,
        notifyUrl: notifyUrl ?? "",
        returnUrl: notifyUrl ?? "",
      });
    } catch (erreurAppel) {
      console.error(JSON.stringify({
        fn: "initier_paiement_cinetpay",
        niveau: "error",
        message: "echec appel CinetPay (initiation)",
        detail: erreurAppel instanceof Error ? erreurAppel.message : String(erreurAppel),
      }));
      return reponseJson(502, { error: "erreur_cinetpay" }, origine);
    }

    await service.rpc("finaliser_initiation_cinetpay", {
      p_transaction_id: transaction.id,
      p_reference_cinetpay: reponseCinetpay.reference_cinetpay ?? null,
    });

    return reponseJson(200, {
      transactionId: transaction.id,
      urlPaiement: reponseCinetpay.url_paiement,
    }, origine);
  } catch (erreur) {
    console.error(JSON.stringify({
      fn: "initier_paiement_cinetpay",
      niveau: "error",
      message: "erreur inattendue",
      detail: erreur instanceof Error ? erreur.message : String(erreur),
    }));
    return reponseJson(500, { error: "erreur_interne" }, req.headers.get("origin"));
  }
});
