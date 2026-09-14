-- ============================================================================
-- EcoShop — Chantier Facturation/Quota IA — Étape (c) : extension de
-- type_objet_paye_cinetpay pour l'abonnement Premium élève.
--
-- Migration séparée à dessein, PAS un choix de conception : Postgres
-- interdit d'utiliser une valeur ajoutée par ALTER TYPE ... ADD VALUE dans
-- la même transaction que son ajout. La migration suivante
-- (20260906001519) référence cette valeur dans une contrainte CHECK sur
-- transactions_cinetpay -- elle doit donc être committée avant. Chaque
-- migration de ce dépôt étant appliquée dans sa propre transaction, deux
-- fichiers séparés suffisent à lever la contrainte, sans artifice
-- supplémentaire.
--
-- Migration idempotente (IF NOT EXISTS).
-- ============================================================================

alter type public.type_objet_paye_cinetpay add value if not exists 'abonnement_premium_eleve';
