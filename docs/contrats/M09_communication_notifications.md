# M09 — Communication & Notifications — Contrat d'interface Flutter

> Migration : `supabase/migrations/20260906000900_m9_communication_notifications.sql`.
> Source de vérité : SQL + tests RLS associés.
> Périmètre : notifications multicanal, préférences de canaux, journal des envois, modèles de messages, IA (taux de lecture, moment opportun, canal préféré, A/B, sentiment).

## 1. Enums

| Enum | Valeurs |
|---|---|
| `public.canal_notification` | `sms`, `whatsapp`, `email`, `push` |
| `public.statut_notification` | `en_attente`, `envoyee`, `lue`, `echouee`, `annulee` |
| `public.statut_envoi` | `envoye`, `echoue`, `en_retry` |
| `public.frequence_notification` | `immediat`, `quotidien`, `hebdomadaire` |

## 2. Tables (DTOs)

### `public.notifications`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| destinataire | uuid | NOT NULL, FK → `profiles(id)` CASCADE |
| type | text | NOT NULL, CHECK `length(type) > 0` |
| canal | canal_notification | NOT NULL DEFAULT `'sms'` |
| contenu | text | NOT NULL DEFAULT `''` |
| variante | text | nullable (`'A'`/`'B'` A/B testing) |
| variables | jsonb | NOT NULL DEFAULT `'{}'` |
| statut | statut_notification | NOT NULL DEFAULT `'en_attente'` |
| date_envoi_planifie | timestamptz | nullable |
| date_envoi | timestamptz | nullable |
| date_lecture | timestamptz | nullable |
| created_at / updated_at | timestamptz | NOT NULL DEFAULT now() |
| deleted_at | timestamptz | nullable |

### `public.preferences_canaux`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| profile_id | uuid | NOT NULL, FK → `profiles(id)` CASCADE |
| canal | canal_notification | NOT NULL |
| actif | boolean | NOT NULL DEFAULT true |
| horaire_debut | time | NOT NULL DEFAULT `'08:00'` |
| horaire_fin | time | NOT NULL DEFAULT `'19:00'` |
| frequence | frequence_notification | NOT NULL DEFAULT `'immediat'` |

Unique `(profile_id, canal)` ; CHECK `horaire_debut <= horaire_fin`.

### `public.logs_envois`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| notification_id | uuid | NOT NULL, FK → `notifications(id)` CASCADE |
| fournisseur | text | NOT NULL DEFAULT `''` |
| statut | statut_envoi | NOT NULL DEFAULT `'envoye'` |
| code_erreur | text | nullable |
| date_retry | timestamptz | nullable |
| message_id_fournisseur | text | nullable |
| created_at | timestamptz | NOT NULL DEFAULT now() |

### `public.templates_notifications`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| type | text | NOT NULL |
| canal | canal_notification | NOT NULL DEFAULT `'sms'` |
| contenu | text | NOT NULL DEFAULT `''` |
| variables | jsonb | NOT NULL DEFAULT `'[]'` |
| actif | boolean | NOT NULL DEFAULT true |

Unique `(etablissement_id, type, canal)`.

## 3. RPC client

### Helpers de visibilité
- `est_membre_etab(p_etablissement uuid) returns boolean` — membre actif.
- `est_comm(p_etablissement uuid) returns boolean` — direction OU permission `comm.notifier`.
- `notif_visible(p_notification uuid) returns boolean` — destinataire OU `est_comm`.

### Fonctions IA (signaux d'aide)
- `analyser_envois(p_etablissement uuid, p_debut date, p_fin date) returns table(canal text, nb_envoyes bigint, nb_lus bigint, taux_lecture numeric)` — gate `COMM_REQUIS`.
- `suggere_heure_envoi(p_profile uuid) returns time` — créneau préféré, sinon heure de lecture la plus fréquente, sinon `09:00`. Gate `DESTINATAIRE_REQUIS` (soi-même).
- `choisir_canal(p_profile uuid, p_type text) returns text` — canal préféré (WhatsApp > SMS > Push > Email), repli `'sms'`. Gate soi-même.
- `selectionner_variante(p_profile uuid, p_type text) returns text` — `'A'`/`'B'` déterministe (md5), sans état serveur.
- `analyser_feedback(p_texte text) returns text` — sentiment `positif`/`negatif`/`neutre` (lexique français).

## 4. RLS

| Table | Commande | Règle |
|---|---|---|
| notifications | SELECT | `notif_visible(id)` |
| notifications | INSERT | `est_comm(etablissement_id)` |
| notifications | UPDATE | `est_comm(etablissement_id)` OU `destinataire = auth.uid()` |
| preferences_canaux | SELECT | `profile_id = auth.uid()` |
| preferences_canaux | ALL | `profile_id = auth.uid()` |
| logs_envois | SELECT | `est_comm(etablissement_id)` |
| logs_envois | ALL | `est_comm(etablissement_id)` |
| templates_notifications | SELECT | `est_membre_etab(etablissement_id)` |
| templates_notifications | ALL | `est_comm(etablissement_id)` |

## 5. Conventions transverses

- Trigger `notifications_verifie_ecriture` : seul le **destinataire** peut poser `date_lecture` (`LECTURE_DESTINATAIRE` 42501) ; un destinataire ne peut pas modifier `canal`/`contenu`/`type`/`destinataire`/`etablissement_id` (`MODIFICATION_NON_AUTORISEE` 42501).
- Trigger `logs_envois_verifie_tenant` : `NOTIFICATION_AUTRE_ETABLISSEMENT` 23514.
- Le marquage « lue » se fait côté client par `UPDATE ... SET date_lecture = now()` sur SA notification.
- Permissions seedées : `comm.notifier`, `comm.voir_logs`.
- IA : jamais d'envoi automatique sans règle éthique (opt-out par canal, horaires, minimisation) ; afficher les suggestions comme non-bloquantes.
- Soft-delete : filtrer `deleted_at is null` sur `notifications`.
