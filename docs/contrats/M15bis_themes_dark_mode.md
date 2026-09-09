# M15bis — Thèmes internationaux & Dark Mode — Contrat de module

> Module **purement client** (aucune migration SQL, aucun contrat DTO/RPC) —
> inséré dans la séquence de construction entre M15 (livré) et M16 (IA à
> rôles, qui conserve son numéro et son contenu inchangés), conformément à la
> règle transversale ANALYSE_GLOBALE.md §4.2.5.
> Code : `apps/client_flutter/lib/core/theme/`, `apps/client_flutter/lib/features/themes/`.
> Tests : `apps/client_flutter/test/core/theme/`, `apps/client_flutter/test/features/themes/`.

## 1. Périmètre

1. Deux nouvelles chartes graphiques d'établissement, alignées sur les 4
   familles du référentiel pédagogique CEDEAO (`public.type_systeme_educatif`,
   M4) : **anglophone_waec** et **lusophone**. `arabophone_mixte` n'a pas
   encore de charte dédiée (différé — voir §6) ; `francophone_cfa` reste la
   charte « Innovation & Énergie » déjà approuvée (cahier v4.1 ch. 2),
   inchangée par ce module.
2. Un **mode sombre** réellement fonctionnel, couvrant l'ensemble de
   l'application (les ~76 fichiers d'écrans existants inclus), avec des
   couleurs propres à chaque luminosité — pas une inversion algorithmique des
   couleurs claires — et vérifiées au contraste WCAG AA.
3. Persistance locale du choix clair/sombre/système de l'utilisateur.
4. Sélection automatique (non manuelle) de la charte graphique selon le pays
   pédagogique de l'établissement actif.

## 2. Architecture

### 2.1 `AppThemeVariant` (`core/theme/app_theme_variant.dart`)

Enum à 3 valeurs (`francophoneCfa`, `anglophoneWaec`, `lusophone`), chacune
portant son `codeSystemeEducatif` (`type_systeme_educatif` de M4).
`AppThemeVariant.depuisCodeSysteme(code)` résout la variante ; retombe sur
`francophoneCfa` pour `arabophone_mixte` et tout code inconnu/absent.

### 2.2 `AppPalette` (`core/theme/app_palette.dart`)

`ThemeExtension<AppPalette>` — remplace les anciennes constantes statiques
`AppColors.xxx`. Champs : `fond, surface, bordure, encre, encreSecondaire,
primaire, accent, succes, premium, erreur`. Accès via l'extension
`context.palette` (retombe sur la charte francophone_cfa claire si aucun
`AppPalette` n'est enregistré dans le thème ambiant — cas d'un `MaterialApp`
de test construit sans `construireThemeData`).

### 2.3 `AppPalettes` (`core/theme/app_palettes.dart`)

Catalogue statique des 6 palettes (3 variantes × clair/sombre).
`AppPalettes.pour(variante, brightness)` sélectionne la bonne instance.

### 2.4 `construireThemeData` (`core/theme/app_theme.dart`)

Construit le `ThemeData` Material 3 d'une (variante, luminosité) : enregistre
la palette comme extension, dérive `ColorScheme`, `AppBarTheme`, `CardTheme`,
`FilledButtonTheme`, `InputDecorationTheme`, `TextTheme`. En mode sombre, le
texte du bouton primaire utilise le ton `fond` de la palette (le plus sombre)
plutôt que `encre` (clair en mode sombre, ce qui donnerait un contraste de
~2:1) ou un blanc fixe (contraste insuffisant sur une couleur déjà éclaircie
pour le mode sombre) — voir la mesure exacte en §3.

### 2.5 Providers (`features/themes/application/theme_providers.dart`)

- `themeModeProvider` (`AsyncNotifierProvider<ThemeModeNotifier, ThemeMode>`) —
  charge la préférence persistée au démarrage, expose `definir(mode)`.
- `themeVariantProvider` — dérive la variante de `etablissementActifProvider`
  (`paysCode`) croisé avec `paysPedagogiquesProvider` (M4, `type_systeme`).
  **Ce n'est jamais un choix libre de l'utilisateur** : la charte reflète le
  système éducatif réel de l'établissement. Repli sur `francophoneCfa` tant
  que l'établissement ou le référentiel n'est pas chargé.

