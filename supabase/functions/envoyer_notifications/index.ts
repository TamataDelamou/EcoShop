// ============================================================================
// EcoShop — Edge Function « envoyer_notifications » (REG-04)
//
// Vide la file `notifications_sortantes` (migration 20260906001533) vers
// Brevo. Appel POST planifié (pg_cron + pg_net, toutes les minutes
// recommandé) avec l'en-tête `x-declencheur-secret: <NOTIFICATIONS_DECLENCHEUR_SECRET>`.
//
// Variables d'environnement (secrets Supabase, JAMAIS dans le dépôt) :
//   BREVO_API_KEY                   clé API Brevo (obligatoire)
//   NOTIFICATIONS_DECLENCHEUR_SECRET secret partagé avec le planificateur
//   COURRIEL_EXPEDITEUR             défaut ne-pas-repondre@globalservicegroupe.com
//   COURRIEL_EXPEDITEUR_NOM         défaut « EcoShop »
//   COURRIEL_SUPPORT                adresse de contact affichée et « répondre à »
//                                   (défaut contact@globalservicegroupe.com)
//   COURRIEL_ADMIN_GSG              destinataire(s) des alertes backoffice,
//                                   séparés par des virgules
//   URL_APPLICATION                 lien des boutons (défaut https://globalservicegroupe.com)
//   BREVO_BAC_A_SABLE=1             valide chez Brevo sans rien envoyer
//
// Un échec sur un message n'arrête jamais les suivants.
// ============================================================================

import { clientService } from "../_shared/supabase_client.ts";
import { egaliteTempsConstant } from "../_shared/interservices.ts";
import { type ConfigBrevo, envoyerCourrielBrevo } from "../_shared/brevo_client.ts";
import { ModeleInconnu, rendreCourriel } from "../_shared/modeles_courriel.ts";

interface Notification {
  id: string;
  canal: string;
  modele: string;
  destinataire: string | null;
  destinataire_role: string | null;
  donnees: Record<string, unknown>;
  cle_idempotence: string;
  tentatives: number;
}

function json(status: number, corps: unknown): Response {
  return new Response(JSON.stringify(corps), { status, headers: { "Content-Type": "application/json" } });
}

function journal(niveau: "info" | "warn" | "error", message: string, extra: Record<string, unknown> = {}) {
  console[niveau === "info" ? "log" : niveau](JSON.stringify({ fn: "envoyer_notifications", niveau, message, ...extra }));
}

