-- ============================================================================
-- EcoShop — KER-MUT K1 : délestage des dépendances au Kernel GSG
-- (docs/REGISTRE.md REG-01.1, directive du 2026-10-17)
--
-- Le Kernel GSG devient exclusivement un Control Plane (hub de tableaux de
-- bord). Il ne fournit plus d'identité : la fédération GSG ID est abandonnée
-- et l'Edge Function gsg-id-federate est retirée du dépôt.
--
-- Cette migration :
--   1. cesse de recopier profiles.gsg_id dans le JWT (custom_access_token_hook
--      redéfini à l'identique de 20260906000100, moins le claim gsg_id) ;
--   2. marque la colonne profiles.gsg_id comme obsolète, SANS la supprimer :
--      aucune donnée n'est détruite ; la suppression physique est un point
--      ouvert soumis au porteur de projet (REG-01.1).
--
-- Migration idempotente.
-- ============================================================================

create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  claims        jsonb;
  app_metadata  jsonb;
  prof          record;
begin
  claims := coalesce(event->'claims', '{}'::jsonb);

  select role_racine, statut_compte into prof
  from public.profiles
  where id = (event->>'user_id')::uuid
    and deleted_at is null;

  if found then
    app_metadata := coalesce(claims->'app_metadata', '{}'::jsonb);

    -- Un jeton émis avant cette migration peut encore porter gsg_id dans
    -- app_metadata (claims repris de l'événement) : on le retire.
    app_metadata := app_metadata - 'gsg_id';

    if prof.role_racine is not null then
      app_metadata := jsonb_set(app_metadata, '{role_racine}',
                                to_jsonb(prof.role_racine::text), true);
    end if;
    app_metadata := jsonb_set(app_metadata, '{statut_compte}',
                              to_jsonb(prof.statut_compte::text), true);

    claims := jsonb_set(claims, '{app_metadata}', app_metadata, true);
  end if;

  -- Rappel : ces claims sont un cache de confort côté client. Toute décision
  -- d'autorisation relit public.profiles côté serveur (ch. 34).
  return jsonb_build_object('claims', claims);
end;
$$;

grant usage on schema public to supabase_auth_admin;
grant execute on function public.custom_access_token_hook(jsonb) to supabase_auth_admin;
revoke execute on function public.custom_access_token_hook(jsonb) from authenticated, anon, public;

comment on column public.profiles.gsg_id is
  'OBSOLÈTE depuis KER-MUT (2026-10-17) : la fédération GSG ID est abandonnée, '
  'le Kernel GSG n''est plus fournisseur d''identité. Plus jamais écrite ni émise '
  'dans le JWT. Conservée sans suppression de données ; retrait physique soumis '
  'au porteur de projet (docs/REGISTRE.md REG-01.1).';
