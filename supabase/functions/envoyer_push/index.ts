// ============================================================================
// EcoShop — Edge Function « envoyer_push » (REG-09)
//
// Envoie en notification push (Firebase Cloud Messaging) les notifications
// de l'application au canal « push » : arrivée et sortie au portail, alertes
// d'absence et de sortie anticipée, relances d'impayés, étapes des dossiers
// d'inscription. Elles restent visibles dans la boîte de notifications de
// l'application, qu'un téléphone soit enregistré ou non.
//
// Appel POST planifié (pg_cron + pg_net, chaque minute) avec l'en-tête
// `x-declencheur-secret: <NOTIFICATIONS_DECLENCHEUR_SECRET>`.
//
// Variables d'environnement (secrets Supabase) :
//   FCM_COMPTE_SERVICE                 compte de service Firebase (JSON)
//   NOTIFICATIONS_DECLENCHEUR_SECRET   secret partagé avec le planificateur
// ============================================================================

import { clientService } from "../_shared/supabase_client.ts";
import { egaliteTempsConstant } from "../_shared/interservices.ts";
import { compteServiceDepuisEnv, envoyerPush } from "../_shared/fcm_client.ts";

interface NotificationPush {
  id: string;
  destinataire: string;
  type: string;
  contenu: string;
  variables: Record<string, unknown> | null;
  jetons: string[] | null;
}

const TITRES: Record<string, string> = {
  pointage_arrivee: "Arrivée à l'école",
  pointage_sortie: "Sortie de l'école",
  alerte_absence: "Absence",
  alerte_sortie_anticipee: "Sortie avant l'heure",
  relance_impaye: "Scolarité",
};

function titre(type: string): string {
  return TITRES[type] ?? (type.startsWith("inscription_") ? "Inscription" : "EcoShop");
}

function json(status: number, corps: unknown): Response {
  return new Response(JSON.stringify(corps), { status, headers: { "Content-Type": "application/json" } });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json(405, { success: false });
  const attendu = Deno.env.get("NOTIFICATIONS_DECLENCHEUR_SECRET");
  if (!attendu || !egaliteTempsConstant(req.headers.get("x-declencheur-secret") ?? "", attendu)) {
    return json(401, { success: false, error: "NON_AUTORISE" });
  }
  const compte = compteServiceDepuisEnv();
  if (!compte) {
    // Rien n'est réservé : les notifications restent dans l'application.
    console.error(JSON.stringify({ fn: "envoyer_push", message: "FCM_COMPTE_SERVICE absent ou invalide" }));
    return json(503, { success: false, error: "CONFIGURATION_INCOMPLETE" });
  }

  const service = clientService();
  const { data, error } = await service.rpc("reserver_notifications_push", { p_limite: 200 });
  if (error) return json(500, { success: false, error: error.message });

  const bilan = { reservees: 0, envoyees: 0, sans_telephone: 0, a_reessayer: 0, jetons_oublies: 0 };
  for (const n of (data ?? []) as NotificationPush[]) {
    bilan.reservees++;
    const jetons = n.jetons ?? [];
    if (jetons.length === 0) {
      // Pas de téléphone enregistré : la notification reste lisible dans l'application.
      await service.rpc("marquer_notification_push", { p_id: n.id, p_envoyee: true, p_jetons_invalides: [] });
      bilan.sans_telephone++;
      continue;
    }
    const donnees: Record<string, string> = { type: n.type, notification_id: n.id };
    for (const [cle, valeur] of Object.entries(n.variables ?? {})) {
      if (valeur !== null && valeur !== undefined) donnees[cle] = String(valeur);
    }
    const invalides: string[] = [];
    let auMoinsUn = false;
    for (const jeton of jetons) {
      const verdict = await envoyerPush(compte, jeton, titre(n.type), n.contenu, donnees);
      if (verdict.issue === "envoye") auMoinsUn = true;
      else if (verdict.issue === "jeton_invalide") invalides.push(jeton);
    }
    const toutInvalide = invalides.length === jetons.length;
    await service.rpc("marquer_notification_push", {
      p_id: n.id,
      p_envoyee: auMoinsUn || toutInvalide,
      p_jetons_invalides: invalides,
    });
    bilan.jetons_oublies += invalides.length;
    if (auMoinsUn || toutInvalide) bilan.envoyees++;
    else bilan.a_reessayer++;
  }
  console.log(JSON.stringify({ fn: "envoyer_push", ...bilan }));
  return json(200, { success: true, bilan });
});
