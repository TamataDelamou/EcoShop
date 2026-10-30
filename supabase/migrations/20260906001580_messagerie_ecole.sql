-- ============================================================================
-- EcoShop — REG-34 : messagerie famille ↔ école et groupes de classe.
--
-- Recherche (registre REG-34) : ClassDojo, Remind, Seesaw, ParentSquare,
-- Pronote ; directive du Manitoba (oct. 2026) et projet sud-africain sur
-- WhatsApp (sept. 2026). Principes retenus :
--   • jamais d'échange privé adulte ↔ élève : les élèves n'échangent que dans
--     le groupe de leur classe, sous les yeux de leurs enseignants (règles M9) ;
--   • le parent écrit à l'enseignant de son enfant ou à la direction, au sujet
--     de cet enfant ; la direction voit tout ; aucun numéro personnel exposé ;
--   • heures de messagerie de l'école : hors de ces heures, le personnel n'est
--     pas dérangé (notification reportée à l'ouverture) et les élèves
--     n'écrivent pas dans les groupes ;
--   • rien n'est effacé : masquage motivé, journal d'audit, signalement.
--
-- Clés fournies par l'appareil (envoi sans réseau, renvoi sans doublon).
-- Migration idempotente.
-- ============================================================================

alter type public.type_entite_journal_audit add value if not exists 'message_groupe';

-- ---------------------------------------------------------------------------
-- 1. Heures de messagerie de l'école
-- ---------------------------------------------------------------------------
alter table public.etablissements
  add column if not exists messagerie_debut time not null default '07:00',
  add column if not exists messagerie_fin time not null default '19:00',
  -- Jours ISO : 1 = lundi … 7 = dimanche.
  add column if not exists messagerie_jours smallint[] not null default '{1,2,3,4,5,6}';

comment on column public.etablissements.messagerie_debut is
  'REG-34 : heures de messagerie (heure locale de l''école). Hors de ces heures, le personnel n''est pas notifié (report à l''ouverture) et les élèves n''écrivent pas dans les groupes.';

-- Vrai si l'instant est dans les heures de messagerie de l'école.
create or replace function public.dans_heures_messagerie(p_etablissement uuid, p_instant timestamptz default now())
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce((
    select extract(isodow from (p_instant at time zone e.fuseau_horaire))::smallint = any (e.messagerie_jours)
       and (p_instant at time zone e.fuseau_horaire)::time >= e.messagerie_debut
       and (p_instant at time zone e.fuseau_horaire)::time < e.messagerie_fin
    from public.etablissements e where e.id = p_etablissement), true);
$$;

-- Prochaine ouverture de la messagerie (maintenant si elle est ouverte).
create or replace function public.prochaine_ouverture_messagerie(p_etablissement uuid)
returns timestamptz
language plpgsql stable security definer set search_path = public
as $$
declare
  e record;
  v_jour date;
  v_debut timestamptz;
begin
  if public.dans_heures_messagerie(p_etablissement) then
    return now();
  end if;
  select fuseau_horaire, messagerie_debut, messagerie_jours into e from public.etablissements where id = p_etablissement;
  if not found or coalesce(array_length(e.messagerie_jours, 1), 0) = 0 then
    return now();
  end if;
  v_jour := (now() at time zone e.fuseau_horaire)::date;
  for i in 0..7 loop
    if extract(isodow from v_jour + i)::smallint = any (e.messagerie_jours) then
      v_debut := ((v_jour + i) + e.messagerie_debut) at time zone e.fuseau_horaire;
      if v_debut > now() then
        return v_debut;
      end if;
    end if;
  end loop;
  return now();
end;
$$;
revoke execute on function public.dans_heures_messagerie(uuid, timestamptz), public.prochaine_ouverture_messagerie(uuid)
  from public, anon;
grant execute on function public.dans_heures_messagerie(uuid, timestamptz), public.prochaine_ouverture_messagerie(uuid)
  to authenticated;

-- Lues par tout membre et par les parents des élèves : l'application les
-- affiche (« l'école répond de 7 h à 19 h »).
create or replace function public.heures_messagerie(p_etablissement uuid)
returns jsonb
language sql stable security definer set search_path = public
as $$
  select jsonb_build_object('debut', to_char(e.messagerie_debut, 'HH24:MI'), 'fin', to_char(e.messagerie_fin, 'HH24:MI'),
                            'jours', to_jsonb(e.messagerie_jours), 'ouverte', public.dans_heures_messagerie(e.id))
  from public.etablissements e
  where e.id = p_etablissement
    and (e.id in (select public.mes_etablissements()) or e.id in (select public.ecoles_de_mes_enfants()));
$$;

create or replace function public.definir_heures_messagerie(p_etablissement uuid, p_debut time, p_fin time, p_jours smallint[])
returns void
language plpgsql volatile security definer set search_path = public
as $$
begin
  if not coalesce(public.est_direction(p_etablissement), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if p_debut is null or p_fin is null or p_debut >= p_fin then
    raise exception 'HEURES_INVALIDES' using errcode = '22023';
  end if;
  if p_jours is null or array_length(p_jours, 1) is null
     or exists (select 1 from unnest(p_jours) j where j not between 1 and 7) then
    raise exception 'JOURS_INVALIDES' using errcode = '22023';
  end if;
  update public.etablissements
     set messagerie_debut = p_debut, messagerie_fin = p_fin,
         messagerie_jours = (select array_agg(distinct j order by j) from unnest(p_jours) j)
   where id = p_etablissement;
end;
$$;
revoke execute on function public.heures_messagerie(uuid), public.definir_heures_messagerie(uuid, time, time, smallint[])
  from public, anon;
grant execute on function public.heures_messagerie(uuid), public.definir_heures_messagerie(uuid, time, time, smallint[])
  to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Notification « au calme » : reportée à l'ouverture de la messagerie
-- ---------------------------------------------------------------------------
alter table public.notifications
  add column if not exists envoyer_apres timestamptz;

create or replace function public.notifier_push_calme(
  p_etablissement uuid, p_destinataire uuid, p_type text, p_contenu text, p_variables jsonb default '{}'::jsonb)
returns void
language sql volatile security definer set search_path = public
as $$
  insert into public.notifications (etablissement_id, destinataire, type, canal, contenu, variables, statut, envoyer_apres)
  values (p_etablissement, p_destinataire, p_type, 'push'::public.canal_notification, p_contenu,
          coalesce(p_variables, '{}'::jsonb), 'en_attente'::public.statut_notification,
          nullif(public.prochaine_ouverture_messagerie(p_etablissement), now()));
$$;
revoke execute on function public.notifier_push_calme(uuid, uuid, text, text, jsonb) from public, anon, authenticated;

-- Le service d'envoi respecte le report (une nuit, un week-end).
create or replace function public.reserver_notifications_push(p_limite integer default 100)
returns table (id uuid, destinataire uuid, type text, contenu text, variables jsonb, jetons text[])
language plpgsql volatile security definer set search_path = public
as $$
#variable_conflict use_column
begin
  return query
  with lot as (
    select n.id from public.notifications n
    where n.canal = 'push' and n.statut = 'en_attente' and n.deleted_at is null
      and (n.push_verrou_jusqu_a is null or n.push_verrou_jusqu_a < now())
      and (n.envoyer_apres is null or n.envoyer_apres <= now())
      and coalesce(n.envoyer_apres, n.created_at) > now() - interval '2 days'
    order by coalesce(n.envoyer_apres, n.created_at)
    limit greatest(1, least(coalesce(p_limite, 100), 500))
    for update skip locked
  )
  update public.notifications n
     set push_verrou_jusqu_a = now() + interval '5 minutes', push_tentatives = n.push_tentatives + 1
    from lot
   where n.id = lot.id
  returning n.id, n.destinataire, n.type, n.contenu, n.variables,
            array(select j.jeton from public.jetons_push j where j.profile_id = n.destinataire);
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Le parent écrit à l'école (cahier de liaison étendu)
-- ---------------------------------------------------------------------------
alter table public.messages_liaison
  add column if not exists destinataire_id uuid references public.profiles (id);

comment on column public.messages_liaison.destinataire_id is
  'REG-34 : mot écrit par un parent — membre du personnel à qui il s''adresse (enseignant de l''élève ou direction). Le fil n''est lu que par ce destinataire, la direction et les parents confirmés.';

-- Personnel qui voit un fil : fil ouvert par l'école → personnel qui écrit
-- au sujet de l'élève ; fil ouvert par un parent → son destinataire et la
-- direction.
create or replace function public.personnel_voit_fil(p_mot uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.messages_liaison m
    where m.id = p_mot and m.mot_id is null
      and (case when m.destinataire_id is null then public.ecrit_liaison(m.fiche_eleve_id)
                else m.destinataire_id = auth.uid() or coalesce(public.est_direction(m.etablissement_id), false) end));
$$;
revoke execute on function public.personnel_voit_fil(uuid) from public, anon;
grant execute on function public.personnel_voit_fil(uuid) to authenticated;

create or replace function public.liaison_visible(p_message uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.messages_liaison m
    where m.id = p_message
      and (public.personnel_voit_fil(coalesce(m.mot_id, m.id))
           or (m.masque_le is null and public.est_parent_confirme(m.fiche_eleve_id))));
$$;

-- Destinataires proposés au parent : la direction et les enseignants de la
-- classe de son enfant (année courante), avec leurs matières ; et les heures
-- de messagerie de l'école, montrées avant d'écrire.
create or replace function public.destinataires_liaison(p_fiche uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_etab uuid;
begin
  if not public.est_parent_confirme(p_fiche) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  select etablissement_id into v_etab from public.fiches_eleves where id = p_fiche;
  return jsonb_build_object('heures', public.heures_messagerie(v_etab), 'destinataires', (
    select coalesce(jsonb_agg(x order by x ->> 'ordre', x ->> 'nom'), '[]'::jsonb) from (
      select jsonb_build_object('id', m.profile_id, 'nom', public.nom_profil(m.profile_id),
                                'role', 'Direction', 'ordre', '0') as x
      from public.etablissements_membres m
      join public.profiles p on p.id = m.profile_id and p.statut_compte = 'actif' and p.deleted_at is null
      where m.etablissement_id = v_etab and m.actif and m.deleted_at is null and m.role_dans_etablissement = 'direction'
      union all
      select jsonb_build_object('id', a.enseignant_profile_id, 'nom', public.nom_profil(a.enseignant_profile_id),
                                'role', coalesce(string_agg(distinct pm.nom, ', '), 'Enseignant'), 'ordre', '1')
      from public.inscriptions i
      join public.annees_scolaires an on an.id = i.annee_scolaire_id and an.courante
      join public.affectations_enseignants a on a.classe_id = i.classe_id and a.annee_scolaire_id = i.annee_scolaire_id
                                              and a.deleted_at is null
      join public.profiles p on p.id = a.enseignant_profile_id and p.statut_compte = 'actif' and p.deleted_at is null
      left join public.programmes_matieres pm on pm.id = a.programme_matiere_id
      where i.fiche_eleve_id = p_fiche and i.statut = 'active' and i.deleted_at is null
        and a.enseignant_profile_id not in (
          select m2.profile_id from public.etablissements_membres m2
          where m2.etablissement_id = v_etab and m2.actif and m2.role_dans_etablissement = 'direction')
      group by a.enseignant_profile_id
    ) s));
end;
$$;
revoke execute on function public.destinataires_liaison(uuid) from public, anon;
grant execute on function public.destinataires_liaison(uuid) to authenticated;

create or replace function public.ecrire_mot_parent(p_id uuid, p_fiche uuid, p_destinataire uuid, p_corps text)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_etab uuid;
  v_eleve text;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;
  if public.message_liaison_deja_recu(p_id) then
    return jsonb_build_object('id', p_id, 'deja_recu', true);
  end if;
  if not public.est_parent_confirme(p_fiche) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if not exists (select 1 from jsonb_array_elements(public.destinataires_liaison(p_fiche) -> 'destinataires') d
                 where (d ->> 'id')::uuid = p_destinataire) then
    raise exception 'DESTINATAIRE_INVALIDE' using errcode = '22023';
  end if;
  if char_length(trim(coalesce(p_corps, ''))) < 1 then
    raise exception 'TEXTE_VIDE' using errcode = '22023';
  end if;
  select etablissement_id, prenom into v_etab, v_eleve from public.fiches_eleves where id = p_fiche;

  insert into public.messages_liaison (id, etablissement_id, fiche_eleve_id, auteur_id, auteur_parent, corps, destinataire_id)
  values (p_id, v_etab, p_fiche, auth.uid(), true, trim(p_corps), p_destinataire);

  perform public.notifier_push_calme(v_etab, p_destinataire, 'cahier_liaison',
    'Message d''un parent au sujet de ' || coalesce(v_eleve, 'un élève'),
    jsonb_build_object('message_id', p_id, 'fiche_eleve_id', p_fiche));
  return jsonb_build_object('id', p_id, 'deja_recu', false, 'ouverture', public.prochaine_ouverture_messagerie(v_etab));
end;
$$;
revoke execute on function public.ecrire_mot_parent(uuid, uuid, uuid, text) from public, anon;
grant execute on function public.ecrire_mot_parent(uuid, uuid, uuid, text) to authenticated;

create or replace function public.repondre_liaison(p_id uuid, p_mot uuid, p_corps text)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  m record;
  v_parent boolean;
  v_eleve text;
  v_personnel uuid;
  d uuid;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;
  if public.message_liaison_deja_recu(p_id) then
    return jsonb_build_object('id', p_id, 'deja_recu', true);
  end if;
  select * into m from public.messages_liaison where id = p_mot and mot_id is null;
  if not found then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  v_parent := public.est_parent_confirme(m.fiche_eleve_id);
  if not v_parent and not public.personnel_voit_fil(p_mot) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if v_parent and m.masque_le is not null then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if char_length(trim(coalesce(p_corps, ''))) < 1 then
    raise exception 'TEXTE_VIDE' using errcode = '22023';
  end if;

  insert into public.messages_liaison (id, etablissement_id, fiche_eleve_id, mot_id, auteur_id, auteur_parent, corps)
  values (p_id, m.etablissement_id, m.fiche_eleve_id, p_mot, auth.uid(), v_parent, trim(p_corps));

  select prenom into v_eleve from public.fiches_eleves where id = m.fiche_eleve_id;
  if v_parent then
    -- Réponse d'un parent : le membre du personnel du fil est prévenu, à
    -- l'ouverture de la messagerie.
    v_personnel := coalesce(m.destinataire_id, m.auteur_id);
    if v_personnel <> auth.uid() then
      perform public.notifier_push_calme(m.etablissement_id, v_personnel, 'cahier_liaison',
        'Cahier de liaison de ' || coalesce(v_eleve, 'l''élève') || ' : réponse d''un parent',
        jsonb_build_object('message_id', p_id, 'mot_id', p_mot, 'fiche_eleve_id', m.fiche_eleve_id));
    end if;
  else
    for d in select * from public.parents_confirmes(m.fiche_eleve_id) loop
      perform public.notifier_push(m.etablissement_id, d, 'cahier_liaison',
        'Cahier de liaison de ' || coalesce(v_eleve, 'votre enfant') || ' : nouvelle réponse',
        jsonb_build_object('message_id', p_id, 'mot_id', p_mot, 'fiche_eleve_id', m.fiche_eleve_id));
    end loop;
  end if;
  return jsonb_build_object('id', p_id, 'deja_recu', false);
end;
$$;

-- Lecture : le parent confirme les messages de l'école ; le personnel du fil
-- confirme ceux des parents (« Lu par l'école »).
create or replace function public.confirmer_lecture_liaison(p_message uuid)
returns void
language plpgsql volatile security definer set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;
  if not exists (select 1 from public.messages_liaison m
                 where m.id = p_message
                   and ((m.masque_le is null and public.est_parent_confirme(m.fiche_eleve_id))
                        or public.personnel_voit_fil(coalesce(m.mot_id, m.id)))) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  insert into public.lectures_liaison (message_id, profile_id) values (p_message, auth.uid())
  on conflict do nothing;
end;
$$;

-- Fil d'un élève, fil par fil selon ce que le compte peut voir.
create or replace function public.cahier_liaison(p_fiche uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_parent boolean := public.est_parent_confirme(p_fiche);
  v_parents integer;
begin
  if not v_parent and not public.ecrit_liaison(p_fiche)
     and not exists (select 1 from public.messages_liaison m
                     where m.fiche_eleve_id = p_fiche and m.mot_id is null and m.destinataire_id = auth.uid()) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  select count(*) into v_parents from public.parents_confirmes(p_fiche);
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
        'id', m.id, 'fiche_eleve_id', m.fiche_eleve_id, 'corps', m.corps, 'cree_le', m.cree_le,
        'auteur', public.nom_profil(m.auteur_id), 'de_moi', m.auteur_id = auth.uid(),
        'auteur_parent', m.auteur_parent,
        'destinataire', public.nom_profil(m.destinataire_id),
        'masque_le', m.masque_le, 'motif_masquage', case when v.personnel then m.motif_masquage end,
        'lu', exists (select 1 from public.lectures_liaison l where l.message_id = m.id and l.profile_id = auth.uid()),
        'lu_par_ecole', m.auteur_parent and exists (
              select 1 from public.lectures_liaison l where l.message_id = m.id
                and l.profile_id not in (select * from public.parents_confirmes(p_fiche))),
        'lectures', case when v.personnel then (select count(*) from public.lectures_liaison l where l.message_id = m.id
                                                and l.profile_id in (select * from public.parents_confirmes(p_fiche))) end,
        'parents', case when v.personnel then v_parents end,
        'reponses', (select coalesce(jsonb_agg(jsonb_build_object(
              'id', r.id, 'corps', r.corps, 'cree_le', r.cree_le, 'auteur', public.nom_profil(r.auteur_id),
              'de_moi', r.auteur_id = auth.uid(), 'auteur_parent', r.auteur_parent,
              'lu', exists (select 1 from public.lectures_liaison l where l.message_id = r.id and l.profile_id = auth.uid()),
              'masque_le', r.masque_le, 'motif_masquage', case when v.personnel then r.motif_masquage end
            ) order by r.cree_le), '[]'::jsonb)
            from public.messages_liaison r
            where r.mot_id = m.id and (v.personnel or r.masque_le is null))
      ) order by m.cree_le desc), '[]'::jsonb)
    from public.messages_liaison m
    cross join lateral (select public.personnel_voit_fil(m.id) as personnel) v
    where m.fiche_eleve_id = p_fiche and m.mot_id is null
      and (v.personnel or (v_parent and m.masque_le is null)));
end;
$$;

-- Élèves du cahier : pour le personnel, aussi ceux dont un parent lui a écrit.
create or replace function public.eleves_cahier_liaison(p_etablissement uuid default null)
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_agg(x order by x ->> 'classe', x ->> 'nom'), '[]'::jsonb) from (
    select jsonb_build_object(
      'fiche_eleve_id', f.id, 'nom', trim(coalesce(f.prenom, '') || ' ' || coalesce(f.nom, '')),
      'classe', (select c.nom from public.inscriptions i join public.classes c on c.id = i.classe_id
                 join public.annees_scolaires a on a.id = i.annee_scolaire_id and a.courante
                 where i.fiche_eleve_id = f.id and i.statut = 'active' and i.deleted_at is null limit 1),
      'etablissement_id', f.etablissement_id,
      'a_lire', case when p_etablissement is null then
          (select count(*) from public.messages_liaison m
           where m.fiche_eleve_id = f.id and m.masque_le is null and not m.auteur_parent
             and not exists (select 1 from public.lectures_liaison l where l.message_id = m.id and l.profile_id = auth.uid()))
        else
          (select count(*) from public.messages_liaison m
           where m.fiche_eleve_id = f.id and m.auteur_parent
             and public.personnel_voit_fil(coalesce(m.mot_id, m.id))
             and not exists (select 1 from public.lectures_liaison l where l.message_id = m.id and l.profile_id = auth.uid()))
        end) as x
    from public.fiches_eleves f
    where f.deleted_at is null
      and ((p_etablissement is null and public.est_parent_confirme(f.id))
           or (p_etablissement is not null and f.etablissement_id = p_etablissement
               and (public.ecrit_liaison(f.id)
                    or exists (select 1 from public.messages_liaison m
                               where m.fiche_eleve_id = f.id and m.mot_id is null and m.destinataire_id = auth.uid()))))
  ) s;
$$;

-- ---------------------------------------------------------------------------
-- 4. Groupes de classe
-- ---------------------------------------------------------------------------
alter table public.groupes_discussion
  add column if not exists eleves_peuvent_ecrire boolean not null default true;
alter table public.messages_groupe
  add column if not exists motif_suppression text;

comment on column public.groupes_discussion.eleves_peuvent_ecrire is
  'REG-34 : faux = le groupe ne sert qu''aux messages des enseignants (annonces de la classe).';

create table if not exists public.lectures_groupe (
  groupe_id uuid not null references public.groupes_discussion (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  lu_jusqu_a timestamptz not null default now(),
  primary key (groupe_id, profile_id)
);
alter table public.lectures_groupe enable row level security;
drop policy if exists lectures_groupe_select on public.lectures_groupe;
create policy lectures_groupe_select on public.lectures_groupe for select using (profile_id = auth.uid());
revoke insert, update, delete on public.lectures_groupe from anon, authenticated;

-- Règles d'écriture des élèves, quelle que soit la voie (fonction ou insertion
-- directe permise par la règle M9) : groupe ouvert aux élèves, heures de
-- messagerie de l'école.
create or replace function public.messages_groupe_regles_eleves()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  g record;
begin
  if auth.uid() is null or public.moderateur_groupe(new.groupe_id) then
    return new;
  end if;
  select * into g from public.groupes_discussion where id = new.groupe_id;
  if g.statut <> 'active' then
    raise exception 'GROUPE_SUSPENDU' using errcode = '42501';
  end if;
  if not g.eleves_peuvent_ecrire then
    raise exception 'GROUPE_LECTURE_SEULE' using errcode = '42501';
  end if;
  if not public.dans_heures_messagerie(g.etablissement_id) then
    raise exception 'HORS_HEURES_MESSAGERIE' using errcode = '42501';
  end if;
  return new;
end;
$$;
drop trigger if exists messages_groupe_regles_eleves_trg on public.messages_groupe;
create trigger messages_groupe_regles_eleves_trg
  before insert on public.messages_groupe
  for each row execute procedure public.messages_groupe_regles_eleves();

-- Groupe de la classe : créé à la demande par un enseignant affecté ou la
-- direction (règle M9 n° 1 : jamais un élève) ; renvoie l'existant.
create or replace function public.creer_groupe_classe(p_classe uuid)
returns uuid
language plpgsql volatile security definer set search_path = public
as $$
declare
  c record;
  v_id uuid;
begin
  select * into c from public.classes where id = p_classe and deleted_at is null;
  if not found or not (public.est_enseignant_affecte(p_classe) or coalesce(public.est_direction(c.etablissement_id), false)) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  select id into v_id from public.groupes_discussion
   where classe_id = p_classe and annee_scolaire_id = c.annee_scolaire_id and deleted_at is null;
  if v_id is not null then
    return v_id;
  end if;
  insert into public.groupes_discussion (etablissement_id, classe_id, annee_scolaire_id, nom, enseignant_createur_id)
  values (c.etablissement_id, p_classe, c.annee_scolaire_id, 'Classe ' || c.nom, auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

-- Envoyer un message : clé de l'appareil, renvoi sans doublon. Notification :
-- un message d'un adulte prévient la classe (à l'ouverture de la
-- messagerie) ; un message d'élève ne réveille personne.
create or replace function public.envoyer_message_groupe(p_id uuid, p_groupe uuid, p_corps text)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  g record;
  v_auteur uuid;
  v_adulte boolean;
  d uuid;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;
  select auteur_id into v_auteur from public.messages_groupe where id = p_id;
  if found then
    if v_auteur <> auth.uid() then
      raise exception 'CLE_DEJA_UTILISEE' using errcode = '23505';
    end if;
    return jsonb_build_object('id', p_id, 'deja_recu', true);
  end if;
  if not public.membre_groupe(p_groupe) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if char_length(trim(coalesce(p_corps, ''))) < 1 then
    raise exception 'TEXTE_VIDE' using errcode = '22023';
  end if;
  select * into g from public.groupes_discussion where id = p_groupe;
  v_adulte := public.moderateur_groupe(p_groupe);

  insert into public.messages_groupe (id, etablissement_id, groupe_id, auteur_id, contenu)
  values (p_id, g.etablissement_id, p_groupe, auth.uid(), left(trim(p_corps), 2000));

  insert into public.lectures_groupe (groupe_id, profile_id, lu_jusqu_a) values (p_groupe, auth.uid(), now())
  on conflict (groupe_id, profile_id) do update set lu_jusqu_a = excluded.lu_jusqu_a;

  if v_adulte then
    for d in
      select f.profile_id from public.inscriptions i
      join public.fiches_eleves f on f.id = i.fiche_eleve_id and f.deleted_at is null and f.profile_id is not null
      where i.classe_id = g.classe_id and i.annee_scolaire_id = g.annee_scolaire_id and i.deleted_at is null
      union
      select a.enseignant_profile_id from public.affectations_enseignants a
      where a.classe_id = g.classe_id and a.annee_scolaire_id = g.annee_scolaire_id and a.deleted_at is null
    loop
      if d <> auth.uid() then
        perform public.notifier_push_calme(g.etablissement_id, d, 'groupe_classe',
          g.nom || ' : nouveau message de ' || coalesce(public.nom_profil(auth.uid()), 'l''enseignant'),
          jsonb_build_object('groupe_id', p_groupe, 'message_id', p_id));
      end if;
    end loop;
  end if;
  return jsonb_build_object('id', p_id, 'deja_recu', false);
end;
$$;

-- Mes groupes : élève (sa classe), enseignant (ses classes), direction ou
-- modération (toutes) ; non lus, dernier message, et pour le personnel les
-- classes encore sans groupe.
create or replace function public.mes_groupes_classe(p_etablissement uuid)
returns jsonb
language sql stable security definer set search_path = public
as $$
  select jsonb_build_object(
    'groupes', coalesce((
      select jsonb_agg(jsonb_build_object(
          'id', g.id, 'nom', g.nom, 'classe_id', g.classe_id, 'classe', c.nom, 'statut', g.statut,
          'eleves_peuvent_ecrire', g.eleves_peuvent_ecrire,
          'moderateur', public.moderateur_groupe(g.id),
          'non_lus', (select count(*) from public.messages_groupe m
                      where m.groupe_id = g.id and not m.supprime and m.auteur_id <> auth.uid()
                        and m.created_at > coalesce((select l.lu_jusqu_a from public.lectures_groupe l
                                                     where l.groupe_id = g.id and l.profile_id = auth.uid()), '-infinity')),
          'dernier', (select jsonb_build_object('auteur', public.nom_profil(m.auteur_id),
                                                'extrait', case when m.supprime then null else left(m.contenu, 80) end,
                                                'cree_le', m.created_at)
                      from public.messages_groupe m where m.groupe_id = g.id
                      order by m.created_at desc limit 1),
          'signalements', case when public.moderateur_groupe(g.id) then
             (select count(*) from public.signalements_message s join public.messages_groupe m on m.id = s.message_id
              where m.groupe_id = g.id and s.statut = 'ouvert') end
        ) order by c.nom)
      from public.groupes_discussion g
      join public.classes c on c.id = g.classe_id
      join public.annees_scolaires a on a.id = g.annee_scolaire_id and a.courante
      where g.etablissement_id = p_etablissement and g.deleted_at is null and public.membre_groupe(g.id)), '[]'::jsonb),
    'classes_sans_groupe', coalesce((
      select jsonb_agg(jsonb_build_object('classe_id', c.id, 'classe', c.nom) order by c.nom)
      from public.classes c
      join public.annees_scolaires a on a.id = c.annee_scolaire_id and a.courante
      where c.etablissement_id = p_etablissement and c.deleted_at is null and c.actif
        and (public.est_enseignant_affecte(c.id) or coalesce(public.est_direction(p_etablissement), false))
        and not exists (select 1 from public.groupes_discussion g
                        where g.classe_id = c.id and g.annee_scolaire_id = c.annee_scolaire_id and g.deleted_at is null)), '[]'::jsonb)
  );
$$;

-- Fil d'un groupe (les plus récents, au plus 200). Message masqué : l'élève
-- voit « message retiré », les adultes le texte et le motif.
create or replace function public.fil_groupe_classe(p_groupe uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_moderateur boolean := public.moderateur_groupe(p_groupe);
begin
  if not public.membre_groupe(p_groupe) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  return (
    select coalesce(jsonb_agg(x order by x ->> 'cree_le'), '[]'::jsonb) from (
      select jsonb_build_object(
        'id', m.id, 'auteur', public.nom_profil(m.auteur_id), 'de_moi', m.auteur_id = auth.uid(),
        'adulte', exists (select 1 from public.groupes_discussion g where g.id = m.groupe_id
                          and (g.enseignant_createur_id = m.auteur_id
                               or exists (select 1 from public.affectations_enseignants a
                                          where a.classe_id = g.classe_id and a.annee_scolaire_id = g.annee_scolaire_id
                                            and a.enseignant_profile_id = m.auteur_id and a.deleted_at is null)
                               or exists (select 1 from public.etablissements_membres em
                                          where em.etablissement_id = g.etablissement_id and em.profile_id = m.auteur_id
                                            and em.actif and em.role_dans_etablissement <> 'eleve'))),
        'corps', case when m.supprime and not v_moderateur then null else m.contenu end,
        'masque', m.supprime, 'motif', case when v_moderateur then m.motif_suppression end,
        'cree_le', m.created_at) as x
      from public.messages_groupe m
      where m.groupe_id = p_groupe
      order by m.created_at desc
      limit 200) s);
end;
$$;

create or replace function public.marquer_groupe_lu(p_groupe uuid)
returns void
language plpgsql volatile security definer set search_path = public
as $$
begin
  if not public.membre_groupe(p_groupe) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  insert into public.lectures_groupe (groupe_id, profile_id, lu_jusqu_a) values (p_groupe, auth.uid(), now())
  on conflict (groupe_id, profile_id) do update set lu_jusqu_a = greatest(public.lectures_groupe.lu_jusqu_a, excluded.lu_jusqu_a);
end;
$$;

-- Réglages du groupe (modération) : ouvert aux élèves ou non, suspendu.
create or replace function public.regler_groupe_classe(p_groupe uuid, p_eleves_peuvent_ecrire boolean, p_actif boolean default true)
returns void
language plpgsql volatile security definer set search_path = public
as $$
begin
  if not public.moderateur_groupe(p_groupe) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  update public.groupes_discussion
     set eleves_peuvent_ecrire = coalesce(p_eleves_peuvent_ecrire, eleves_peuvent_ecrire),
         statut = case when p_actif then 'active'::public.statut_groupe_discussion
                       else 'suspendue'::public.statut_groupe_discussion end
   where id = p_groupe;
end;
$$;

-- Masquer un message (modération) : jamais supprimé, motif, journal d'audit.
create or replace function public.masquer_message_groupe(p_message uuid, p_motif text)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  m record;
begin
  select * into m from public.messages_groupe where id = p_message for update;
  if not found or not public.moderateur_groupe(m.groupe_id) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if char_length(trim(coalesce(p_motif, ''))) < 3 then
    raise exception 'MOTIF_REQUIS' using errcode = '22023';
  end if;
  if m.supprime then
    return;
  end if;
  update public.messages_groupe
     set supprime = true, supprime_par_id = auth.uid(), date_suppression = now(), motif_suppression = trim(p_motif)
   where id = p_message;
  update public.signalements_message set statut = 'traite', traite_par_id = auth.uid(), traite_at = now()
   where message_id = p_message and statut = 'ouvert';
  perform public.enregistrer_audit(m.etablissement_id, 'message_groupe', m.id, 'masque',
    jsonb_build_object('masque', false), jsonb_build_object('masque', true, 'motif', trim(p_motif)), null);
end;
$$;

-- Signaler un message : tout membre ; les modérateurs sont prévenus (à
-- l'ouverture de la messagerie). Un même compte ne signale qu'une fois.
create or replace function public.signaler_message_groupe(p_message uuid, p_motif text)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  m record;
  g record;
  d uuid;
begin
  select * into m from public.messages_groupe where id = p_message;
  if not found or not public.membre_groupe(m.groupe_id) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if char_length(trim(coalesce(p_motif, ''))) < 3 then
    raise exception 'MOTIF_REQUIS' using errcode = '22023';
  end if;
  if exists (select 1 from public.signalements_message where message_id = p_message and signale_par_id = auth.uid()) then
    return;
  end if;
  insert into public.signalements_message (etablissement_id, message_id, signale_par_id, motif)
  values (m.etablissement_id, p_message, auth.uid(), left(trim(p_motif), 500));

  select * into g from public.groupes_discussion where id = m.groupe_id;
  for d in
    select g.enseignant_createur_id
    union
    select em.profile_id from public.etablissements_membres em
    where em.etablissement_id = g.etablissement_id and em.actif and em.role_dans_etablissement = 'direction'
  loop
    if d <> auth.uid() then
      perform public.notifier_push_calme(g.etablissement_id, d, 'groupe_classe',
        g.nom || ' : un message a été signalé', jsonb_build_object('groupe_id', g.id, 'message_id', p_message));
    end if;
  end loop;
end;
$$;

-- Signalements ouverts d'un groupe (modération).
create or replace function public.signalements_groupe(p_groupe uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.moderateur_groupe(p_groupe) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
        'id', s.id, 'message_id', s.message_id, 'motif', s.motif, 'par', public.nom_profil(s.signale_par_id),
        'extrait', left(m.contenu, 120), 'auteur', public.nom_profil(m.auteur_id), 'cree_le', s.created_at)
      order by s.created_at), '[]'::jsonb)
    from public.signalements_message s
    join public.messages_groupe m on m.id = s.message_id
    where m.groupe_id = p_groupe and s.statut = 'ouvert');
