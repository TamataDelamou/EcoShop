# M15ter — Export PDF (bulletins) — Contrat de module

> Module **purement client** (aucune migration SQL) — inséré dans la
> séquence de construction juste après M15bis, avant M16.
> Code : `apps/client_flutter/lib/features/export_pdf/`.
> Tests : `apps/client_flutter/test/features/export_pdf/`.
>
> **Retrait du sous-périmètre « reçu PDF » (voir §7)** : livré initialement
> avec un export de reçu adossé aux écritures comptables générales de M14
> (`EcritureComptable`), puis **retiré** avant tout push vers `origin/main` —
> cette entité n'a aucun lien structurel avec un élève, une inscription ou
> un solde dû, et n'aurait pas garanti qu'un document ayant l'apparence d'un
> reçu de scolarité corresponde à un vrai encaissement. Ce sous-périmètre
> sera rebranché sur une entité d'encaissement dédiée livrée par
> **M15quater — Inscription, réinscription & encaissement de scolarité**.

## 1. Périmètre (livré)

Conformément à `docs/AUDIT_ECOSHOP_FLUTTER.md` §0.2 : `ecoshop_flutter`
(source) générait un bulletin PDF (`pdf_service.dart`, mise en page A4 codée
en dur) et un reçu de paiement, capacités totalement absentes côté cible
avant ce module.

1. **Export PDF des bulletins** (M6) : le bulletin, jusqu'ici un simple
   affichage écran d'un jsonb (`ecran_bulletins.dart`), peut désormais être
   exporté, prévisualisé, imprimé ou partagé en PDF. **Livré et conservé.**
