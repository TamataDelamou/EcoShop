// ============================================================================
// EcoShop — jetons d'accès INTER-SERVICES avec le Control Plane du Kernel GSG
// (KER-MUT K3, docs/REGISTRE.md REG-01.3, docs/contrats/KERNEL_CONTROL_PLANE.md)
//
// JWT asymétriques ES256, jamais de secret partagé :
//   - SORTANT  (EcoShop → Kernel) : EcoShop signe avec SA clé privée ; le
//     Kernel vérifie avec la clé publique publiée par EcoShop (jwks.json).
//   - ENTRANT  (Kernel → EcoShop) : le Kernel signe avec SA clé privée ;
//     EcoShop vérifie via le JWKS du Kernel (émetteur, audience, scope,
//     durée de vie courte).
//
// Pourquoi pas mTLS : les Edge Functions Supabase ne terminent pas elles-mêmes
// le TLS et n'exposent pas le certificat client — inapplicable sans proxy.
//
// Ce module ne lit AUCUNE variable d'environnement : tout est passé en
// paramètre, ce qui le rend testable isolément (interservices_test.ts).
// ============================================================================

import {
  exportJWK,
  importJWK,
  type JWK,
  type JWTPayload,
  type JWTVerifyGetKey,
  jwtVerify,
  type KeyLike,
  SignJWT,
} from "npm:jose@5.9.6";

export const ALGORITHME = "ES256";
export const EMETTEUR_ECOSHOP = "ecoshop";
export const AUDIENCE_KERNEL = "gsg-kernel";
export const AUDIENCE_ECOSHOP = "ecoshop";
export const SCOPE_LECTURE_ECOSHOP = "ecoshop:lecture";
export const SCOPE_INGESTION_KERNEL = "kernel:ingestion";

/** Durée de vie des jetons émis par EcoShop (secondes). */
export const DUREE_JETON_SORTANT_S = 60;
/** Durée de vie maximale acceptée pour un jeton entrant (secondes). */
export const DUREE_MAX_JETON_ENTRANT_S = 300;

export class ErreurInterServices extends Error {
  constructor(public readonly code: string, message?: string) {
    super(message ?? code);
    this.name = "ErreurInterServices";
  }
}

export interface ClePrivee {
  cle: KeyLike | Uint8Array;
  kid: string;
  /** Partie publique seule (jamais d, jamais la clé privée). */
  publique: JWK;
}

/**
 * Charge la clé privée EcoShop depuis son JWK JSON (secret
 * KERNEL_INTERSERVICES_CLE_PRIVEE_JWK). Le JWK doit porter un `kid`.
 */
export async function chargerClePrivee(jwkJson: string): Promise<ClePrivee> {
  let jwk: JWK;
  try {
    jwk = JSON.parse(jwkJson);
  } catch {
    throw new ErreurInterServices("CLE_PRIVEE_ILLISIBLE");
  }
  if (jwk.kty !== "EC" || jwk.crv !== "P-256" || !jwk.d) {
    throw new ErreurInterServices("CLE_PRIVEE_INVALIDE", "JWK EC P-256 privé attendu");
  }
  if (!jwk.kid) {
    throw new ErreurInterServices("CLE_PRIVEE_SANS_KID");
  }
  const cle = await importJWK(jwk, ALGORITHME);
  const { d: _d, ...publique } = jwk;
  return {
    cle,
    kid: jwk.kid,
    publique: { ...publique, use: "sig", alg: ALGORITHME },
  };
}

/** Jeu de clés publiques EcoShop, servi à /kernel-control-plane/jwks.json. */
export function jeuDeClesPublic(cle: ClePrivee): { keys: JWK[] } {
  return { keys: [cle.publique] };
}

