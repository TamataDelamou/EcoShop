-- ============================================================================
-- EcoShop — REG-22 partie B : appareils connectés
-- ============================================================================
-- Mon profil › Sécurité › Mes appareils : la liste des connexions ouvertes,
-- avec la dernière utilisation ; « Déconnecter » un appareil, ou tous les
-- autres. La session est supprimée dans auth.sessions (ses jetons de
-- renouvellement partent avec elle) ; grâce au contrôle avant chaque requête
-- (migration 1562), l'appareil est refusé dès sa requête suivante
-- (SESSION_REVOQUEE), même si son jeton est encore valable. L'application,
-- à ce refus, déconnecte et efface les données du téléphone.
-- Actions sensibles : code ou empreinte demandés par l'application,
-- journalisées, avec un courriel.
-- ============================================================================

-- Toutes les connexions ouvertes du compte, décrites ou non (une ancienne
-- version de l'application ne se décrit pas).
create or replace function public.mes_appareils()
returns table (
  session_id uuid,
  modele text,
  systeme text,
  version_application text,
  statut text,
  connecte_le timestamptz,
  derniere_utilisation timestamptz,
  cet_appareil boolean
)
language plpgsql stable security definer set search_path = public
as $$
declare v_session uuid := public.exiger_session();
begin
  return query
  select s.id,
         coalesce(a.modele, 'Appareil inconnu'),
         a.systeme,
         a.version_application,
         coalesce(a.statut, 'non_enregistre'),
         s.created_at,
         -- Dernier renouvellement du jeton (au plus une heure d'écart), sans
         -- écriture supplémentaire à chaque requête.
         greatest(s.created_at, coalesce(s.refreshed_at at time zone 'UTC', s.updated_at), s.updated_at),
         s.id = v_session
    from auth.sessions s
    left join public.sessions_appareils a on a.session_id = s.id
   where s.user_id = auth.uid()
     and (s.not_after is null or s.not_after > now())
   order by (s.id = v_session) desc, 7 desc;
end;
$$;

-- Appareil depuis lequel on peut déconnecter les autres : vérifié (ou
-- compte sans code du compte).
create or replace function public.exiger_appareil_de_confiance()
returns uuid
language plpgsql stable security definer set search_path = public
as $$
declare v_session uuid := public.exiger_session();
begin
  if exists (select 1 from public.codes_compte where profile_id = auth.uid())
     and not public.session_approuvee(v_session) then
    raise exception 'APPAREIL_A_VERIFIER' using errcode = '42501';
  end if;
  return v_session;
end;
$$;
revoke all on function public.exiger_appareil_de_confiance() from public, anon, authenticated;

create or replace function public.deconnecter_appareil(p_session uuid)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_session uuid := public.exiger_appareil_de_confiance();
  v_modele text;
begin
  if p_session = v_session then
    raise exception 'CET_APPAREIL' using errcode = '22023',
      hint = 'Pour cet appareil, utilisez « Se déconnecter ».';
  end if;
  select coalesce(a.modele, 'Appareil inconnu') into v_modele
    from auth.sessions s left join public.sessions_appareils a on a.session_id = s.id
   where s.id = p_session and s.user_id = auth.uid();
  if not found then
    raise exception 'APPAREIL_INCONNU' using errcode = 'P0002';
  end if;
  delete from auth.sessions where id = p_session and user_id = auth.uid();
  perform public.enregistrer_audit(null, 'code_compte', auth.uid(), 'deconnexion_appareil', null,
    jsonb_build_object('session', p_session, 'modele', v_modele));
  perform public.prevenir_compte(auth.uid(), 'appareils_deconnectes', 'appareil_deconnecte:' || p_session,
    jsonb_build_object('modeles', v_modele, 'nombre', 1));
end;
$$;

create or replace function public.deconnecter_autres_appareils()
returns integer
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_session uuid := public.exiger_appareil_de_confiance();
  v_modeles text;
  v_nombre integer;
begin
  select string_agg(coalesce(a.modele, 'Appareil inconnu'), ', '), count(*)
    into v_modeles, v_nombre
    from auth.sessions s left join public.sessions_appareils a on a.session_id = s.id
   where s.user_id = auth.uid() and s.id <> v_session;
  if coalesce(v_nombre, 0) = 0 then
    return 0;
  end if;
  delete from auth.sessions where user_id = auth.uid() and id <> v_session;
  perform public.enregistrer_audit(null, 'code_compte', auth.uid(), 'deconnexion_autres_appareils', null,
    jsonb_build_object('nombre', v_nombre, 'modeles', v_modeles));
  perform public.prevenir_compte(auth.uid(), 'appareils_deconnectes',
    'autres_deconnectes:' || v_session || ':' || extract(epoch from now())::bigint,
    jsonb_build_object('modeles', v_modeles, 'nombre', v_nombre));
  return v_nombre;
end;
$$;

revoke all on function public.mes_appareils() from public, anon;
revoke all on function public.deconnecter_appareil(uuid) from public, anon;
revoke all on function public.deconnecter_autres_appareils() from public, anon;
grant execute on function public.mes_appareils(), public.deconnecter_appareil(uuid),
  public.deconnecter_autres_appareils() to authenticated;
