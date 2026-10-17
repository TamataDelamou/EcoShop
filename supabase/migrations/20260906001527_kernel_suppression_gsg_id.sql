-- ============================================================================
-- EcoShop — KER-MUT K1 (suite) : suppression définitive de profiles.gsg_id
-- (docs/REGISTRE.md REG-01.1, décision du porteur de projet du 2026-10-17 :
--  « les fichiers inutiles du Kernel, il faudra s'en débarrasser »)
--
-- La fédération GSG ID est abandonnée (migration 20260906001525) : la
-- colonne n'est plus ni écrite ni émise dans le JWT. Elle est supprimée.
--
-- Ordre imposé : profiles_protege_colonnes() (20260906000100) recopie
-- old.gsg_id ; PL/pgSQL n'étant résolu qu'à l'exécution, supprimer la
-- colonne d'abord casserait TOUT update de profiles par un client. La
-- fonction est donc redéfinie sans gsg_id AVANT le drop.
--
-- Migration idempotente.
-- ============================================================================

create or replace function public.profiles_protege_colonnes()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if public.est_appel_service() then
    return new;
  end if;

  new.id                     := old.id;
  new.identifiant_canonique  := old.identifiant_canonique;
  new.role_racine            := old.role_racine;
  new.statut_compte          := old.statut_compte;
  new.created_at             := old.created_at;
  new.deleted_at             := old.deleted_at;
  return new;
end;
$$;

comment on function public.profiles_protege_colonnes() is
  'Empêche un client d''élever ses propres privilèges via un UPDATE sur profiles.';

alter table public.profiles drop column if exists gsg_id;
