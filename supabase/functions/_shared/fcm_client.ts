// ============================================================================
// EcoShop — Client Firebase Cloud Messaging (API HTTP v1) — REG-09
//
// Authentification par compte de service Google : un JWT signé RS256
// (WebCrypto) est échangé contre un jeton d'accès OAuth 2 (1 heure), gardé
// en mémoire. Aucune bibliothèque tierce.
//
//   FCM_COMPTE_SERVICE   contenu JSON du compte de service Firebase
//                        (project_id, client_email, private_key) — secret
//                        Supabase, JAMAIS dans le dépôt.
// ============================================================================

export interface CompteServiceFcm {
  project_id: string;
  client_email: string;
  private_key: string;
}

export type VerdictPush =
  | { issue: "envoye" }
  | { issue: "jeton_invalide" }
  | { issue: "temporaire"; erreur: string };

export function compteServiceDepuisEnv(): CompteServiceFcm | null {
  const brut = Deno.env.get("FCM_COMPTE_SERVICE");
  if (!brut) return null;
  try {
    const c = JSON.parse(brut) as CompteServiceFcm;
    return c.project_id && c.client_email && c.private_key ? c : null;
  } catch {
    return null;
  }
}

function base64Url(octets: Uint8Array | string): string {
  const binaire = typeof octets === "string" ? octets : String.fromCharCode(...octets);
  return btoa(binaire).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function cleePrivee(pem: string): Promise<CryptoKey> {
  const contenu = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(contenu), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
}

let acces: { valeur: string; expireA: number } | null = null;

async function jetonAcces(compte: CompteServiceFcm): Promise<string> {
  if (acces && acces.expireA > Date.now() + 60_000) return acces.valeur;
  const maintenant = Math.floor(Date.now() / 1000);
  const entete = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const charge = base64Url(JSON.stringify({
    iss: compte.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: maintenant,
    exp: maintenant + 3600,
  }));
  const signature = new Uint8Array(await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    await cleePrivee(compte.private_key),
    new TextEncoder().encode(`${entete}.${charge}`),
  ));
  const reponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${entete}.${charge}.${base64Url(signature)}`,
    }),
  });
  if (!reponse.ok) throw new Error(`JETON_GOOGLE_${reponse.status}`);
  const corps = await reponse.json() as { access_token: string; expires_in: number };
  acces = { valeur: corps.access_token, expireA: Date.now() + corps.expires_in * 1000 };
  return corps.access_token;
}

/**
 * Destinataire du message. Depuis 2026, l'application désigne le téléphone
 * par son identifiant d'installation Firebase (FID : 22 caractères, sans
 * « : »), à envoyer dans `fid` ; les anciens jetons d'appareil, longs et
 * contenant « : », restent acceptés dans `token`.
 */
export function cible(identifiant: string): { fid: string } | { token: string } {
  return /^[A-Za-z0-9_-]{22}$/.test(identifiant) ? { fid: identifiant } : { token: identifiant };
}

export async function envoyerPush(
  compte: CompteServiceFcm,
  jeton: string,
  titre: string,
  corps: string,
  donnees: Record<string, string>,
): Promise<VerdictPush> {
  let reponse: Response;
  try {
    reponse = await fetch(`https://fcm.googleapis.com/v1/projects/${compte.project_id}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${await jetonAcces(compte)}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          ...cible(jeton),
          notification: { title: titre, body: corps },
          data: donnees,
          android: { priority: "high", notification: { channel_id: "ecoshop_alertes" } },
        },
      }),
    });
  } catch (e) {
    return { issue: "temporaire", erreur: e instanceof Error ? e.message : "FCM_INJOIGNABLE" };
  }
  if (reponse.ok) return { issue: "envoye" };
  const detail = await reponse.text().catch(() => "");
  // Application désinstallée, téléphone désinscrit ou identifiant périmé :
  // on l'oublie. Un INVALID_ARGUMENT ne vise l'identifiant que s'il le
  // nomme (sinon c'est le message lui-même qui est en cause).
  if (
    reponse.status === 404 || detail.includes("UNREGISTERED") ||
    (detail.includes("INVALID_ARGUMENT") && /message\.(fid|token)|registration/i.test(detail))
  ) {
    return { issue: "jeton_invalide" };
  }
  if (reponse.status === 401) acces = null;
  return { issue: "temporaire", erreur: `FCM_${reponse.status}` };
}
