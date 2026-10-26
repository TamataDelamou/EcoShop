-- ============================================================================
-- EcoShop — REG-22 partie C : rôle « personnel » et journal des membres
-- ============================================================================
-- Seule dans sa migration : une valeur ajoutée à un type énuméré ne peut pas
-- servir dans la même transaction (migration 1567).
-- ============================================================================
alter type public.role_racine add value if not exists 'personnel';
alter type public.type_entite_journal_audit add value if not exists 'membre';