### 2.6 Persistance (`features/themes/data/theme_preference_store.dart`)

Réutilise le `CacheDocumentStore` générique (Drift, déjà partagé par M5+)
avec le domaine `'preferences'`, plutôt que d'ajouter une dépendance
`shared_preferences` pour un seul champ. Cohérent avec le principe
« hors-ligne prioritaire » : un réglage d'affichage ne doit jamais attendre un
aller-retour réseau. Aucune migration Drift nécessaire (table `CacheEntries`
déjà existante).

### 2.7 UI (`features/themes/presentation/ecran_preferences_apparence.dart`)

Écran « Apparence » : bascule clair/sombre/système (`RadioGroup`, cohérent
avec le reste du client) + rappel en lecture seule de la charte active et de
sa provenance (référentiel pédagogique). Accessible depuis l'onglet Profil
(`coquille_app.dart`, entrée « Apparence »).

### 2.8 `main.dart`

`EcoShopApp` (converti en `ConsumerWidget`) watch `themeVariantProvider` et
`themeModeProvider` pour construire `theme`/`darkTheme`/`themeMode` du
`MaterialApp`. En **mode diagnostic** (`Env.estConfigure == false`, aucun
`--dart-define` Supabase), ces providers ne sont **pas** regardés — ils
dérivent transitivement de la session Supabase (`etablissementActifProvider`
→ `authRepositoryProvider` → `Supabase.instance`), qui n'existe pas encore
dans ce mode. La charte par défaut (`francophoneCfa`, `ThemeMode.system`) est
utilisée à la place, exactement comme avant ce module.

## 3. Vérification du contraste (WCAG AA)

Chacune des 6 palettes est vérifiée par le test
`test/core/theme/app_palettes_test.dart` :

- Texte principal (`encre`) et secondaire (`encreSecondaire`) sur `fond` :
  ≥ 4.5:1 (texte normal), pour les 6 combinaisons.
- Pour les 2 nouvelles chartes (`anglophone_waec`, `lusophone`, clair et
  sombre) : `accent`, `succes`, `premium`, `erreur` utilisés comme texte
  direct sur `fond` (usage réel confirmé dans le code — badges, montants,
  statuts) : ≥ 4.5:1.
- Bouton primaire (texte sur fond `primaire`) : ≥ 4.5:1 dans les 6 palettes —
  blanc en mode clair, ton `fond` de la palette en mode sombre (voir §2.4).

`francophone_cfa` clair n'est **pas** re-vérifié : c'est la charte
« Innovation & Énergie » déjà approuvée par le cahier v4.1, ses teintes
d'accent ne sont pas modifiées par ce module (voir aussi §6 sur une dette
d'accessibilité pré-existante non traitée ici).

## 4. Résolution des problèmes hérités

1. **Aucun mode sombre fonctionnel n'existait dans la cible** : un seul thème
   clair (`appTheme()`, thème unique, aucune extension). Résolu : 6 palettes
   couvrant les 3 variantes × 2 luminosités, réellement branchées et
   basculables sans redémarrage.
2. **~76 fichiers d'écrans lisaient des couleurs figées à la compilation**
   (`AppColors.xxx`, `static const Color`, dont 106 usages en `const`) — un
   thème dynamique n'aurait donc eu strictement aucun effet sur l'écran une
   fois affiché. Résolu : migration complète de ces fichiers vers
   `context.palette.xxx` (`AppPalette`, `ThemeExtension`, réactif au thème
   Material ambiant), `const` retiré partout où la valeur n'est plus une
   constante de compilation. `flutter analyze` propre et 233 tests passent
   après migration.
3. `lib/core/theme/app_colors.dart` (les anciennes constantes) est
   **supprimé** — plus aucune référence dans le code après migration.

## 5. Rapport d'écart fonctionnel vs `ecoshop_flutter`

Conformément à la règle transversale ANALYSE_GLOBALE.md §4.2.5.

