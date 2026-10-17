# Proposition REG-02 — Implémentation d'un opérateur Mobile Money

**Date** : 2026-10-17. **Statut** : **validée** par le porteur de projet le
2026-10-17 ; lots L1 à L4 (serveur) livrés le même jour — voir le registre. **Registre** : `docs/REGISTRE.md` REG-02.
**Marché ciblé en premier** : Guinée (GNF).

---

## 1. Décision demandée

> **Recommandation** : implémenter **Orange Money Guinée en intégration
> directe** comme second adaptateur du Port Paiement, pour les paiements
> encaissés **par les établissements** (scolarité en ligne, marketplace).
> Conserver **CinetPay** pour les paiements encaissés **par GSG** (licence
> Pro, frais IA, Premium élève) et comme solution de repli couvrant aussi
> l'ex-MTN (Areeba). Ne pas intégrer en direct l'ex-MTN MoMo pour l'instant.

Trois décisions sont attendues du porteur de projet (§7).

---

## 2. Ce qui existe déjà dans EcoShop

Le projet a **deux circuits de paiement distincts**, qu'il ne faut pas
confondre :

| Circuit | Qui encaisse | Flux concernés | État |
|---|---|---|---|
| **GSG** | Le compte marchand de GSG | Licence Pro, frais IA admin, Premium élève | Brique CinetPay générique livrée (migration `…1515`, Edge Functions `initier_paiement_cinetpay` / `recevoir_webhook_cinetpay`), testée en simulation, **sans identifiants réels** |
| **Établissement** | Le compte marchand **propre à chaque établissement** (modèle AssoShop : GSG ne détient jamais les fonds) | Marketplace (M13) ; scolarité en ligne (chapitre 17, pas encore câblée) | Port agnostique en place : `sous_comptes_marchands` + `paiements`, type `type_fournisseur_paiement ('cinetpay', 'mobile_money')`. Aucun adaptateur réel branché. La scolarité n'est saisie qu'à la main (`encaissements_scolarite`, moyen `mobile_money` déclaratif). |

**Constat important** : CinetPay prend en charge la Guinée en GNF avec
**Orange Money GN** (`OMGN`) et **MTN Mobile Money GN** (`MTNGN`), pour des
montants de 1 000 à 15 000 000 GNF. L'appel actuel (`channels: "ALL"`)
donne donc **déjà accès au mobile money guinéen** dès qu'un compte marchand
CinetPay est ouvert : la question n'est pas « comment accéder au mobile
money », mais « faut-il, en plus, une relation directe avec un opérateur ».

---

## 3. Le paysage guinéen en 2026