/** Masque une adresse dans les journaux : a***@domaine.org */
function masquer(adresse: string): string {
  const [local, domaine] = adresse.split("@");
  return `${(local ?? "").slice(0, 1)}***@${domaine ?? ""}`;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json(405, { success: false });

  const attendu = Deno.env.get("NOTIFICATIONS_DECLENCHEUR_SECRET");
  if (!attendu || !egaliteTempsConstant(req.headers.get("x-declencheur-secret") ?? "", attendu)) {
    return json(401, { success: false, error: "NON_AUTORISE" });
  }

  const cleApi = Deno.env.get("BREVO_API_KEY");
  if (!cleApi) {
    // Rien n'est réservé : les messages restent en file jusqu'à la configuration.
    journal("error", "BREVO_API_KEY absente — aucun envoi");
    return json(503, { success: false, error: "CONFIGURATION_INCOMPLETE" });
  }

  const support = Deno.env.get("COURRIEL_SUPPORT") ?? "contact@globalservicegroupe.com";
  const config: ConfigBrevo = {
    cleApi,
    expediteur: {
      email: Deno.env.get("COURRIEL_EXPEDITEUR") ?? "ne-pas-repondre@globalservicegroupe.com",
      nom: Deno.env.get("COURRIEL_EXPEDITEUR_NOM") ?? "EcoShop",
    },
    repondreA: support,
    bacASable: Deno.env.get("BREVO_BAC_A_SABLE") === "1",
  };
  const contexte = {
    urlApplication: Deno.env.get("URL_APPLICATION") ?? "https://globalservicegroupe.com",
    adresseSupport: support,
  };
  const adminsGsg = (Deno.env.get("COURRIEL_ADMIN_GSG") ?? "")
    .split(",").map((a) => a.trim()).filter((a) => a.includes("@"));

  const service = clientService();
  const bilan = { reservees: 0, envoyees: 0, reprogrammees: 0, echecs_definitifs: 0, erreurs: 0 };

  const { data, error } = await service.rpc("reserver_notifications", { p_limite: 25 });
  if (error) {
    journal("error", "réservation impossible", { detail: error.message });
    return json(500, { success: false });
  }
  const lot = (data ?? []) as Notification[];
  bilan.reservees = lot.length;

  let alerteConfiguration = false;

  for (const n of lot) {
    try {
      if (n.canal !== "email") {
        await service.rpc("marquer_notification_echec", { p_id: n.id, p_erreur: "CANAL_NON_PRIS_EN_CHARGE", p_definitif: true });
        bilan.echecs_definitifs++;
        continue;
      }

      const destinataires = n.destinataire ? [n.destinataire] : n.destinataire_role === "admin_gsg" ? adminsGsg : [];
      if (destinataires.length === 0) {
        await service.rpc("marquer_notification_echec", { p_id: n.id, p_erreur: "AUCUN_DESTINATAIRE_CONFIGURE", p_definitif: false });
        bilan.reprogrammees++;
        continue;
      }

      const rendu = rendreCourriel(n.modele, n.donnees, contexte);

      // Brevo : un appel par destinataire, pour que personne ne voie l'adresse des autres.
      const identifiants: string[] = [];
      let echec: { erreur: string; definitif: boolean } | null = null;
      for (const [i, dest] of destinataires.entries()) {
        const verdict = await envoyerCourrielBrevo(config, {
          destinataire: dest,
          sujet: rendu.sujet,
          html: rendu.html,
          texte: rendu.texte,
          cleIdempotence: destinataires.length > 1 ? `${n.cle_idempotence}#${i}` : n.cle_idempotence,
          etiquettes: ["ecoshop", n.modele],
        });
        if (verdict.issue === "envoye") {
          identifiants.push(verdict.identifiant);
        } else {
          if (verdict.issue === "temporaire" && verdict.alerteConfiguration) alerteConfiguration = true;
          echec = { erreur: verdict.erreur, definitif: verdict.issue === "definitif" };
          journal("warn", "envoi refusé", { notificationId: n.id, destinataire: masquer(dest), erreur: verdict.erreur });
          break;
        }
      }

      if (echec) {
        const { data: issue } = await service.rpc("marquer_notification_echec", {
          p_id: n.id, p_erreur: echec.erreur, p_definitif: echec.definitif,
        });
        if (issue === "echec_definitif") bilan.echecs_definitifs++;
        else bilan.reprogrammees++;
      } else {
        await service.rpc("marquer_notification_envoyee", { p_id: n.id, p_identifiant_fournisseur: identifiants.join(",") });
        bilan.envoyees++;
      }

      // Clé invalide : inutile d'user les tentatives des messages suivants.
      if (alerteConfiguration) break;
    } catch (erreur) {
      bilan.erreurs++;
      const definitif = erreur instanceof ModeleInconnu;
      await service.rpc("marquer_notification_echec", {
        p_id: n.id,
        p_erreur: erreur instanceof Error ? erreur.message : String(erreur),
        p_definitif: definitif,
      });
      journal("error", "traitement impossible", { notificationId: n.id, definitif });
    }
  }

  // Les messages réservés mais non traités (arrêt sur alerte) seront repris
  // à l'expiration de leur bail (5 min).
  if (alerteConfiguration) journal("error", "Brevo refuse la clé API (401/403) : vérifier BREVO_API_KEY et les IP autorisées");

  journal("info", "passage terminé", bilan);
  return json(200, { success: true, bilan, alerte_configuration: alerteConfiguration });
});
