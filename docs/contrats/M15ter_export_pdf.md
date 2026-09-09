# M15ter — Export PDF (bulletins & reçus) — Contrat de module

> Module **purement client** (aucune migration SQL) — inséré dans la
> séquence de construction juste après M15bis, avant M16.
> Code : `apps/client_flutter/lib/features/export_pdf/`.
> Tests : `apps/client_flutter/test/features/export_pdf/`.

## 1. Périmètre

Conformément à `docs/AUDIT_ECOSHOP_FLUTTER.md` §0.2 : `ecoshop_flutter`
(source) générait un bulletin PDF (`pdf_service.dart`, mise en page A4 codée
en dur) et un reçu de paiement (thermique 58 mm + A4) à chaque encaissement,
capacités totalement absentes côté cible avant ce module.

1. **Export PDF des bulletins** (M6) : le bulletin, jusqu'ici un simple
   affichage écran d'un jsonb (`ecran_bulletins.dart`), peut désormais être
   exporté, prévisualisé, imprimé ou partagé en PDF.
2. **Export PDF des reçus** (M13/M14) : toute écriture comptable déjà saisie
   (`ecran_ecritures_recentes.dart`) peut être exportée en reçu PDF.
3. **Attestations** (scolarité/inscription/paiement) : **hors périmètre**,
   confirmées absentes des deux côtés par l'audit (pas une régression) —
   reportées à l'arbitrage général du porteur de projet, pas traitées ici.
4. Le document respecte la charte graphique de l'établissement (M15bis) :
   3 variantes (`francophoneCfa`/`anglophoneWaec`/`lusophone`), toujours dans
   leur déclinaison **claire** — un document imprimé n'a pas de mode sombre.
   L'écran de prévisualisation qui l'entoure, lui, suit le thème actif de
   l'application (clair/sombre) comme n'importe quel autre écran.

Ce n'est **pas** un système de gabarits (« templates ») paramétrable côté
back-office — comme la source elle-même (mise en page codée en Dart, pas de
moteur de gabarit), et cohérent avec le périmètre demandé (« sur le modèle de
ce qui existait dans ecoshop_flutter, à consulter comme référence
fonctionnelle, pas technique »).

## 2. Architecture

### 2.1 `PdfPaletteX` (`application/pdf_palette.dart`)

Convertit une `AppPalette` (M15bis, `dart:ui`/Flutter `Color`) en `PdfColor`
(package `pdf`) — toujours à partir de `AppPalettes.pour(variante,
Brightness.light)`, jamais la variante sombre. Repli sur une palette par
défaut impossible ici : la variante est toujours résolue en amont par
`themeVariantProvider` (M15bis) avant d'appeler un constructeur de document.

### 2.2 `entete_pdf.dart` — en-tête et pied de page partagés

