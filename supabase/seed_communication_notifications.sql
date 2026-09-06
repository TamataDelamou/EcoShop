-- ============================================================================
-- EcoShop — M9 — Maquette de données Communication & Notifications
--
-- S'appuie sur : l'établissement « Lycée Innovation Conakry » (M0) et les
-- comptes existants (enseignant1 +224620001020, direction1 +224620001030).
-- Crée : un compte parent, des préférences de canaux, des modèles de messages,
-- des notifications (absence, note, alerte) et un journal d'envois.
--
-- Idempotent : recherches par clés naturelles + on conflict do nothing.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Helper : créer ou retrouver un compte (auth.users → profil, par téléphone)
-- ---------------------------------------------------------------------------
create or replace function pg_temp.creer_compte(p_phone text, p_role text)
returns uuid
language plpgsql
set search_path = public, auth, pg_catalog
as $$
declare
  v_id uuid;
begin
  select p.id into v_id
  from public.profiles p
  join public.identifiants_comptes i on i.profile_id = p.id
  where i.valeur = p_phone
  limit 1;

  if v_id is null then
    insert into auth.users (id, phone) values (gen_random_uuid(), replace(p_phone, '+', ''));
    select p.id into v_id
    from public.profiles p
    join public.identifiants_comptes i on i.profile_id = p.id
    where i.valeur = p_phone
    limit 1;
  end if;

  update public.profiles set role_racine = p_role::public.role_racine where id = v_id;
  return v_id;
end $$;

create temp table if not exists seed_m9 (cle text primary key, val uuid);

insert into seed_m9 (cle, val)
select 'etab', id from public.etablissements where slug = 'lycee-innovation-conakry'
on conflict (cle) do nothing;

-- ---------------------------------------------------------------------------
-- Comptes : parent (nouveau) + retrouver enseignant1 et direction1
-- ---------------------------------------------------------------------------
insert into seed_m9 (cle, val)
values ('parent', pg_temp.creer_compte('+224620001040', 'parent'))
on conflict (cle) do nothing;

insert into seed_m9 (cle, val)
select 'ens1', p.id from public.profiles p
join public.identifiants_comptes i on i.profile_id = p.id
where i.valeur = '+224620001020'
on conflict (cle) do nothing;

insert into seed_m9 (cle, val)
select 'dir1', p.id from public.profiles p
join public.identifiants_comptes i on i.profile_id = p.id
where i.valeur = '+224620001030'
on conflict (cle) do nothing;

-- ---------------------------------------------------------------------------
-- Préférences de canaux
-- ---------------------------------------------------------------------------
insert into public.preferences_canaux (profile_id, canal, actif, horaire_debut, horaire_fin, frequence)
values
  ((select val from seed_m9 where cle = 'ens1'),   'whatsapp', true, '08:00', '19:00', 'immediat'),
  ((select val from seed_m9 where cle = 'dir1'),   'email',    true, '09:00', '18:00', 'quotidien'),
  ((select val from seed_m9 where cle = 'parent'), 'sms',      true, '08:00', '20:00', 'immediat')
on conflict (profile_id, canal) do nothing;

-- ---------------------------------------------------------------------------
-- Modèles de messages
-- ---------------------------------------------------------------------------
insert into public.templates_notifications (etablissement_id, type, canal, contenu, variables)
values
  ((select val from seed_m9 where cle = 'etab'), 'absence',           'sms',      'Votre enfant {{eleve}} est absent(e) le {{date}}.', '["eleve","date"]'),
  ((select val from seed_m9 where cle = 'etab'), 'note',              'sms',      'Nouvelle note en {{matiere}} : {{note}}/20.',     '["matiere","note"]'),
  ((select val from seed_m9 where cle = 'etab'), 'alerte_decrochage', 'whatsapp', 'Alerte pédagogique pour {{eleve}} : merci de contacter la direction.', '["eleve"]'),
  ((select val from seed_m9 where cle = 'etab'), 'evenement',         'sms',      'Rappel : {{evenement}} le {{date}}.',             '["evenement","date"]')