| Acteur | Situation | Fiabilité de l'information |
|---|---|---|
| **Orange Money** (Orange Finances Mobiles Guinée) | Premier opérateur, part de marché estimée à 50-60 %. L'API **Orange Money Web Payment** est officiellement disponible en **Guinée Conakry** (portail développeurs Orange). Accès : devenir marchand Orange Money auprès d'Orange Guinée. | Disponibilité de l'API : source officielle. Parts de marché : estimation d'un blog spécialisé. |
| **Ex-MTN Guinée → Areeba Guinée** | MTN Group a cédé sa filiale à l'État fin 2024 ; l'opérateur est **entièrement nationalisé depuis décembre 2025** sous le nom Areeba Guinée. Le service mobile money continue d'être proposé par les agrégateurs (CinetPay `MTNGN`, Moneroo `mtn_gf`), mais **aucune source ne précise l'avenir de la marque MoMo ni de l'accès à l'API MoMo du groupe MTN** pour la Guinée. Un projet de fusion avec Guinée Telecom est évoqué. | Nationalisation : presse spécialisée, plusieurs sources concordantes. Avenir de l'API : **inconnu**. |
| **NimbaPay** | Système national de paiement instantané lancé par la **BCRG le 22 juillet 2026** (banques, portefeuilles électroniques, microfinance, 24 h/24). Aucune offre marchande ni API pour les entreprises documentée à ce jour. | Presse spécialisée. |
| **Agrégateurs régionaux** | CinetPay (Orange + MTN GN) ; Moneroo (MTN GN uniquement). | Documentation officielle des agrégateurs. |
| **Fintechs guinéennes** | Lengo Pay (fondée en 2024, API annoncée, opérateurs couverts non précisés) ; PayCard (portefeuille + carte Visa prépayée, pas d'API marchande documentée). | Presse ; informations publiques insuffisantes. |

**Ordres de grandeur commerciaux** (source unique : un blog d'intégrateur,
chiffres **indicatifs et parfois contradictoires d'un article à l'autre** —
à remplacer par les grilles officielles négociées) :

- Frais marchand en direct chez l'opérateur : environ **1,5 % à 2,5 %**.
- Frais via un agrégateur : environ **3 % à 4 %**, tout compris.
- Délai de reversement : Orange **T+2**, ex-MTN **T+1** ; agrégateurs **T+1 à T+3**.
- Plafonds : environ 5 000 000 GNF/jour en KYC simple, 20 000 000 GNF/jour en
  KYC marchand complet.
- Ouverture d'un compte marchand Orange : **RCCM + NIF + pièce du dirigeant**,
  validation KYC de quelques jours, bac à sable **sur demande**, 2 à 4
  semaines au total.

---

## 4. Options comparées

| | A. CinetPay seul | **B. Orange Money direct** | C. Ex-MTN MoMo direct | D. Fintech locale | E. NimbaPay |
|---|---|---|---|---|---|
| Couverture | Orange + ex-MTN | Orange (~55 %) | ex-MTN (~35 %) | Non documentée | Toutes institutions à terme |
| Frais indicatifs | ~3-4 % | **~1,5-2,5 %** | ~1,7-2 % | Inconnus | Inconnus |
| Code à écrire | **Aucun** (déjà livré) | Un adaptateur | Un adaptateur | Un adaptateur | Impossible aujourd'hui |
| Contrat | 1 contrat GSG ou 1 par établissement | 1 contrat **par établissement** avec Orange | 1 par établissement | 1 par établissement | — |
| Maturité de l'API | Bonne, multi-pays | Bonne, API officielle documentée | **Incertaine** (changement de propriétaire) | Faible | Pas d'API marchande |
| Dépendance | Un intermédiaire de plus | Relation directe établissement ↔ Orange | Relation directe | Startup jeune | BCRG |
| Risque principal | Coût par transaction | Ne couvre pas les clients ex-MTN | Avenir de l'API | Pérennité | Calendrier |

---

## 5. Recommandation détaillée

1. **Orange Money Guinée en direct** pour le circuit **établissement** :
   - frais nettement plus bas sur la scolarité, qui représente les plus gros
     montants ;
   - l'argent arrive directement sur le compte Orange Money **de
     l'établissement** : cohérent avec le modèle AssoShop (GSG ne détient
     jamais les fonds) ;
   - l'API Web Payment est officielle et disponible en Guinée.
2. **CinetPay maintenu** :
   - pour le circuit **GSG** (un seul compte marchand, plusieurs pays à
     terme : c'est là que l'agrégateur est le plus utile) ;
   - comme **repli** côté établissement pour les payeurs ex-MTN/Areeba, tant
     qu'une intégration directe n'est pas possible : l'établissement choisit
     d'activer un sous-compte CinetPay en plus d'Orange.
3. **Ex-MTN (Areeba) direct : différé**, à réévaluer dès que le statut de
   son service mobile money et de son API est clarifié.
4. **NimbaPay : veille**. Si la BCRG ouvre une interface marchande,
   l'adaptateur se branchera derrière le même port, sans réécriture.

**Point juridique à faire confirmer** (je ne suis pas juriste) : le schéma
« chaque établissement encaisse sur son propre compte marchand, GSG ne fait
que fournir le logiciel » vise à éviter que GSG soit considéré comme
collectant des fonds pour compte de tiers. Ce point doit être validé par un
conseil juridique ou auprès de la BCRG avant la mise en production.

---

## 6. Plan d'implémentation (derrière le Port Paiement existant)

Même discipline que les chantiers précédents : un lot = migration + code +
tests + documentation, vérifié avant le suivant.

