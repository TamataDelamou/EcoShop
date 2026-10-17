-- ============================================================================
-- EcoShop — REG-02 Orange Money Guinée, lot L1 (1/2) : valeurs d'énumération
-- (docs/REGISTRE.md REG-02, docs/propositions/REG-02_MOBILE_MONEY.md)
--
-- Isolé dans sa propre migration : une valeur ajoutée par ALTER TYPE ... ADD
-- VALUE ne peut pas être utilisée dans la même transaction (même raison que
-- 20260906001518_facturation_abonnement_premium_eleve_enum.sql).
-- ============================================================================

alter type public.type_fournisseur_paiement add value if not exists 'orange_money_gn';
alter type public.type_entite_journal_audit add value if not exists 'transaction_mobile_money';
