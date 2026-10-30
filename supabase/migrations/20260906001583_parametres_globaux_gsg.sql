-- ============================================================================
-- EcoShop — REG-36 : l'Administrateur GSG règle les paramètres globaux
-- ============================================================================
-- Les paramètres globaux (tarifs Premium, quotas du Tuteur IA, offres…)
-- étaient lisibles par tous mais ne se modifiaient qu'en base, avec la clé
-- de service. Désormais l'Administrateur GSG les règle depuis l'application,
-- et chaque changement est historisé (qui, quand, avant, après).
--
-- Garde-fous : seuls des paramètres existants se modifient (pas de création
-- à la volée) ; la valeur reste un objet JSON ; une valeur simple garde son
-- type (un tarif reste un nombre).
-- ============================================================================

create table if not exists public.historique_parametres_globaux (
  id uuid primary key default gen_random_uuid(),
  cle text not null references public.parametres_globaux (cle) on delete cascade,
  ancienne_valeur jsonb,
  nouvelle_valeur jsonb not null,
  modifie_par uuid references public.profiles (id) on delete set null,
  modifie_le timestamptz not null default now()
);

create index if not exists idx_historique_parametres_cle
  on public.historique_parametres_globaux (cle, modifie_le desc);

alter table public.historique_parametres_globaux enable row level security;
revoke insert, update, delete on public.historique_parametres_globaux from anon, authenticated;

drop policy if exists historique_parametres_select on public.historique_parametres_globaux;
create policy historique_parametres_select on public.historique_parametres_globaux
  for select to authenticated
  using (coalesce(public.est_admin_gsg(), false));

create or replace function public.definir_parametre_global(p_cle text, p_valeur jsonb)
returns public.parametres_globaux
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ancienne jsonb;
  v_ligne public.parametres_globaux;
begin
  if not coalesce(public.est_admin_gsg(), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if p_valeur is null or jsonb_typeof(p_valeur) <> 'object' then
    raise exception 'VALEUR_INVALIDE' using errcode = '22023';
  end if;

  select valeur into v_ancienne from public.parametres_globaux where cle = p_cle for update;
  if not found then
    raise exception 'PARAMETRE_INCONNU' using errcode = '22023';
  end if;

  if v_ancienne ? 'valeur' and p_valeur ? 'valeur'
     and jsonb_typeof(v_ancienne -> 'valeur') <> jsonb_typeof(p_valeur -> 'valeur') then
    raise exception 'TYPE_INVALIDE' using errcode = '22023';
  end if;

  update public.parametres_globaux
     set valeur = p_valeur, updated_at = now()
   where cle = p_cle
  returning * into v_ligne;

  insert into public.historique_parametres_globaux (cle, ancienne_valeur, nouvelle_valeur, modifie_par)
  values (p_cle, v_ancienne, p_valeur, auth.uid());

  return v_ligne;
end;
$$;

revoke all on function public.definir_parametre_global(text, jsonb) from public, anon;
grant execute on function public.definir_parametre_global(text, jsonb) to authenticated;
