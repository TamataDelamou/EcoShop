// ============================================================================
// EcoShop — connexion avec l'identifiant EcoShop (REG-18, partie D)
//
// Logique pure, testée sans réseau (connexion_identifiant_test.ts). L'Edge
// Function `connexion_identifiant` y branche Supabase.
//
// Deux actions :
//   - « envoyer » : { identifiant } -> code envoyé à l'adresse du compte ;
//     réponse { adresseMasquee } ;
//   - « verifier » : { identifiant, code } -> session ouverte ; réponse
//     { session } (le téléphone ne voit jamais l'adresse complète).
//
// Pas d'énumération : un identifiant inconnu reçoit la MÊME réponse qu'un
// identifiant existant (adresse masquée fictive mais stable, tirée de
// l'identifiant par HMAC ; délai minimum identique) ; une vérification sur un
// identifiant inconnu échoue comme un code faux. Essais limités par
// identifiant et par adresse réseau, que l'identifiant existe ou non.
// ============================================================================

export interface Dependances {
  /** Adresse du compte actif portant cet identifiant, ou null. */
  emailPour(identifiant: string): Promise<string | null>;
  /** Enregistre un essai ; faux si la limite est atteinte. */
  noterEssai(cle: string, nature: "envoi" | "verification", minutes: number, max: number): Promise<boolean>;
  /** Demande à Supabase Auth d'envoyer un code (sans créer de compte). */
  envoyerCode(email: string): Promise<void>;
  /** Vérifie le code ; renvoie la session Supabase, ou null si refusé. */
  verifierCode(email: string, code: string): Promise<Record<string, unknown> | null>;
  /** Clé secrète pour l'adresse fictive des identifiants inconnus. */
  cleMasque: string;
  /** Attente minimale d'une réponse (égalise les durées). */
  attendre(ms: number): Promise<void>;
  /** Poursuit une tâche après la réponse (EdgeRuntime.waitUntil). */
  enArrierePlan(tache: Promise<unknown>): void;
  maintenant(): number;
}

export const LIMITES = {
  envoiParIdentifiant: { minutes: 60, max: 5 },
  envoiParReseau: { minutes: 60, max: 30 },
  verificationParIdentifiant: { minutes: 15, max: 10 },
  verificationParReseau: { minutes: 15, max: 60 },
  dureeMinimaleMs: 800,
} as const;

export type Reponse = { statut: number; corps: Record<string, unknown> };

const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

/** Caractère de contrôle Luhn mod 32 (même calcul que la base). */
export function caractereControle(corps: string): string {
  let facteur = 2;
  let somme = 0;
  for (let i = corps.length - 1; i >= 0; i--) {
    const valeur = ALPHABET.indexOf(corps[i]);
    if (valeur < 0) throw new Error("CARACTERE_INVALIDE");
    const ajout = facteur * valeur;
    facteur = facteur === 2 ? 1 : 2;
    somme += Math.floor(ajout / 32) + (ajout % 32);
  }
  return ALPHABET[(32 - (somme % 32)) % 32];
}

/** Forme EC-XXXX-XXC, ou null si la saisie n'est pas un identifiant valide. */
export function normaliserIdentifiant(saisie: string): string | null {
  const v = saisie.toUpperCase().replace(/[\s-]/g, "").replace(/O/g, "0").replace(/[IL]/g, "1");
  if (!/^EC[0-9A-HJKMNP-TV-Z]{7}$/.test(v)) return null;
  if (caractereControle(v.substring(2, 8)) !== v[8]) return null;
  return `EC-${v.substring(2, 6)}-${v.substring(6, 9)}`;
}

/** « awa.bah@gmail.com » -> « a•••@gmail.com ». */
export function masquerAdresse(email: string): string {
  const [local, domaine] = email.split("@");
  return `${(local ?? "?").charAt(0)}•••@${domaine ?? ""}`;
}

async function adresseFictive(identifiant: string, cle: string): Promise<string> {
  const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(cle), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(`masque:${identifiant}`)));
  const lettres = "abcdefghijklmnopqrstuvwxyz";
  const domaines = ["gmail.com", "gmail.com", "gmail.com", "yahoo.fr", "outlook.com"];
  return `${lettres[sig[0] % 26]}•••@${domaines[sig[1] % domaines.length]}`;
}

export async function traiter(
  corps: { action?: string; identifiant?: string; code?: string },
  adresseReseau: string,
  d: Dependances,
): Promise<Reponse> {
  const debut = d.maintenant();
  const egaliser = async (r: Reponse) => {
    const reste = LIMITES.dureeMinimaleMs - (d.maintenant() - debut);
    if (reste > 0) await d.attendre(reste);
    return r;
  };

  const identifiant = normaliserIdentifiant(String(corps.identifiant ?? ""));
  if (!identifiant) return { statut: 400, corps: { success: false, error: "IDENTIFIANT_INVALIDE" } };

  if (corps.action === "envoyer") {
    const okId = await d.noterEssai(`id:${identifiant}`, "envoi", LIMITES.envoiParIdentifiant.minutes, LIMITES.envoiParIdentifiant.max);
    const okReseau = await d.noterEssai(`ip:${adresseReseau}`, "envoi", LIMITES.envoiParReseau.minutes, LIMITES.envoiParReseau.max);
    if (!okId || !okReseau) {
      return egaliser({ statut: 429, corps: { success: false, error: "TROP_DE_TENTATIVES" } });
    }
    const email = await d.emailPour(identifiant);
    if (email) {
      // Envoi en arrière-plan : la réponse ne l'attend pas, sa durée ne
      // dépend donc pas de l'existence du compte. Un refus de Supabase
      // (limite d'envoi) ne change pas non plus la réponse.
      d.enArrierePlan(d.envoyerCode(email).catch(() => {}));
    }
    const adresseMasquee = email ? masquerAdresse(email) : await adresseFictive(identifiant, d.cleMasque);
    return egaliser({ statut: 200, corps: { success: true, adresseMasquee } });
  }

  if (corps.action === "verifier") {
    const code = String(corps.code ?? "").trim();
    if (!/^[0-9]{6}$/.test(code)) return { statut: 400, corps: { success: false, error: "OTP_EXPIRED" } };
    const okId = await d.noterEssai(`id:${identifiant}`, "verification",
      LIMITES.verificationParIdentifiant.minutes, LIMITES.verificationParIdentifiant.max);
    const okReseau = await d.noterEssai(`ip:${adresseReseau}`, "verification",
      LIMITES.verificationParReseau.minutes, LIMITES.verificationParReseau.max);
    if (!okId || !okReseau) {
      return egaliser({ statut: 429, corps: { success: false, error: "TROP_DE_TENTATIVES" } });
    }
    const email = await d.emailPour(identifiant);
    const session = email ? await d.verifierCode(email, code) : null;
    if (!session) return egaliser({ statut: 400, corps: { success: false, error: "OTP_EXPIRED" } });
    return { statut: 200, corps: { success: true, session } };
  }

  return { statut: 400, corps: { success: false, error: "ACTION_INCONNUE" } };
}
