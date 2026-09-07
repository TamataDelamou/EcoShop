# Marketplace AssoShop — Spécifications

Document de référence du volet marketplace : cadre mono-vendeur (M13) et
**accès sans authentification** (M15).

## 1. Cadre mono-vendeur (M13, rappel)

- Panier **mono-vendeur** : une commande = un seul commerçant.
- **Sous-comptes marchands** par établissement (CinetPay / Mobile Money),
  isolation stricte des encaissements.
- **Port de paiement agnostique** : `paiements.fournisseur` ∈
  {cinetpay, mobile_money}, colonnes génériques.
- Détail : `docs/M13_ASSOSHOP_MARKETPLACE.md`.

## 2. Accès sans authentification (M15)

### 2.1 Page d'accueil post-onboarding (sans auth)

Menu clair, cinq choix :

| Choix | Accès |
|---|---|
| **Marketplace** | Libre (sans mot de passe) |
| Espace Établissement | Authentification requise |
| Espace Enseignant | Authentification requise |
| Espace Parent/Élève | Authentification requise |
| Administration | Authentification requise |

### 2.2 Parcours invité (sans mot de passe)

1. L'utilisateur entre sur le catalogue (commerçants + ressources/services).
2. Si son **profil public est incomplet** → formulaire de complétion :
   nom, email, téléphone, rôle voulu, établissement si connu. **Aucun mot de
   passe demandé.**
3. Si complet → navigation libre (consultation, achat/téléchargement,
   inscription à un service/formation, prise de rendez-vous).
4. Un **UUID + jeton opaque `token_acces`** identifient le visiteur et corrèlent
   son panier. La complétion est **déduite** (nom + email/téléphone).

### 2.3 Parcours authentifié (espaces protégés)

Email + mot de passe (Auth native Supabase), redirection vers l'espace du rôle.
Aucun changement par rapport au socle M0→M3.

## 3. Contrats UI/UX

| Écran | Comportement attendu |
|---|---|
| Accueil | 5 choix, Marketplace en tête, aucun pré-requis d'auth |
| Catalogue | Lecture publique, recherche/filtres, fiche ressource |
| Complétion profil | Affichée **uniquement si profil incomplet** (divulgation progressive) |
| Panier | Mono-vendeur ; badge « non synchronisé » si hors-ligne |
| Commande invitée | Rattachée au `token_acces` ; pas de création de compte forcée |

## 4. DTO — Edge Function `creer_profil_marketplace`

**Requête** `POST /functions/v1/creer_profil_marketplace`

```json
{
  "nom": "Aminata Diallo",
  "email": "aminata@example.com",
  "telephone": "+224620001111",
  "role_voulu": "visiteur_marketplace",
  "etablissement_id": "uuid-optionnel",
  "token_acces": "uuid-optionnel (complétion d'un profil existant)"
}
```

**Réponse** `200`

```json
{ "success": true, "id": "uuid", "token_acces": "uuid", "complet": true }
```

**Erreurs** : `400` (`nom_requis`, `contact_requis`), `500` (`erreur_interne`).

## 5. Modèle de données (M15)

- `profils_publics` : identité publique du visiteur (jeton opaque, complétion,
  liaison optionnelle `profile_id` après inscription).
- `paniers.visiteur_id` / `commandes.visiteur_id` : propriétaire invité
  (contrainte `profile_id OU visiteur_id` requis).

## 6. Sécurité

- RLS **fermée par défaut** sur `profils_publics` (données personnelles) ;
  seule la lecture par l'admin GSG ou le propriétaire lié est autorisée.
- Catalogue **public en lecture** (`using (true)`) ; aucune écriture anon :
  les écritures invitées passent par l'Edge Function (service role).
- Le `token_acces` est **opaque et non élévateur de privilège** : il ne donne
  jamais accès aux espaces protégés.

## 7. Hors-ligne

- Panier invité porté en cache local (Drift), badge « non synchronisé » ;
  réconciliation via `paniers.visiteur_id` + `device_id`/`client_ts` (LWW).

## 8. Livrables

| Livrable | Chemin |
|---|---|
| DDL | `supabase/migrations/20260906001500_m15_marketplace_sans_auth.sql` |
| Edge Function | `supabase/functions/creer_profil_marketplace/index.ts` |
| Tests RLS | `tests/rls/34_m15_profils_publics.sql`, `35_m15_catalogue_public.sql`, `36_m15_panier_invite.sql` |
| Recherche comparative §17 | `docs/RECHERCHE_COMPARATIVE.md` |