2. **Export PDF des reçus** (M13/M14) : **retiré** — voir §7.
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
Brightness.light)`, jamais la variante sombre.

### 2.2 `entete_pdf.dart` — en-tête et pied de page partagés

`enteteDocument()` (nom d'établissement, localisation, titre du document) et
`piedDePage()` (horodatage de génération) — communs à tout document produit
par ce module (un seul bulletin aujourd'hui, potentiellement d'autres
documents à l'avenir).

**Convention de police** : tiret simple `-`, jamais de tiret cadratin `—`,
dans tout texte rendu par ce module. La police de base (Helvetica, non
embarquée — voir §4) ne dessine pas ce glyphe.

### 2.3 `bulletin_pdf_builder.dart`

`construireBulletinPdf({bulletin, fiche, etablissement, variante})` — en-tête
+ bloc identité élève (nom, prénom, matricule, date de naissance) + tableau
des rubriques de `bulletin.contenu` (jsonb libre, rendu clé/valeur tel quel,
sans réinterpréter le format métier) + empreinte d'intégrité si présente.

### 2.4 `EcranApercuPdf` (`presentation/ecran_apercu_pdf.dart`)

Écran générique de prévisualisation/impression/partage, basé sur
`PdfPreview` (package `printing`). Chrome (barre d'application, fond) themée
normalement via `Theme.of(context)`/`context.palette`. Conservé générique
(pas spécifique au bulletin) pour être réutilisé sans modification quand le
PDF reçu sera rebranché (M15quater).

### 2.5 Point d'entrée UI

`ecran_bulletins.dart` : bouton « Exporter en PDF » sur chaque bulletin
publié (`_CarteBulletin`, `ConsumerStatefulWidget` pour l'état de chargement
de l'export).

## 3. Résolution des problèmes hérités

1. **Aucune capacité PDF n'existait dans la cible** — ni dépendance
   `pdf`/`printing`, ni service, ni bouton d'export sur aucun écran. Résolu
   pour les bulletins : dépendances ajoutées (`pdf: ^3.13.0`, `printing:
   ^5.15.0`), module dédié, un point d'entrée UI fonctionnel.
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
| Reçu thermique 58 mm / reçu A4 annuel | `genererRecuThermique`/`genererRecuA4` | **Retiré** (voir §7) — sera traité après M15quater, sur l'entité d'encaissement dédiée, pas sur une écriture comptable générale | Différé — dépend de M15quater |
| Fiche élève PDF | `genererFicheEleve` (identité + situation financière + historique) | **Absent** | Différé — dépend du suivi financier par élève (M15quater), hors périmètre de ce module |
| Bulletin de paie PDF | `pdf_service.dart` (paie) | **Absent** | Différé — dépend du cycle de paie RH, déjà signalé fortement dégradé (audit M8/M9 point 4), hors périmètre de ce module |
| Attestations | Absentes des deux côtés (confirmé par l'audit) | Absentes | Pas un écart — hors périmètre assumé de ce module |

## 5. Tests

- `test/features/export_pdf/pdf_palette_test.dart` — la palette PDF reprend
  bien la variante claire de chaque charte, jamais la sombre.
- `test/features/export_pdf/bulletin_pdf_builder_test.dart` — génère un PDF
  structurellement valide (en-tête `%PDF-`) pour les 3 variantes, avec et
  sans contenu.

242 tests passent au total (module entier), `flutter analyze` propre.

## 6. Limites connues et éléments différés

- Pas de système de gabarits paramétrable — mise en page fixe, comme la
  source (choix assumé, cf. §1).
- Génération groupée (classe entière) hors périmètre — dépend d'un point
  déjà signalé dans l'audit rétroactif, à arbitrer avec le porteur de projet
  plutôt que construit par anticipation ici.
- Glyphes hors police de base (ex. tiret cadratin) dans les champs libres
  utilisateur : affichage dégradé (glyphe manquant), pas d'échec — voir §2.2.

## 7. Historique — retrait du sous-périmètre « reçu PDF »

**Livré initialement**, puis **retiré avant tout push vers `origin/main`**,
sur décision explicite du porteur de projet, pour la raison suivante :
l'export s'appuyait sur `EcritureComptable` (M14, écriture comptable
générale — débit/crédit/montant/libellé/journal), qui n'a **aucun lien
structurel** avec un élève, une inscription ou un solde dû :

- Pas de `fiche_eleve_id` sur `EcritureComptable`.
- Pas de lien vers `inscriptions`, pas de suivi `montant_du`/solde.
- `libelle` est un champ texte libre non vérifié — un comptable peut y
  écrire n'importe quoi, y compris une mention de scolarité pour une
  écriture qui n'en est pas une (loyer, salaire, achat…).
- L'écran source (`ecran_saisie_ecriture.dart`) est une saisie comptable
  générale, pas un encaissement de frais de scolarité.

Autrement dit : le document généré avait l'apparence d'un reçu officiel de
scolarité sans qu'aucune donnée ne garantisse qu'il corresponde à un vrai
encaissement — un risque inacceptable pour un document remis à une famille.

**Ce qui a été retiré** (commit de retrait à identifier dans l'historique
git, postérieur au commit initial de M15ter) :
- `apps/client_flutter/lib/features/export_pdf/data/recu_pdf_builder.dart`
  (supprimé).
- `apps/client_flutter/test/features/export_pdf/recu_pdf_builder_test.dart`
  (supprimé).
- Le bouton « Exporter le reçu (PDF) » et l'état associé dans
  `ecran_ecritures_recentes.dart` (`_CarteEcriture` revenu à un
  `StatelessWidget` simple, comme avant M15ter).

**Ce qui reste** : `PdfPaletteX`, `entete_pdf.dart` et `EcranApercuPdf` sont
restés génériques (jamais spécifiques au reçu) — aucune reprise nécessaire
de cette infrastructure partagée quand le PDF reçu sera reconstruit.

**Prochaine étape (M15quater, puis retour ici)** : une fois l'entité
d'encaissement de scolarité dédiée livrée (liant explicitement
`fiche_eleve_id`/`inscription_id`, montant dû, montant payé, solde), un
nouveau `recu_pdf_builder.dart` sera écrit contre **cette** entité — jamais
contre `EcritureComptable` — et ce document sera remis à jour en
conséquence.