`enteteDocument()` (nom d'établissement, localisation, titre du document) et
`piedDePage()` (horodatage de génération) sont communs aux deux documents :
un seul endroit à faire évoluer si la charte documentaire change.

**Convention de police** : tiret simple `-`, jamais de tiret cadratin `—`,
dans tout texte rendu par ce module. La police de base (Helvetica, non
embarquée — voir §4) ne dessine pas ce glyphe. Les champs libres saisis par
l'utilisateur (`ecriture.libelle`, contenu du bulletin) ne sont pas
assainis : un caractère hors police s'affiche comme un glyphe manquant sans
faire échouer la génération — limite connue, documentée dans
`recu_pdf_builder.dart`.

### 2.3 `bulletin_pdf_builder.dart`

`construireBulletinPdf({bulletin, fiche, etablissement, variante})` — en-tête
+ bloc identité élève (nom, prénom, matricule, date de naissance) + tableau
des rubriques de `bulletin.contenu` (jsonb libre, rendu clé/valeur tel quel,
sans réinterpréter le format métier) + empreinte d'intégrité si présente.

### 2.4 `recu_pdf_builder.dart`

`construireRecuPdf({ecriture, libelleCompteDebit, libelleCompteCredit,
libelleJournal, etablissement, variante})` — en-tête + informations
(date/libellé/journal/référence) + montant mis en avant (devise de
l'établissement) + comptes débit/crédit + mention « saisi hors ligne » le
cas échéant. Format A4 unique : pas de variante thermique 58 mm séparée, la
cible n'a pas encore d'écran de caisse dédié (écart distinct, différé —
audit M13/M15 point 3, non traité par ce module).

### 2.5 `EcranApercuPdf` (`presentation/ecran_apercu_pdf.dart`)

Écran générique de prévisualisation/impression/partage, basé sur
`PdfPreview` (package `printing`) — réutilisé par les deux documents plutôt
que dupliqué. Chrome (barre d'application, fond) themée normalement via
`Theme.of(context)`/`context.palette`.

### 2.6 Points d'entrée UI

- `ecran_bulletins.dart` : bouton « Exporter en PDF » sur chaque bulletin
  publié (`_CarteBulletin`, converti en `ConsumerStatefulWidget` pour l'état
  de chargement de l'export).
- `ecran_ecritures_recentes.dart` : icône « Exporter le reçu (PDF) » sur
  chaque écriture (`_CarteEcriture`, même conversion).

## 3. Résolution des problèmes hérités

1. **Aucune capacité PDF n'existait dans la cible** — ni dépendance
   `pdf`/`printing`, ni service, ni bouton d'export sur aucun écran. Résolu :
   dépendances ajoutées (`pdf: ^3.13.0`, `printing: ^5.15.0`), module dédié,
   deux points d'entrée UI fonctionnels.
2. **Duplication de libellé de type de bulletin** — `TypeBulletin` (M6)
   n'exposait pas de libellé lisible ; `ecran_bulletins.dart` dupliquait un
   `switch` local. Ajout de `TypeBulletin.libelle` (enum, `enums_notes.dart`)
   et réutilisation dans l'écran ET le PDF — une seule source de vérité pour
   ce libellé plutôt que deux copies destinées à diverger.

## 4. Rapport d'écart fonctionnel vs `ecoshop_flutter`

Conformément à la règle transversale ANALYSE_GLOBALE.md §4.2.5.

| Fonctionnalité | ecoshop_flutter (source) | EcoShop (cible, ce module) | Écart |
|---|---|---|---|
| Export PDF bulletin | `pdf_service.dart` (`genererBulletinA4`) — mise en page codée en dur, **moyenne générale + rang + appréciation seulement**, pas le détail par matière (limite documentée dans le code source lui-même) | `construireBulletinPdf` — rend **tout** `bulletin.contenu` (jsonb serveur), donc le détail par matière si le serveur le fournit ; dépend de ce que M6 publie réellement dans ce champ | Dépassé en flexibilité (rend ce que le serveur envoie), mais n'a pas de mise en page dédiée « par matière » codée en dur comme la source — différence de conception, pas une perte |
| Export PDF groupé (classe entière) | `genererBulletinsClasseA4` — génère tous les bulletins d'une classe en un geste | **Absent** — ce module exporte un bulletin à la fois | Écart assumé : dépend du point non résolu « génération de bulletins pour une classe entière » (déjà signalé, différé, audit M6 point 8) — sans écran de génération de masse, un export groupé n'a pas de source de données à consommer |
| Reçu thermique 58 mm | `genererRecuThermique` | **Absent** — format A4 unique | Différé — aucun écran de caisse dédié dans la cible à ce jour (voir §2.4) ; à revoir si un besoin de caisse physique est confirmé |
| Reçu A4 annuel récapitulatif (2 exemplaires) | `genererRecuA4` | **Absent** — un reçu = une écriture, pas de récapitulatif annuel | Différé — nécessite d'abord un concept de « solde élève par année » (déjà signalé absent, audit M13/M15 point 3) |
| Fiche élève PDF | `genererFicheEleve` (identité + situation financière + historique) | **Absent** | Différé — dépend du suivi financier par élève, déjà signalé absent (audit M4/M5 point 5), hors périmètre de ce module |
| Bulletin de paie PDF | `pdf_service.dart` (paie) | **Absent** | Différé — dépend du cycle de paie RH, déjà signalé fortement dégradé (audit M8/M9 point 4), hors périmètre de ce module |
| Attestations | Absentes des deux côtés (confirmé par l'audit) | Absentes | Pas un écart — hors périmètre assumé de ce module |

## 5. Tests

- `test/features/export_pdf/pdf_palette_test.dart` — la palette PDF reprend
  bien la variante claire de chaque charte, jamais la sombre.
- `test/features/export_pdf/bulletin_pdf_builder_test.dart` — génère un PDF
  structurellement valide (en-tête `%PDF-`) pour les 3 variantes, avec et
  sans contenu.
- `test/features/export_pdf/recu_pdf_builder_test.dart` — idem pour les
  reçus, y compris le cas d'une écriture saisie hors ligne.

246 tests passent au total (module entier), `flutter analyze` propre.

## 6. Limites connues et éléments différés

- Pas de système de gabarits paramétrable — mise en page fixe, comme la
  source (choix assumé, cf. §1).
- Génération groupée (classe entière, récapitulatif annuel) hors périmètre —
  dépend de points déjà signalés dans l'audit rétroactif, à arbitrer avec le
  porteur de projet plutôt que construits par anticipation ici.
- Glyphes hors police de base (ex. tiret cadratin) dans les champs libres
  utilisateur : affichage dégradé (glyphe manquant), pas d'échec — voir §2.2.

---

**Point de contrôle** : le module M15ter (Export PDF) est-il totalement clos
et validé pour passer au suivant ? — Code livré, testé, documenté, écart vs
`ecoshop_flutter` posé (§4), limites explicitement signalées (§6). **M16**
reste bloqué indépendamment de M15ter, par l'arbitrage en attente du reste du
rapport d'audit rétroactif (`docs/AUDIT_ECOSHOP_FLUTTER.md`).