| Lot | Contenu |
|---|---|
| **L1 — Schéma** | Ajout de `orange_money_gn` à `type_fournisseur_paiement`. Table `secrets_sous_comptes_marchands` (identifiants Orange **par établissement** : client id/secret, merchant key), RLS sans aucune policy, comme `parametres_secrets_integration` — jamais lisible par un client. |
| **L2 — Adaptateur** | `_shared/orange_money_client.ts`, seul point d'appel sortant vers Orange : jeton OAuth (client credentials), initiation d'un paiement Web Payment (URL de paiement + jeton de paiement + jeton de notification), consultation du statut. `ORANGE_MONEY_URL_OVERRIDE` pour les tests, comme CinetPay. |
| **L3 — Notification** | Edge Function `recevoir_notification_orange_money` : vérifie le jeton de notification, puis **reconfirme le statut auprès d'Orange** (jamais la notification seule), bascule idempotente `initie → reussi/echoue` sous verrou, comme le webhook CinetPay. |
| **L4 — Branchement des usages** | (a) Paiement d'une commande marketplace. (b) **Paiement de scolarité en ligne** (chapitre 17) : un paiement réussi crée automatiquement l'`encaissement_scolarite` correspondant (moyen `mobile_money`, référence Orange), donc le reçu PDF déjà livré. |
| **L5 — Client Flutter** | Choix du moyen de paiement selon les sous-comptes actifs de l'établissement, redirection vers la page Orange, retour dans l'application, suivi du statut ; écran Direction pour activer le sous-compte Orange. |
| **L6 — Tests** | pgTAP (isolation entre établissements, secrets illisibles, idempotence, montant recalculé serveur, notification rejouée sans double crédit) ; Deno avec faux serveur Orange. |
| **L7 — Exploitation** | Rapprochement quotidien paiements ↔ relevé Orange, prise en compte du reversement à T+2, alerte sur paiement resté « initié ». |

Détails techniques de l'API Orange (chemins exacts, code pays guinéen,
devise de test, format de la notification) : **à confirmer sur la
documentation remise par Orange Guinée avec l'accès au bac à sable** — non
publiés en libre accès.

---

## 7. Ce qu'il faut au porteur de projet pour démarrer

1. **Valider l'option B** (ou en choisir une autre).
2. **Un établissement pilote** prêt à ouvrir un compte marchand Orange Money
   (RCCM, NIF, pièce du dirigeant), et la demande d'**accès au bac à sable**
   auprès d'Orange Guinée. Le développement des lots L1 à L3 peut commencer
   sans attendre, contre un faux serveur ; seuls les tests réels en dépendent.
3. **Faire confirmer le point juridique** du §5.

---

## 8. Sources

- [Orange Developer — Orange Money Web Payment / M Payment in Africa](https://developer.orange.com/apis/om-webpay) : liste des pays dont la Guinée Conakry, inscription marchande auprès d'Orange.
- [CinetPay — tableau des moyens de paiement](https://docs.cinetpay.com/api/1.0-en/checkout/tableau) : Guinée GNF, `OMGN` et `MTNGN`, 1 000 – 15 000 000 GNF.
- [Moneroo — méthodes disponibles](https://docs.moneroo.io/fr/payments/methodes-disponibles) : `mtn_gf` (Guinée).
- [MTN MoMo Developer Community — pays où les API MoMo sont en production](https://momodevelopercommunity.mtn.com/momo-api-production-q-a-7/what-are-the-countries-where-momo-apis-are-live-95) (juillet 2023, antérieur à la cession).
- [African Markets — MTN conclut la vente de ses opérations guinéennes à l'État (janv. 2025)](https://www.african-markets.com/en/stock-markets/jse/mtn-concludes-the-sale-of-its-guinea-operations-to-the-state-of-guinea).
- [Developing Telecoms — la Guinée prend le contrôle total d'Areeba Guinée (déc. 2025)](https://developingtelecoms.com/telecom-business/operator-news/19493-guinea-takes-full-control-of-areeba-guinee-after-seizing-mtn-stake.html) ; [Afrique IT News (déc. 2025)](https://afriqueitnews.com/tech-media/guinee-nationalise-areeba-guinee-retrait-definitif-mtn/).
- [We Are Tech — la Guinée lance NimbaPay (juil. 2026)](https://www.wearetech.africa/fr/fils/actualites/finance/la-guinee-lance-nimbapay-son-systeme-national-de-paiement-instantane).
- [We Are Tech — Lengo Pay (juin 2025)](https://www.wearetech.africa/fr/fils/solutions/guinee-lengo-pay-veut-simplifier-les-paiements-numeriques-en-afrique) ; [Paymentology — PayCard (juil. 2023)](https://www.paymentology.com/newsroom/paymentology-partners-with-paycard-to-drive-financial-inclusion-in-guinea).
- Ordres de grandeur commerciaux (indicatifs) : Kolonell, [paiement mobile money en Guinée](https://kolonell.com/fr/blog/paiement-mobile-money-guinee-conakry-orange-mtn-paycard-2026), [API Orange Money Guinée](https://kolonell.com/fr/blog/api-orange-money-guinee-integration-conakry-2026), [frais Orange vs MTN (août 2026)](https://kolonell.com/fr/blog/guinee-orange-mtn-momo-frais-encaissement-conakry-2026), [délais de reversement (août 2026)](https://kolonell.com/fr/blog/delais-settlement-orange-money-mtn-conakry-2026).
