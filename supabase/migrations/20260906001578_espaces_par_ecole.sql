-- ============================================================================
-- EcoShop — REG-32 : les espaces partent de l'établissement.
--
-- Un même compte peut être enseignant dans une école et parent dans une
-- autre (ou dans la même). Les espaces proposés dans l'application sont donc
-- des couples (rôle, école), jamais un rôle seul :
--   • rôle de personnel ou d'élève : rattachement actif dans l'école ;
--   • parent : au moins un lien confirmé et autorisé avec un élève de
--     l'école (un parent ne devient pas membre de l'école, cf. M5 §9).
--
-- Corrige aussi la liaison d'un enfant : elle exigeait un compte dont le
-- rôle principal est « parent » ; un enseignant ou un membre du personnel
-- est aussi parent. Seul un compte élève (ou sans rôle choisi) est refusé.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Espaces du compte connecté
-- ---------------------------------------------------------------------------
create or replace function public.mes_espaces()
returns table (role text, etablissement_id uuid, etablissement_nom text, enfants integer)
language sql stable
security definer
set search_path = public
as $$
  with membres as (
    select m.role_dans_etablissement as role, m.etablissement_id, 0 as enfants
    from public.etablissements_membres m
    join public.profiles p on p.id = m.profile_id
    where m.profile_id = auth.uid()
      and m.actif
      and m.deleted_at is null
      and (m.date_fin is null or m.date_fin >= current_date)
      and p.statut_compte = 'actif'
      and p.deleted_at is null
      and m.role_dans_etablissement <> 'parent'
  ),
  parents as (
    select 'parent'::text as role, r.etablissement_id, count(*)::int as enfants
    from public.relations_parent_eleve r
    join public.fiches_eleves f on f.id = r.fiche_eleve_id and f.deleted_at is null
    where r.parent_profile_id = auth.uid()
      and r.statut = 'confirmee'
      and r.autorise
      and r.deleted_at is null
    group by r.etablissement_id
  )
  select e.role, e.etablissement_id, et.nom, e.enfants
  from (select * from membres union all select * from parents) e
  join public.etablissements et on et.id = e.etablissement_id and et.deleted_at is null
  order by et.nom, case e.role when 'parent' then 1 else 0 end;
$$;

comment on function public.mes_espaces() is
  'REG-32 : espaces (rôle, école) du compte connecté — rattachements actifs et écoles où il a un enfant lié et confirmé.';

revoke execute on function public.mes_espaces() from public, anon;
grant execute on function public.mes_espaces() to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Liaison d'un enfant : tout compte adulte peut être parent
-- ---------------------------------------------------------------------------
do $$
declare
  v_def text := pg_get_functiondef('public.lier_parent_a_fiche(text, date, public.type_relation_parentale)'::regprocedure);
  v_ancien constant text := $a$if (select role_racine from public.profiles where id = auth.uid()) is distinct from 'parent' then$a$;
  v_nouveau constant text := $n$if coalesce((select role_racine::text from public.profiles where id = auth.uid()), 'eleve') = 'eleve' then$n$;
begin
  if position(v_ancien in v_def) = 0 then
    if position(v_nouveau in v_def) > 0 then
      return; -- déjà appliqué
    end if;
    raise exception 'REG-32 : contrôle du rôle introuvable dans lier_parent_a_fiche';
  end if;
  execute replace(v_def, v_ancien, v_nouveau);
end $$;

comment on function public.lier_parent_a_fiche(text, date, public.type_relation_parentale) is
  'Liaison parent ↔ fiche (matricule + date de naissance). REG-32 : ouverte à tout compte adulte (parent, enseignant, personnel, direction…) ; refusée aux comptes élèves.';
