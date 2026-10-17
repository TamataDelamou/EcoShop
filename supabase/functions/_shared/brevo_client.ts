// ============================================================================
// EcoShop — client Brevo (courriel transactionnel) — REG-04
//
// API : POST https://api.brevo.com/v3/smtp/email, en-tête `api-key`.
// Le client ne lève jamais d'exception : il renvoie un verdict que la file
// d'envoi sait appliquer (envoyé / à réessayer / échec définitif).
//
//   • 2xx                       => envoyé (messageId conservé)
//   • 429, 5xx, réseau, délai   => temporaire : nouvel essai plus tard
//   • 401 / 403                 => temporaire ET signalé : clé absente,
//                                  révoquée ou IP non autorisée — c'est une
//                                  panne de configuration, pas la faute du
//                                  destinataire ; les messages attendent sa
//                                  correction au lieu d'être perdus
//   • autres 4xx                => définitif (requête ou adresse refusée)
//
// Mode « bac à sable » : en-tête X-Sib-Sandbox: drop — Brevo valide la
// requête et répond 201 sans rien envoyer (essais avant mise en service).
// ============================================================================

export const URL_BREVO_COURRIEL = "https://api.brevo.com/v3/smtp/email";

export interface ConfigBrevo {
  cleApi: string;
  expediteur: { email: string; nom: string };
  repondreA?: string;
  bacASable?: boolean;
  delaiMs?: number;
}

export interface MessageCourriel {
  destinataire: string;
  sujet: string;
  html: string;
  texte: string;
  cleIdempotence: string;
  etiquettes?: string[];
}

export type VerdictEnvoi =
  | { issue: "envoye"; identifiant: string }
  | { issue: "temporaire"; erreur: string; alerteConfiguration?: boolean }
  | { issue: "definitif"; erreur: string };

export function corpsRequeteBrevo(config: ConfigBrevo, m: MessageCourriel): Record<string, unknown> {
  const entetes: Record<string, string> = { "X-EcoShop-Cle": m.cleIdempotence, IdempotencyKey: m.cleIdempotence };
  if (config.bacASable) entetes["X-Sib-Sandbox"] = "drop";
  const corps: Record<string, unknown> = {
    sender: { email: config.expediteur.email, name: config.expediteur.nom },
    to: [{ email: m.destinataire }],
    subject: m.sujet,
    htmlContent: m.html,
    textContent: m.texte,
    headers: entetes,
    tags: (m.etiquettes ?? []).slice(0, 10),
  };
  if (config.repondreA) corps.replyTo = { email: config.repondreA };
  return corps;
}

async function resumeErreur(rep: Response): Promise<string> {
  try {
    const corps = await rep.json() as { code?: string; message?: string };
    return `HTTP ${rep.status} ${corps.code ?? ""} ${corps.message ?? ""}`.trim().slice(0, 300);
  } catch {
    return `HTTP ${rep.status}`;
  }
}

export async function envoyerCourrielBrevo(
  config: ConfigBrevo,
  message: MessageCourriel,
  fetchImpl: typeof fetch = fetch,
): Promise<VerdictEnvoi> {
  let rep: Response;
  try {
    rep = await fetchImpl(URL_BREVO_COURRIEL, {
      method: "POST",
      headers: { "api-key": config.cleApi, "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify(corpsRequeteBrevo(config, message)),
      signal: AbortSignal.timeout(config.delaiMs ?? 10_000),
    });
  } catch (e) {
    return { issue: "temporaire", erreur: `RESEAU: ${e instanceof Error ? e.name : String(e)}` };
  }

  if (rep.ok) {
    let identifiant = "";
    try {
      const corps = await rep.json() as { messageId?: string };
      identifiant = corps.messageId ?? "";
    } catch { /* corps vide accepté */ }
    return { issue: "envoye", identifiant };
  }

  const erreur = await resumeErreur(rep);
  if (rep.status === 401 || rep.status === 403) {
    return { issue: "temporaire", erreur, alerteConfiguration: true };
  }
  if (rep.status === 429 || rep.status >= 500 || rep.status === 408) {
    return { issue: "temporaire", erreur };
  }
  return { issue: "definitif", erreur };
}
