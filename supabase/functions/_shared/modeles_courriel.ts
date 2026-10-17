// ============================================================================
// EcoShop — modèles de courriels transactionnels (REG-04)
//
// Rendu 100 % côté code, sans dépendance au gabarit Brevo : le contenu est
// versionné avec le dépôt, testé, et ne peut pas être modifié par erreur dans
// une console. Principes retenus (pratiques de délivrabilité 2025-2026) :
//   • version texte TOUJOURS fournie à côté du HTML (filtres anti-spam,
//     messageries basiques, lecteurs d'écran) ;
//   • mise en page en tableaux, styles en ligne, 600 px max, lisible sur
//     mobile d'entrée de gamme et en mode sombre (pas de texte sur image) ;
//   • texte d'aperçu (« preheader ») explicite ;
//   • aucune image distante ni pixel de suivi : rien à télécharger sur une
//     connexion mobile lente, aucune donnée de lecture collectée ;
//   • toute donnée saisie par un utilisateur est échappée.
// ============================================================================

export type ModeleCourriel =
  | "demande_etablissement_recue"
  | "demande_etablissement_a_traiter"
  | "demande_etablissement_acceptee"
  | "demande_etablissement_refusee";

export interface ContexteCourriel {
  /** Lien d'ouverture de l'application (site ou page de téléchargement). */
  urlApplication: string;
  /** Adresse de contact affichée en pied de message. */
  adresseSupport: string;
}

export interface CourrielRendu {
  sujet: string;
  html: string;
  texte: string;
}

export class ModeleInconnu extends Error {
  constructor(modele: string) {
    super(`MODELE_INCONNU: ${modele}`);
    this.name = "ModeleInconnu";
  }
}

const COULEUR_PRINCIPALE = "#0B6E4F";
const COULEUR_TEXTE = "#1F2933";
const COULEUR_DOUCE = "#52606D";

