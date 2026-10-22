// ============================================================================
// EcoShop — Vérification des appels signés « Standard Webhooks »
// (https://www.standardwebhooks.com), utilisés par les crochets HTTP de
// Supabase Auth (ex. envoi des codes SMS de connexion).
//
//   En-têtes : webhook-id, webhook-timestamp (secondes), webhook-signature
//   (« v1,<base64> », plusieurs séparées par des espaces).
//   Signature : HMAC-SHA256 de `${id}.${timestamp}.${corps}` avec la clé
//   décodée du secret « v1,whsec_<base64> » (plusieurs secrets séparés par
//   « | » pendant une rotation).
//
// Aucune bibliothèque tierce : WebCrypto seulement.
// ============================================================================

const TOLERANCE_SECONDES = 5 * 60;

function base64VersOctets(b64: string): Uint8Array<ArrayBuffer> {
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

function octetsVersBase64(octets: Uint8Array): string {
  return btoa(String.fromCharCode(...octets));
}

function egal(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/**
 * Clés HMAC décodées d'une liste « v1,whsec_…|v1,whsec_… ». Un secret mal
 * recopié est ignoré (les autres restent valables) plutôt que de tout
 * bloquer.
 */
export function clesDepuisSecrets(secrets: string): Uint8Array<ArrayBuffer>[] {
  const cles: Uint8Array<ArrayBuffer>[] = [];
  for (const brut of secrets.split("|")) {
    const b64 = brut.trim().replace(/^v1,/, "").replace(/^whsec_/, "");
    if (!b64) continue;
    try {
      cles.push(base64VersOctets(b64));
    } catch {
      // Secret illisible : ignoré.
    }
  }
  return cles;
}

export async function signer(cle: Uint8Array<ArrayBuffer>, id: string, horodatage: string, corps: string): Promise<string> {
  const k = await crypto.subtle.importKey("raw", cle, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(`${id}.${horodatage}.${corps}`));
  return octetsVersBase64(new Uint8Array(mac));
}

/**
 * `true` si l'appel est authentique et récent. `maintenant` en secondes
 * (injectable pour les tests).
 */
export async function verifierAppelSigne(
  secrets: string,
  entetes: Headers,
  corps: string,
  maintenant = Math.floor(Date.now() / 1000),
): Promise<boolean> {
  const id = entetes.get("webhook-id");
  const horodatage = entetes.get("webhook-timestamp");
  const signatures = entetes.get("webhook-signature");
  if (!id || !horodatage || !signatures) return false;
  const t = Number(horodatage);
  if (!Number.isFinite(t) || Math.abs(maintenant - t) > TOLERANCE_SECONDES) return false;

  const recues = signatures.split(" ").filter((s) => s.startsWith("v1,")).map((s) => s.slice(3));
  for (const cle of clesDepuisSecrets(secrets)) {
    const attendue = await signer(cle, id, horodatage, corps);
    if (recues.some((r) => egal(r, attendue))) return true;
  }
  return false;
}