end;
$$;

-- Signalement écarté (message conservé tel quel).
create or replace function public.ecarter_signalement(p_signalement uuid)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_groupe uuid;
begin
  select m.groupe_id into v_groupe from public.signalements_message s
    join public.messages_groupe m on m.id = s.message_id where s.id = p_signalement;
  if v_groupe is null or not public.moderateur_groupe(v_groupe) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  update public.signalements_message set statut = 'rejete', traite_par_id = auth.uid(), traite_at = now()
   where id = p_signalement and statut = 'ouvert';
end;
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.creer_groupe_classe(uuid)', 'public.envoyer_message_groupe(uuid, uuid, text)',
    'public.mes_groupes_classe(uuid)', 'public.fil_groupe_classe(uuid)', 'public.marquer_groupe_lu(uuid)',
    'public.regler_groupe_classe(uuid, boolean, boolean)', 'public.masquer_message_groupe(uuid, text)',
    'public.signaler_message_groupe(uuid, text)', 'public.signalements_groupe(uuid)', 'public.ecarter_signalement(uuid)'
  ] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 5. Résumé de l'accueil : cahier selon le fil, groupes non lus
-- ---------------------------------------------------------------------------
do $$
declare
  v_def text := pg_get_functiondef('public.accueil_resume(uuid, uuid)'::regprocedure);
  v_avant text := 'and public.ecrit_liaison(m.fiche_eleve_id) and m.auteur_parent))';
  v_ancre text := 'v_res := v_res || jsonb_build_object(''cahier_non_lu'', v_n);';
begin
  if position('groupes_non_lus' in v_def) > 0 then
    return;
  end if;
  if position(v_avant in v_def) = 0 or position(v_ancre in v_def) = 0 then
    raise exception 'accueil_resume : texte attendu introuvable';
  end if;
  v_def := replace(v_def, v_avant, 'and m.auteur_parent and public.personnel_voit_fil(coalesce(m.mot_id, m.id))))');
  v_def := replace(v_def, v_ancre, v_ancre || $r$

  select count(*) into v_n from public.messages_groupe mg
    join public.groupes_discussion g on g.id = mg.groupe_id and g.deleted_at is null
   where g.etablissement_id = p_etablissement and not mg.supprime and mg.auteur_id <> v_uid
     and mg.created_at > now() - interval '30 days' and public.membre_groupe(g.id)
     and mg.created_at > coalesce((select l.lu_jusqu_a from public.lectures_groupe l
                                   where l.groupe_id = g.id and l.profile_id = v_uid), '-infinity');
  v_res := v_res || jsonb_build_object('groupes_non_lus', v_n);$r$);
  execute v_def;
end $$;