export function echapperHtml(valeur: unknown): string {
  return String(valeur ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function texteDe(donnees: Record<string, unknown>, cle: string, defaut = ""): string {
  const v = donnees[cle];
  if (v === null || v === undefined) return defaut;
  return String(v).trim() || defaut;
}

interface Contenu {
  sujet: string;
  apercu: string;
  titre: string;
  paragraphes: string[];        // texte brut, échappé au rendu
  encadre?: { titre: string; lignes: Array<[string, string]> };
  bouton?: { libelle: string; url: string };
  conclusion?: string;
}

function contenuPour(modele: string, d: Record<string, unknown>, ctx: ContexteCourriel): Contenu {
  const prenom = texteDe(d, "prenom");
  const salutation = prenom ? `Bonjour ${prenom},` : "Bonjour,";
  const ecole = texteDe(d, "nom_etablissement", "votre établissement");
  const reference = texteDe(d, "reference");
  const lieu = [texteDe(d, "ville"), texteDe(d, "pays")].filter(Boolean).join(", ");

  const recap = {
    titre: "Votre demande",
    lignes: [
      ["Établissement", ecole],
      ["Localisation", lieu || "—"],
      ["Référence", reference || "—"],
    ] as Array<[string, string]>,
  };

  switch (modele as ModeleCourriel) {
    case "demande_etablissement_recue":
      return {
        sujet: `Demande reçue : ${ecole}`,
        apercu: "Nous avons bien reçu votre demande d'ouverture d'établissement sur EcoShop.",
        titre: "Votre demande est bien reçue",
        paragraphes: [
          salutation,
          `Merci d'avoir choisi EcoShop pour ${ecole}. Votre demande d'ouverture a bien été enregistrée et sera examinée par l'équipe Global Service Groupe.`,
          "Nous pouvons vous contacter pour vérifier les informations fournies (autorisation d'ouverture, coordonnées). Vous recevrez un nouveau message dès qu'une décision sera prise.",
        ],
        encadre: recap,
        conclusion: "Conservez la référence ci-dessus : elle vous sera demandée si vous nous contactez.",
      };
    case "demande_etablissement_acceptee":
      return {
        sujet: `Bienvenue sur EcoShop : ${ecole} est ouvert`,
        apercu: "Votre établissement est créé. Vous pouvez dès maintenant le configurer.",
        titre: "Votre établissement est ouvert",
        paragraphes: [
          salutation,
          `Bonne nouvelle : la demande pour ${ecole} est acceptée. L'établissement est créé et votre compte dispose désormais du rôle Direction.`,
          "Prochaines étapes conseillées : personnaliser l'identité visuelle (logo, couleur), créer les classes et l'année scolaire, puis inviter votre équipe.",
        ],
        encadre: recap,
        bouton: { libelle: "Ouvrir EcoShop", url: ctx.urlApplication },
      };
    case "demande_etablissement_refusee":
      return {
        sujet: `Votre demande pour ${ecole} n'a pas pu être acceptée`,
        apercu: "Votre demande nécessite une correction avant de pouvoir être acceptée.",
        titre: "Votre demande doit être complétée",
        paragraphes: [
          salutation,
          `Après examen, la demande pour ${ecole} n'a pas pu être acceptée en l'état.`,
          `Motif indiqué par notre équipe : ${texteDe(d, "motif", "non précisé")}`,
          "Vous pouvez soumettre une nouvelle demande corrigée depuis l'application, à tout moment.",
        ],
        encadre: recap,
        bouton: { libelle: "Soumettre une nouvelle demande", url: ctx.urlApplication },
      };
    case "demande_etablissement_a_traiter": {
      const effectif = d["effectif_estime"];
      return {
        sujet: `[Backoffice] Nouvelle demande : ${ecole}${lieu ? ` (${lieu})` : ""}`,
        apercu: "Une nouvelle demande d'ouverture d'établissement attend une décision.",
        titre: "Nouvelle demande à traiter",
        paragraphes: [
          "Une nouvelle demande d'ouverture d'établissement attend une décision dans le backoffice (menu « Demandes d'établissement »).",
        ],
        encadre: {
          titre: "Demande",
          lignes: [
            ...recap.lignes,
            ["Effectif estimé", effectif === null || effectif === undefined ? "—" : String(effectif)],
          ],
        },
        bouton: { libelle: "Ouvrir le backoffice", url: ctx.urlApplication },
      };
    }
    default:
      throw new ModeleInconnu(modele);
  }
}

function rendreHtml(c: Contenu, ctx: ContexteCourriel): string {
  const paragraphes = c.paragraphes
    .map((p) => `<p style="margin:0 0 16px;font-size:16px;line-height:24px;color:${COULEUR_TEXTE};">${echapperHtml(p)}</p>`)
    .join("");
  const encadre = c.encadre
    ? `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:8px 0 20px;border:1px solid #D9E2EC;border-radius:8px;">
<tr><td style="padding:14px 16px 6px;font-size:13px;font-weight:bold;letter-spacing:.04em;text-transform:uppercase;color:${COULEUR_DOUCE};">${echapperHtml(c.encadre.titre)}</td></tr>
${c.encadre.lignes.map(([k, v]) => `<tr><td style="padding:4px 16px;font-size:15px;line-height:22px;color:${COULEUR_TEXTE};"><span style="color:${COULEUR_DOUCE};">${echapperHtml(k)} :</span> <strong>${echapperHtml(v)}</strong></td></tr>`).join("\n")}
<tr><td style="height:10px;line-height:10px;font-size:0;">&nbsp;</td></tr>
</table>`
    : "";
  const bouton = c.bouton
    ? `<table role="presentation" cellpadding="0" cellspacing="0" style="margin:4px 0 24px;"><tr><td style="border-radius:6px;background:${COULEUR_PRINCIPALE};">
<a href="${echapperHtml(c.bouton.url)}" style="display:inline-block;padding:14px 26px;font-size:16px;font-weight:bold;color:#FFFFFF;text-decoration:none;border-radius:6px;">${echapperHtml(c.bouton.libelle)}</a>
</td></tr></table>`
    : "";
  const conclusion = c.conclusion
    ? `<p style="margin:0 0 16px;font-size:14px;line-height:22px;color:${COULEUR_DOUCE};">${echapperHtml(c.conclusion)}</p>`
    : "";

  return `<!doctype html>
<html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light dark"><meta name="supported-color-schemes" content="light dark">
<title>${echapperHtml(c.sujet)}</title></head>
<body style="margin:0;padding:0;background:#F0F4F8;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">${echapperHtml(c.apercu)}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F0F4F8;">
<tr><td align="center" style="padding:24px 12px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;background:#FFFFFF;border-radius:10px;font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
<tr><td style="padding:20px 28px;background:${COULEUR_PRINCIPALE};border-radius:10px 10px 0 0;font-size:20px;font-weight:bold;color:#FFFFFF;">EcoShop</td></tr>
<tr><td style="padding:28px 28px 8px;">
<h1 style="margin:0 0 20px;font-size:22px;line-height:30px;color:${COULEUR_TEXTE};">${echapperHtml(c.titre)}</h1>
${paragraphes}
${encadre}
${bouton}
${conclusion}
</td></tr>
<tr><td style="padding:18px 28px 24px;border-top:1px solid #E4E7EB;font-size:12px;line-height:18px;color:${COULEUR_DOUCE};">
Message automatique envoyé par EcoShop, une application de Global Service Groupe. Merci de ne pas y répondre directement : écrivez-nous à
<a href="mailto:${echapperHtml(ctx.adresseSupport)}" style="color:${COULEUR_PRINCIPALE};">${echapperHtml(ctx.adresseSupport)}</a>.
</td></tr>
</table></td></tr></table>
</body></html>`;
}

function rendreTexte(c: Contenu, ctx: ContexteCourriel): string {
  const lignes: string[] = [c.titre.toUpperCase(), "", ...c.paragraphes.flatMap((p) => [p, ""])];
  if (c.encadre) {
    lignes.push(`${c.encadre.titre} :`);
    for (const [k, v] of c.encadre.lignes) lignes.push(`  - ${k} : ${v}`);
    lignes.push("");
  }
  if (c.bouton) lignes.push(`${c.bouton.libelle} : ${c.bouton.url}`, "");
  if (c.conclusion) lignes.push(c.conclusion, "");
  lignes.push("--", `EcoShop · Global Service Groupe · ${ctx.adresseSupport}`);
  return lignes.join("\n");
}

export function rendreCourriel(
  modele: string,
  donnees: Record<string, unknown>,
  ctx: ContexteCourriel,
): CourrielRendu {
  const c = contenuPour(modele, donnees ?? {}, ctx);
  // Un sujet ne doit jamais contenir de saut de ligne (injection d'en-têtes).
  const sujet = c.sujet.replace(/[\r\n]+/g, " ").slice(0, 150);
  return { sujet, html: rendreHtml(c, ctx), texte: rendreTexte(c, ctx) };
}
