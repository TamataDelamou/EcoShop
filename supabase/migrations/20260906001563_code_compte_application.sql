-- ============================================================================
-- EcoShop — REG-22 partie A (application) : compléments serveur
-- ============================================================================
-- 1. Autorisation par un appareil connu (« Code oublié ? › Autoriser depuis
--    un autre appareil ») : le nouvel appareil entre sans connaître le code ;
--    il choisit donc un nouveau code du compte dans les 15 minutes, une fois.
-- 2. Direction › « Débloquer le code d'une personne » : liste des personnes
--    de l'école que la direction peut débloquer.
-- 3. Administrateur GSG : retrouver un compte (direction, fondateur) par son
--    adresse ou son identifiant EcoShop, après vérification d'identité.
-- ============================================================================

alter table public.sessions_appareils add column if not exists code_a_choisir_avant timestamptz;

create or replace function public.approuver_appareil(p_demande uuid)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_session uuid := public.exiger_session();
  v_d public.demandes_appareil;
begin
  if not public.session_approuvee(v_session) then
    raise exception 'APPAREIL_A_VERIFIER' using errcode = '42501';
  end if;
  select * into v_d from public.demandes_appareil
   where id = p_demande and profile_id = auth.uid() and type = 'approbation' for update;
  if v_d.id is null then
    raise exception 'DEMANDE_INCONNUE' using errcode = 'P0002';
  end if;
  if v_d.statut <> 'en_attente' or v_d.echeance <= now() then
    raise exception 'DEMANDE_EXPIREE' using errcode = '22023';
  end if;
  if v_d.session_id is null or v_d.session_id = v_session
     or not exists (select 1 from auth.sessions where id = v_d.session_id) then
    raise exception 'DEMANDE_EXPIREE' using errcode = '22023';
  end if;
  update public.demandes_appareil set statut = 'approuvee', traitee_par_session = v_session, updated_at = now()
   where id = v_d.id;
  perform public.approuver_session(v_d.session_id, auth.uid(), 'appareil_connu');
  update public.sessions_appareils set code_a_choisir_avant = now() + interval '15 minutes'
   where session_id = v_d.session_id;
end;
$$;

-- Nouveau code choisi par l'appareil que l'on vient d'autoriser.
create or replace function public.choisir_code_apres_autorisation(p_nouveau text)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_session uuid := public.exiger_session();
  v_version integer;
begin
  if not exists (select 1 from public.sessions_appareils
                 where session_id = v_session and profile_id = auth.uid() and statut = 'approuvee'
                   and methode = 'appareil_connu' and code_a_choisir_avant > now()) then
    raise exception 'CHOIX_EXPIRE' using errcode = '42501';
  end if;
  v_version := public.poser_code_compte(auth.uid(), p_nouveau);
  update public.sessions_appareils set code_a_choisir_avant = null, updated_at = now() where session_id = v_session;
  perform public.prevenir_compte(auth.uid(), 'code_compte_change', 'code_change:' || auth.uid() || ':' || v_version);
  return jsonb_build_object('version_code', v_version);
end;
$$;

-- Personnes que la direction peut débloquer : personnel non dirigeant,
-- élèves au compte lié, parents confirmés. Jamais elle-même.
create or replace function public.personnes_debloquables(p_etablissement uuid, p_recherche text default null)
returns table (profile_id uuid, nom_complet text, qualite text, a_un_code boolean, bloque boolean)
language plpgsql stable security definer set search_path = public
as $$
declare v_motif text := '%' || lower(trim(coalesce(p_recherche, ''))) || '%';
begin
  if not coalesce(public.est_direction(p_etablissement), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  return query
  with personnes as (
    select m.profile_id as id, case m.role_dans_etablissement when 'enseignant' then 'Enseignant' else 'Personnel' end as qualite
      from public.etablissements_membres m
     where m.etablissement_id = p_etablissement and m.actif and m.deleted_at is null
       and m.role_dans_etablissement not in ('direction', 'fondateur_reseau', 'eleve', 'parent')
    union
    select f.profile_id, 'Élève'
      from public.fiches_eleves f
     where f.etablissement_id = p_etablissement and f.profile_id is not null and f.deleted_at is null
    union
    select r.parent_profile_id, 'Parent'
      from public.relations_parent_eleve r
      join public.fiches_eleves f on f.id = r.fiche_eleve_id
     where f.etablissement_id = p_etablissement and r.statut = 'confirmee' and r.deleted_at is null
  )
  select p.id,
         trim(coalesce(p.prenom, '') || ' ' || coalesce(p.nom, '')),
         string_agg(distinct x.qualite, ', '),
         exists (select 1 from public.codes_compte c where c.profile_id = p.id),
         exists (select 1 from public.essais_code_compte e where e.profile_id = p.id and e.bloque_jusqu_a > now())
    from personnes x
    join public.profiles p on p.id = x.id and p.deleted_at is null
   where p.id <> auth.uid()
     and coalesce(p.role_racine::text, '') not in ('direction', 'fondateur_reseau', 'admin_gsg')
     and not exists (select 1 from public.etablissements_membres d
                      where d.profile_id = p.id and d.actif and d.deleted_at is null
                        and d.role_dans_etablissement in ('direction', 'fondateur_reseau'))
     and (lower(coalesce(p.prenom, '') || ' ' || coalesce(p.nom, '') || ' ' || coalesce(p.identifiant_ecoshop, '')) like v_motif)
   group by p.id, p.prenom, p.nom
   order by 2
   limit 50;
end;
$$;

-- Administrateur GSG : un compte par son adresse exacte ou son identifiant EcoShop.
create or replace function public.chercher_compte_gsg(p_recherche text)
returns table (profile_id uuid, nom_complet text, courriel text, roles text, a_un_code boolean, bloque boolean)
language plpgsql stable security definer set search_path = public
as $$
declare v_r text := lower(trim(coalesce(p_recherche, '')));
begin
  if not coalesce(public.est_admin_gsg(), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if length(v_r) < 4 then
    return;
  end if;
  return query
  select p.id,
         trim(coalesce(p.prenom, '') || ' ' || coalesce(p.nom, '')),
         u.email::text,
         coalesce((select string_agg(e.nom || ' (' || m.role_dans_etablissement || ')', ', ')
                     from public.etablissements_membres m join public.etablissements e on e.id = m.etablissement_id
                    where m.profile_id = p.id and m.actif and m.deleted_at is null), p.role_racine::text, ''),
         exists (select 1 from public.codes_compte c where c.profile_id = p.id),
         exists (select 1 from public.essais_code_compte s where s.profile_id = p.id and s.bloque_jusqu_a > now())
    from public.profiles p
    join auth.users u on u.id = p.id
   where p.deleted_at is null
     and (lower(u.email) = v_r or lower(coalesce(p.identifiant_ecoshop, '')) = v_r)
   limit 5;
end;
$$;

revoke all on function public.choisir_code_apres_autorisation(text) from public, anon;
revoke all on function public.personnes_debloquables(uuid, text) from public, anon;
revoke all on function public.chercher_compte_gsg(text) from public, anon;
grant execute on function public.choisir_code_apres_autorisation(text), public.personnes_debloquables(uuid, text),
  public.chercher_compte_gsg(text) to authenticated;
