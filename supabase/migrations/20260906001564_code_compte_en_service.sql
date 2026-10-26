-- ============================================================================
-- EcoShop — REG-22 partie A : mise en service du code du compte
-- ============================================================================
-- Serveur (1562-1563) et application livrés : tout nouvel appareil d'un
-- compte doté d'un code doit désormais être vérifié. Un compte sans code
-- serveur passe toujours (il le définit à sa prochaine ouverture en ligne).
-- Retour arrière sans migration, si un défaut apparaît :
--   update public.parametres_globaux set valeur = 'false'
--    where cle = 'code_compte_obligatoire';
-- ============================================================================
update public.parametres_globaux set valeur = 'true'::jsonb, updated_at = now()
 where cle = 'code_compte_obligatoire';
