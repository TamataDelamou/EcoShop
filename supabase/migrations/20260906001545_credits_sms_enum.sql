-- ============================================================================
-- EcoShop — REG-09 (préalable) : achat de crédits SMS par CinetPay (circuit GSG)
--
-- ALTER TYPE … ADD VALUE ne peut pas être utilisé dans la même transaction
-- que la nouvelle valeur : il vit dans sa propre migration, comme
-- `…1518` (abonnement Premium) et `…1539` (dons).
-- ============================================================================
alter type public.type_objet_paye_cinetpay add value if not exists 'pack_sms_etablissement';
