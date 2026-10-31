# Site de Global Service Groupe — pages légales (REG-31)

Première pierre du site `globalservicegroupe.com`, qui présentera toutes les
applications de GSG. Ce dossier est **autonome** : il pourra être déplacé tel
quel dans le dépôt du futur site.

| Adresse | Fichier | Rôle |
|---|---|---|
| `/` | `index.html` | Accueil provisoire (liste des applications) |
| `/confidentialite/` | `confidentialite/index.html` | Politique de confidentialité — déclarée sur l'écran de consentement Google et à déclarer au Play Store |
| `/conditions/` | `conditions/index.html` | Conditions d'utilisation — déclarées sur l'écran de consentement Google |
| `/suppression-compte/` | `suppression-compte/index.html` | Lien « suppression de compte » exigé par le formulaire *Sécurité des données* du Play Store |
| `/certificat/` | `certificat/index.html` | Vérifier un certificat de maîtrise EcoShop sans compte (REG-38) : formulaire vers la fonction publique `verifier_certificat` — remplacer `⟦URL_PROJET⟧` par l'adresse du projet Supabase de production |

Une seule politique et une seule page de conditions pour tout GSG : une partie
commune (nos promesses, vos droits), puis **une section par application**
(`#ecoshop`). Pour une nouvelle application, ajouter sa section
`<section class="application" id="…">` et une entrée au sommaire.

HTML et CSS seuls : aucun script, aucune police à télécharger, aucun
traceur — pages légères sur un réseau mobile lent, thème sombre automatique.

## Avant de publier

1. **Compléter les deux champs entre ⟦ ⟧** (adresse du siège, numéro RCCM)
   dans `confidentialite/index.html` et `conditions/index.html` :
   ```
   rechercher : ⟦
   ```
2. **Faire relire par l'avocat** (feuille de route REG-30, point 10), en
   particulier : responsable / sous-traitant (école ↔ GSG), transferts hors
   de Guinée (loi L/2016/037/AN : autorisation préalable de l'autorité),
   déclaration préalable des traitements, données des mineurs, clause de
   responsabilité, juridiction.
3. **Déclarations à l'autorité guinéenne** : la politique annonce que GSG
   effectue les démarches de déclaration et d'autorisation de transfert —
   à engager en parallèle de la publication.

## Mettre en ligne (Cloudflare Pages, gratuit)

Le domaine est déjà géré par Cloudflare (DNS et routage des e-mails).

1. Tableau de bord Cloudflare › **Workers & Pages** › **Créer** › onglet
   **Pages** › **Importer des ressources** (*Upload assets*).
2. Nom du projet : `gsg-site`. Déposer **le contenu** du dossier `site_gsg`
   (pas le dossier lui-même), puis **Déployer**.
3. Onglet **Domaines personnalisés** › ajouter `globalservicegroupe.com`
   (et `www.globalservicegroupe.com`). Cloudflare crée l'enregistrement DNS ;
   les e-mails (contact@, direction@) ne sont pas touchés.
4. Vérifier : `https://globalservicegroupe.com/confidentialite`,
   `/conditions` et `/suppression-compte` s'ouvrent (Cloudflare ajoute la
   barre finale tout seul).

Mise à jour : même écran, **Créer un déploiement**, déposer de nouveau le
dossier.

## Ensuite, côté Google

- **Play Console** › Contenu de l'application › *Règles de confidentialité* :
  `https://globalservicegroupe.com/confidentialite/`.
- **Play Console** › *Sécurité des données* › suppression des données :
  « Oui, les utilisateurs peuvent demander la suppression » et
  `https://globalservicegroupe.com/suppression-compte/`.
- **Écran de consentement OAuth** (Google Cloud) : adresses déjà déclarées ;
  le logo peut désormais être ajouté.