| Fonctionnalité | ecoshop_flutter (source) | EcoShop (cible, ce module) | Écart |
|---|---|---|---|
| Thème sombre défini | `core/theme/app_theme.dart` définit `AppTheme.light()` et `AppTheme.dark()` complets | 6 palettes (3 variantes × 2 luminosités) | Dépassé |
| Thème sombre **activé** | `main.dart:77` — `themeMode: ThemeMode.light` **figé en dur** : le thème sombre existe dans le code mais n'est **jamais atteignable** par un utilisateur (aucun bouton, aucune préférence, mort depuis l'écriture) | Bascule clair/sombre/système fonctionnelle, persistée, exposée dans Profil → Apparence | **Le mode sombre n'a en réalité jamais été livré côté source** — ce n'est donc pas une régression corrigée mais une fonctionnalité neuve menée à terme |
| Personnalisation de charte par établissement | Commentaire dans `app_theme.dart` source : « Personnalisation par établissement (module 11, mode payant) : injecter `primaryOverride`/`secondaryOverride` » — **jamais implémenté**, aucun code appelant ces paramètres avec une valeur réelle trouvé | Variante dérivée automatiquement du pays pédagogique (M4), 2 chartes complètes livrées (anglophone_waec, lusophone) | Dépassé — la source ne prévoyait qu'un point d'extension de couleur seule (primaire/secondaire), jamais un système de charte complète, jamais construit |
| Persistance de la préférence d'affichage | Sans objet (aucune préférence n'existait, le mode étant figé) | Persistée localement (Drift, hors-ligne prioritaire) | Neuf |

**Couvert sans écart** : aucune fonctionnalité de thématisation n'était
réellement disponible côté source pour un utilisateur final — ce module part
donc d'une base fonctionnelle nulle côté source, pas d'un report de
fonctionnalité existante.

## 6. Limites connues et éléments différés

- **`arabophone_mixte`** n'a pas de charte graphique dédiée : les
  établissements de cette famille utilisent `francophoneCfa` par repli
  (`AppThemeVariant.depuisCodeSysteme`). Signalé ici, pas silencieux —
  décision à prendre avec le porteur de projet : construire une 4ᵉ charte
  dans un module ultérieur, ou assumer le repli durablement.
- La variante visuelle n'est **pas modifiable manuellement** par
  l'utilisateur (dérivée du pays de l'établissement, cf. §2.5). Choix
  délibéré du périmètre demandé (« thèmes visuels d'établissement ») — à
  confirmer si un besoin de préférence personnelle distincte émerge.
- **Dette d'accessibilité pré-existante non traitée par ce module** : certains
  usages de couleurs de la charte `francophone_cfa` **claire** (déjà
  approuvée, chapitre 2 du cahier v4.1) tombent sous le seuil WCAG AA quand
  utilisées comme texte de petite taille sur fond clair (ex. `accent`,
  `succes`, `premium` directement en couleur de texte plutôt qu'en fond de
  bouton). Cette charte n'a pas été modifiée par ce module (verrouillée par
  cadrage officiel) ; à signaler séparément au porteur de projet si une
  correction de la charte claire existante est souhaitée.

## 7. Tests

- `test/core/theme/app_palettes_test.dart` — résolution de variante, sélection
  de palette, contraste WCAG AA des 6 palettes, construction du `ThemeData`,
  repli de `context.palette` hors contexte de thème.
- `test/features/themes/theme_preference_store_test.dart` — persistance
  (écriture/lecture, isolation par domaine de cache, survie à une nouvelle
  instance de store sur la même base).
- `test/features/themes/theme_providers_test.dart` — `themeModeProvider`
  (chargement, `definir()`, persistance inter-conteneurs) ; `themeVariantProvider`
  (dérivation depuis établissement + référentiel, tous les cas de repli).
- `test/features/themes/ecran_preferences_apparence_test.dart` — rendu de
  l'écran, bascule clair/sombre via l'UI, affichage de la charte active.
- `test/widget_test.dart` — mis à jour (`AppColors` → `AppPalettes`).

233 tests passent, `flutter analyze` ne remonte aucun problème.

---

**Point de contrôle** : le module M15bis (Thèmes internationaux & Dark Mode)
est-il totalement clos et validé pour passer au suivant ? — Code livré, testé
(233 tests), documenté, écart vs `ecoshop_flutter` posé (§5), limites
explicitement signalées (§6). Le module suivant dans la séquence, **M16 — IA à
rôles**, reste toutefois bloqué indépendamment de M15bis, par l'arbitrage en
attente du rapport d'audit rétroactif `docs/AUDIT_ECOSHOP_FLUTTER.md`.
