# Contrats d'interface — M4 → M15 (DTOs & RPCs)

Spécifications des contrats d'interface destinées au développement des écrans Flutter.
Chaque fichier décrit pour un module : les **enums** (→ enum Dart), les **tables** (→ DTOs),
les **RPC** appelables par le client, les **politiques RLS** (ce que chaque rôle peut faire)
et les **conventions transverses** (soft-delete, hors-ligne, permissions, pièges).

## Fichiers

| Module | Fichier | Nature |
|---|---|---|
| M04 Référentiel pédagogique CEDEAO | [M04_referentiel_pedagogique.md](M04_referentiel_pedagogique.md) | lecture seule publique |
| M05 Administration & Scolarité | [M05_administration_scolarite.md](M05_administration_scolarite.md) | structures + inscriptions + parent↔élève |
| M06 Notes & Évaluations | [M06_notes_evaluations.md](M06_notes_evaluations.md) | évaluations, notes hors-ligne, bulletins |
| M07 Absences & Vie scolaire | [M07_absences_vie_scolaire.md](M07_absences_vie_scolaire.md) | présences, sanctions, alertes décrochage |
| M08 RH & Personnel | [M08_rh_personnel.md](M08_rh_personnel.md) | employés, contrats, congés, paie |
| M09 Communication & Notifications | [M09_communication_notifications.md](M09_communication_notifications.md) | notifications multicanal |
| M10 Rapports & Statistiques | [M10_rapports_statistiques.md](M10_rapports_statistiques.md) | indicateurs, anomalies, NLG |
| M11 Planification & Agenda | [M11_planification_agenda.md](M11_planification_agenda.md) | emplois du temps, salles, progression |
| M12 Intégration & Déploiement | [M12_observabilite.md](M12_observabilite.md) | métriques, santé, pics de charge |
| M13 Marketplace AssoShop | [M13_marketplace_assoshop.md](M13_marketplace_assoshop.md) | commerçants, panier, commandes, paiements |
| M14 Comptabilité sans OHADA | [M14_comptabilite.md](M14_comptabilite.md) | partie double, journal, balance |
| M15 Marketplace sans authentification | [M15_marketplace_public.md](M15_marketplace_public.md) | profils publics invités |

## Conventions transverses (rappel)

- **Soft-delete** : la plupart des tables portent `deleted_at` ; toute requête client filtre `deleted_at is null`.
- **Hors-ligne** : `device_id` + `client_ts` (Last-Write-Wins) et/ou `saisi_hors_ligne` sur les écritures décentralisées ; les moyennes/agrégats ne sont JAMAIS calculés côté client (toujours via RPC serveur).
- **Multi-tenant** : chaque table porte `etablissement_id` + trigger `*_verifie_tenant` (errcode `23514`).
- **IA** : les fonctions prédictives/prescriptives produisent des **signaux** à valider par un humain, jamais d'action automatique.
- **Permissions** : la visibilité fine passe par `public.permissions` (`est_direction`, `a_permission`, `mes_permissions`) — ne jamais coder les rôles en dur dans le client.
- **Rôles de prédicat** : `est_personnel`, `est_parent_confirme`, `fiche_visible`, `classe_visible`, `est_rh`, `est_comptable`, `est_comptable_ecriture`, `est_comm`, etc.

## Fidélité

Ces specs sont dérivées des migrations SQL (`supabase/migrations/2026090600*_m*.sql`) et des tests RLS (`tests/rls/*.sql`).
Les **noms d'enums, de tables, de RPC et de policies sont exacts** ; pour la liste **colonne par colonne**,
la migration reste la source de vérité — croiser systématiquement avec le fichier SQL du module avant de coder.
