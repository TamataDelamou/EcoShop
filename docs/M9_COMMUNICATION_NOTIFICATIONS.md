# M9 — Communication & Notifications

> Module de communication parentale et interne de l'établissement, multicanal
> (SMS, WhatsApp, Email, Push) et orienté faible connectivité. L'IA ne produit
> que des signaux d'aide (timing, canal, A/B) ; aucun envoi n'est automatisé
> sans règle éthique.

## 1. Périmètre fonctionnel

- **Notifications** : absences/retards (parents), notes/évaluations
  (parents/élèves), congés/sanctions (personnel/direction), alertes
  décrochage, rappels d'événements.
- **Préférences de canaux** : par utilisateur — canal actif, horaires de
  réception, fréquence (`immediat`/`quotidien`/`hebdomadaire`), avec opt-out.
- **Journal des envois** : fournisseur, statut (`envoye`/`echoue`/`en_retry`),
  code d'erreur, retry, identifiant fournisseur (accusé de réception).
- **Modèles de messages** : par établissement, type et canal, avec variables
  (`{{eleve}}`, `{{date}}`, `{{note}}`…).

## 2. Modèle de données (migration `20260906000900_m9_communication_notifications.sql`)

| Table | Rôle | Points clés |
|---|---|---|
| `notifications` | Message adressé à un destinataire | `destinataire`, `type`, `canal`, `contenu`, `variante` (A/B), `statut`, `date_envoi`, `date_lecture` |
| `preferences_canaux` | Préférences par utilisateur | `canal`, `actif`, `horaire_debut`/`fin`, `frequence` — unique (profile, canal) |
| `logs_envois` | Journal technique | `fournisseur`, `statut`, `code_erreur`, `date_retry`, `message_id_fournisseur` |
| `templates_notifications` | Modèles par établissement | `type`, `canal`, `contenu`, `variables`, `actif` |

### Garde-fous

- **Multi-tenant** : un log d'envoi doit référencer une notification du même
  établissement (`logs_envois_verifie_tenant`).
- **Intégrité des notifications** : seul le destinataire (ou le serveur) peut
  marquer « lue » ; le destinataire ne peut pas altérer contenu/canal/type.
- **Horaires cohérents** : `horaire_debut <= horaire_fin` sur les préférences.

## 3. IA — trois niveaux (cohérents M6/M7/M8)

| Niveau | Fonction | Description |
|---|---|---|
| Descriptive | `analyser_envois(etab, début, fin)` | Taux de lecture par canal sur une période |
| Prédictive | `suggere_heure_envoi(profile)` | Créneau d'envoi préféré (préférence, sinon heure de lecture la plus fréquente, sinon 09:00) |
| Prescriptive | `choisir_canal(profile, type)` | Canal préféré (WhatsApp > SMS > Push > Email), repli SMS |
| Prescriptive | `selectionner_variante(profile, type)` | Affectation A/B déterministe et stable (sans état serveur) |
| Prescriptive | `analyser_feedback(texte)` | Sentiment (positif/neutre/négatif) par lexique français léger |

**Règle éthique** : opt-out par canal, pas d'envoi automatique aux heures
inopportunes (hors créneau de préférence), minimisation des données de lecture
(« lu/non lu », pas le contenu des réponses hors consentement). L'A/B reste un
outil interne d'amélioration, discret et limité (petits effectifs).

## 4. RLS & visibilité

- **Destinataire** : voit ses notifications ; marque « lue » ; gère ses
  préférences de canaux (strictement personnelles).
- **Direction/administration** (`est_comm`) : voit toutes les notifications de
  l'établissement, crée les notifications, consulte les logs, gère les modèles.
- **Membres** : lecture des modèles de messages de leur établissement.
- **Isolation multi-tenant** : aucune notification ni log visible hors
  établissement.

## 5. Hors-ligne

- **File d'attente locale** : les notifications à envoyer sont stockées en
  cache (Drift) avec leur statut, puis poussées à la synchronisation suivante
  (pattern `sync_queue` du socle).
- **Accusés de réception** : le `message_id_fournisseur` est réconcilié côté
  serveur à la remontée ; le client ne fait jamais foi sur le statut final.

## 6. Plan de tests

- `19_m9_notifications_visibilite.sql` : destinataire/direction, envoi réservé,
  isolation multi-tenant.
- `20_m9_notifications_lecture.sql` : marquage « lue », intégrité du contenu,
  création par la direction.
- `21_m9_ia_comm.sql` : canal préféré, créneau d'envoi, sentiment, A/B, taux de
  lecture.

Exécution (session Docker) : `pg_prove -d "$DB" tests/rls/19_m9_*.sql` — détail
complet dans `docs/SESSION_VALIDATION_TECHNIQUE.md`.

## 7. Permissions introduites

| Code | Libellé |
|---|---|
| `comm.notifier` | Envoyer des notifications |
| `comm.voir_logs` | Consulter les logs d'envois |
