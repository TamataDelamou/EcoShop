-- ============================================================================
-- EcoShop — REG-03, lot C5 (2/3) : valeurs d'énumération du journal d'audit
-- pour les dons. Fichier séparé (comme 20260906001528) : une valeur ajoutée
-- par ALTER TYPE ne peut servir qu'après validation de la transaction.
-- ============================================================================
alter type public.type_entite_journal_audit add value if not exists 'don';
alter type public.type_entite_journal_audit add value if not exists 'emploi_fonds_affectes';
