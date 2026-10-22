-- ============================================================================
-- EcoShop — Désigner l'administrateur GSG (une fois)
--
-- MODÈLE rempli par scripts/deployer_supabase.ps1. Le compte doit d'abord
-- exister : s'inscrire dans l'application avec cette adresse ou ce numéro.
-- ============================================================================
with cible as (
  select u.id from auth.users u
  where (nullif('{{ADMIN_GSG_COURRIEL}}', '') is not null and lower(u.email) = lower('{{ADMIN_GSG_COURRIEL}}'))
     or (nullif('{{ADMIN_GSG_TELEPHONE}}', '') is not null and u.phone = '{{ADMIN_GSG_TELEPHONE}}')
)
update public.profiles p set role_racine = 'admin_gsg'
from cible where p.id = cible.id
returning 'Administrateur GSG désigné : ' || p.id as resultat;