on conflict (etablissement_id, type, canal) do nothing;

-- ---------------------------------------------------------------------------
-- Notifications (idempotentes : garde sur destinataire + type + contenu)
-- ---------------------------------------------------------------------------
insert into public.notifications
  (etablissement_id, destinataire, type, canal, contenu, variante, statut, date_envoi, date_lecture)
select (select val from seed_m9 where cle = 'etab'), (select val from seed_m9 where cle = 'parent'),
       'absence', 'sms', 'Votre enfant Aicha est absente le 2026-09-08.', null, 'lue',
       now() - interval '2 days', now() - interval '2 days' + interval '3 hours'
where not exists (
  select 1 from public.notifications n
  where n.destinataire = (select val from seed_m9 where cle = 'parent')
    and n.type = 'absence' and n.contenu = 'Votre enfant Aicha est absente le 2026-09-08.'
);

insert into public.notifications
  (etablissement_id, destinataire, type, canal, contenu, variante, statut, date_envoi, date_lecture)
select (select val from seed_m9 where cle = 'etab'), (select val from seed_m9 where cle = 'parent'),
       'note', 'sms', 'Nouvelle note en Mathématiques : 14/20.', 'A', 'envoyee',
       now() - interval '1 day', null
where not exists (
  select 1 from public.notifications n
  where n.destinataire = (select val from seed_m9 where cle = 'parent')
    and n.type = 'note' and n.variante = 'A'
);

insert into public.notifications
  (etablissement_id, destinataire, type, canal, contenu, variante, statut, date_envoi, date_lecture)
select (select val from seed_m9 where cle = 'etab'), (select val from seed_m9 where cle = 'parent'),
       'note', 'sms', 'Nouvelle note en Physique-Chimie : 11/20.', 'B', 'envoyee',
       now() - interval '1 day', null
where not exists (
  select 1 from public.notifications n
  where n.destinataire = (select val from seed_m9 where cle = 'parent')
    and n.type = 'note' and n.variante = 'B'
);

insert into public.notifications
  (etablissement_id, destinataire, type, canal, contenu, variante, statut, date_envoi, date_lecture)
select (select val from seed_m9 where cle = 'etab'), (select val from seed_m9 where cle = 'ens1'),
       'evenement', 'whatsapp', 'Rappel : conseil de classe le 2026-09-20.', null, 'envoyee',
       now() - interval '1 day', null
where not exists (
  select 1 from public.notifications n
  where n.destinataire = (select val from seed_m9 where cle = 'ens1') and n.type = 'evenement'
);

insert into public.notifications
  (etablissement_id, destinataire, type, canal, contenu, variante, statut, date_envoi, date_lecture)
select (select val from seed_m9 where cle = 'etab'), (select val from seed_m9 where cle = 'dir1'),
       'alerte_decrochage', 'email', 'Alerte pédagogique pour Ibrahim : merci de contacter la famille.', null, 'en_attente',
       null, null
where not exists (
  select 1 from public.notifications n
  where n.destinataire = (select val from seed_m9 where cle = 'dir1') and n.type = 'alerte_decrochage'
);

-- Journal d'envois pour les notifications effectivement parties.
insert into public.logs_envois (etablissement_id, notification_id, fournisseur, statut, message_id_fournisseur)
select (select val from seed_m9 where cle = 'etab'), n.id, v.fournisseur, 'envoye', v.msg_id
from public.notifications n
join (values
  ('absence',           'twilio',   'MSG-0001'),
  ('note',              'twilio',   'MSG-0002'),
  ('evenement',         'whatsapp', 'MSG-0003'),
  ('alerte_decrochage', 'smtp',     'MSG-0004')
) as v(type, fournisseur, msg_id) on v.type = n.type
where n.etablissement_id = (select val from seed_m9 where cle = 'etab')
  and n.statut in ('envoyee', 'lue')
  and not exists (
    select 1 from public.logs_envois l
    where l.notification_id = n.id and l.fournisseur = v.fournisseur
  );

-- ============================================================================
-- Fin de la maquette M9.
-- ============================================================================