/** Signe un jeton court EcoShop → Kernel. */
export async function signerJetonSortant(
  cle: ClePrivee,
  options: { scope?: string; dureeS?: number; maintenantS?: number } = {},
): Promise<string> {
  const maintenant = options.maintenantS ?? Math.floor(Date.now() / 1000);
  return await new SignJWT({ scope: options.scope ?? SCOPE_INGESTION_KERNEL })
    .setProtectedHeader({ alg: ALGORITHME, kid: cle.kid, typ: "JWT" })
    .setIssuer(EMETTEUR_ECOSHOP)
    .setSubject(EMETTEUR_ECOSHOP)
    .setAudience(AUDIENCE_KERNEL)
    .setIssuedAt(maintenant)
    .setNotBefore(maintenant - 5)
    .setExpirationTime(maintenant + (options.dureeS ?? DUREE_JETON_SORTANT_S))
    .setJti(crypto.randomUUID())
    .sign(cle.cle);
}

export interface OptionsVerification {
  emetteur: string;
  audience?: string;
  scopeRequis?: string;
  dureeMaxS?: number;
  /** Pour les tests uniquement. */
  maintenant?: Date;
}

/**
 * Vérifie un jeton Kernel → EcoShop. Lève ErreurInterServices avec un code
 * stable (jamais le détail de jose, qui ne doit pas fuiter vers l'appelant).
 */
export async function verifierJetonEntrant(
  jeton: string,
  cles: JWTVerifyGetKey | KeyLike | Uint8Array,
  options: OptionsVerification,
): Promise<JWTPayload> {
  let payload: JWTPayload;
  try {
    // deno-lint-ignore no-explicit-any
    const resultat = await jwtVerify(jeton, cles as any, {
      algorithms: [ALGORITHME],
      issuer: options.emetteur,
      audience: options.audience ?? AUDIENCE_ECOSHOP,
      requiredClaims: ["iat", "exp", "jti"],
      currentDate: options.maintenant,
    });
    payload = resultat.payload;
  } catch {
    throw new ErreurInterServices("JETON_INVALIDE");
  }

  const dureeMax = options.dureeMaxS ?? DUREE_MAX_JETON_ENTRANT_S;
  if ((payload.exp as number) - (payload.iat as number) > dureeMax) {
    throw new ErreurInterServices("JETON_TROP_LONG");
  }

  const scopeRequis = options.scopeRequis ?? SCOPE_LECTURE_ECOSHOP;
  const scopes = typeof payload.scope === "string" ? payload.scope.split(" ") : [];
  if (!scopes.includes(scopeRequis)) {
    throw new ErreurInterServices("SCOPE_INSUFFISANT");
  }

  return payload;
}

/** Extrait le jeton d'un en-tête `Authorization: Bearer …`. */
export function jetonPorteur(req: Request): string {
  const [schema, jeton] = (req.headers.get("authorization") ?? "").split(" ");
  if (schema?.toLowerCase() !== "bearer" || !jeton) {
    throw new ErreurInterServices("AUTH_REQUISE");
  }
  return jeton;
}

/** Comparaison à temps constant (secret de déclenchement de l'export). */
export function egaliteTempsConstant(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  let diff = ea.length ^ eb.length;
  const n = Math.max(ea.length, eb.length);
  for (let i = 0; i < n; i++) diff |= (ea[i] ?? 0) ^ (eb[i] ?? 0);
  return diff === 0;
}

/**
 * Clé d'idempotence d'un lot : déterministe à partir du flux et des bornes,
 * pour que le Kernel puisse ignorer un lot renvoyé après un acquittement
 * perdu (livraison « au moins une fois »).
 */
export async function cleIdempotenceLot(
  flux: string,
  premierId: string,
  dernierId: string,
): Promise<string> {
  const empreinte = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(`ecoshop|${flux}|${premierId}|${dernierId}`),
  );
  return Array.from(new Uint8Array(empreinte))
    .map((o) => o.toString(16).padStart(2, "0")).join("");
}

/** Utilitaire de génération de clé (scripts/tests) — jamais appelé en prod. */
export async function exporterJwkPublic(cle: KeyLike): Promise<JWK> {
  return await exportJWK(cle);
}
