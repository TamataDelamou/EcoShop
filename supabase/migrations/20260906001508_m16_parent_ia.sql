-- ============================================================================
-- EcoShop — M16, sous-livrable 4/7 : Parent IA (déclaration manuelle)
-- ============================================================================
-- Porté depuis ecoshop_flutter/PARENT_IA.md (cahier §15.3) : autolimitation
-- numérique activée par l'ÉLÈVE lui-même (jamais le parent, jamais
-- l'établissement) — l'IA croise le temps d'usage réseaux sociaux/jeux avec
-- le score de risque d'échec déjà matérialisé (sous-livrable 1/7), et
-- notifie l'élève si l'usage est jugé excessif au vu de ce risque. Le parent
-- consulte l'historique en lecture seule.
--
-- Périmètre acté pour cette passe (décision explicite) :
--   • DÉCLARATION MANUELLE UNIQUEMENT (formulaire minutes + app). La mesure
--     automatique Android (`usage_stats`/`UsageStatsManager`, permission
--     système `PACKAGE_USAGE_STATS`) est un écart documenté séparément —
--     non construite ici : elle nécessite un appareil/émulateur Android réel
--     avec la permission accordée pour être vérifiée empiriquement, ce que
--     l'outillage local (podman/supabase) ne permet pas, et ce projet ne
--     construit jamais un mécanisme de permission/sécurité sans pouvoir le
--     vérifier réellement. La déclaration manuelle couvre déjà exactement le
--     chemin de repli qu'utilisait la source pour iOS et pour Android sans
--     permission — colonne `source_donnee` volontairement générique
--     (`'declaration_manuelle' | 'auto_android'`) pour ne pas fermer la porte
--     à cette extension future sur la même infrastructure.
--   • Verrouillage d'engagement de 30 jours, non contournable — calculé et
--     posé UNIQUEMENT côté serveur (comme la source : le premier ship avait
--     laissé l'écriture cliente ouverte, corrigé après coup — ici construit
--     dès la conception, AUCUNE policy d'écriture cliente sur
--     `parent_ia_config`/`parent_ia_historique`, jamais une confiance dans le
--     client pour une date qui conditionne un contournement possible).
--   • Score de risque RÉUTILISÉ (`risque_reussite_actuel`, sous-1/7), jamais
--     recalculé — la source lit son propre `risqueEchecActuel` (formule
--     distincte, 70% évolution des moyennes + 30% présence) : EcoShop
--     n'importe pas cette formule, elle expose la sienne, déjà matérialisée.
--   • Client n'appelle jamais l'API Anthropic directement : nouvelle Edge
--     Function `analyser_usage_parent_ia`, prompt technique interne séparé
--     des 3 personas officiels (jamais exposé en conversation).
--   • Visibilité élève + parent confirmé UNIQUEMENT, PAS le personnel/
--     direction de l'établissement (divergence délibérée de
--     `fiche_visible()` — reprise à l'identique de la source, qui exclut
--     aussi explicitement le personnel de cette donnée sensible de
--     bien-être numérique d'un mineur).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------
create table if not exists public.parent_ia_config (
  id uuid primary key default gen_random_uuid(),
  fiche_eleve_id uuid not null references public.fiches_eleves (id) on delete cascade,
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  actif boolean not null default false,
  date_activation timestamptz,
  verrouille_jusquau timestamptz,
  consentement_eleve boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint parent_ia_config_fiche_unique unique (fiche_eleve_id)
);

comment on table public.parent_ia_config is
  'Paramètre PARENT IA (M16 4/7, cahier §15.3) — écriture réservée aux fonctions SECURITY DEFINER ci-dessous, jamais au client.';

create table if not exists public.parent_ia_historique (
  id uuid primary key default gen_random_uuid(),
  fiche_eleve_id uuid not null references public.fiches_eleves (id) on delete cascade,
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  app_concernee text not null check (length(app_concernee) > 0),
  temps_usage_minutes int not null check (temps_usage_minutes >= 0),
  niveau_risque_echec int not null check (niveau_risque_echec between 0 and 100),
  matiere_a_risque text,
  source_donnee text not null default 'declaration_manuelle'
    check (source_donnee in ('declaration_manuelle', 'auto_android')),
  created_at timestamptz not null default now()
);

comment on table public.parent_ia_historique is
  'Restrictions déclenchées par PARENT IA — écrite UNIQUEMENT par enregistrer_restriction_parent_ia (SECURITY DEFINER).';

drop trigger if exists parent_ia_config_set_updated_at on public.parent_ia_config;
create trigger parent_ia_config_set_updated_at
  before update on public.parent_ia_config
  for each row execute procedure public.set_updated_at();

create index if not exists idx_parent_ia_historique_fiche
  on public.parent_ia_historique (fiche_eleve_id, created_at desc);

-- ---------------------------------------------------------------------------
-- 2. Garde-fous multi-tenant (pattern _verifie_tenant, valide la ROW, jamais
--    l'identité de l'appelant) — ★ SECURITY DEFINER ICI, contrairement à la
--    plupart des `_verifie_tenant` du codebase : `fiches_eleves` est une
--    table étroitement protégée par RLS (élève/parent confirmé/personnel
--    uniquement). Un trigger non-security-definer y ferait un SELECT sous
--    les droits de l'APPELANT — invisible pour lui si son insert cible une
--    fiche qu'il ne peut pas voir (ex. tentative sur la fiche d'un autre
--    élève), et la vérification tomberait alors sur un faux
--    FICHE_AUTRE_ETABLISSEMENT (23514) au lieu du vrai rejet RLS attendu
--    (42501) — trouvé exactement par ce cas en testant l'INSERT direct d'un
--    tiers (test 43). Sans risque : ce lookup ne fait que confirmer une
--    cohérence de données déjà garantie par la contrainte de clé étrangère,
--    jamais une décision d'autorisation.
-- ---------------------------------------------------------------------------
create or replace function public.parent_ia_config_verifie_tenant()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_etab uuid;
begin
  select etablissement_id into v_etab from public.fiches_eleves where id = new.fiche_eleve_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'FICHE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;
  return new;
end $$;

drop trigger if exists parent_ia_config_verifie_tenant_trg on public.parent_ia_config;
create trigger parent_ia_config_verifie_tenant_trg
  before insert or update on public.parent_ia_config
  for each row execute procedure public.parent_ia_config_verifie_tenant();

create or replace function public.parent_ia_historique_verifie_tenant()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_etab uuid;
begin
  select etablissement_id into v_etab from public.fiches_eleves where id = new.fiche_eleve_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'FICHE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;
  return new;
end $$;

drop trigger if exists parent_ia_historique_verifie_tenant_trg on public.parent_ia_historique;
create trigger parent_ia_historique_verifie_tenant_trg
  before insert or update on public.parent_ia_historique
  for each row execute procedure public.parent_ia_historique_verifie_tenant();

-- ---------------------------------------------------------------------------
-- 3. Visibilité — élève propriétaire + parent confirmé UNIQUEMENT (jamais le
--    personnel : divergence délibérée de `fiche_visible()`, voir en-tête).
-- ---------------------------------------------------------------------------
create or replace function public.parent_ia_visible(p_fiche uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.fiches_eleves f
    where f.id = p_fiche and f.deleted_at is null
      and (f.profile_id = auth.uid() or public.est_parent_confirme(f.id))
  );
$$;

grant execute on function public.parent_ia_visible(uuid) to authenticated;

alter table public.parent_ia_config enable row level security;
alter table public.parent_ia_historique enable row level security;

-- Aucune policy insert/update/delete définie, sur AUCUNE des deux tables —
-- c'est intentionnel : le client ne peut écrire NULLE PART ici, seules les
-- fonctions SECURITY DEFINER ci-dessous (possédées par le propriétaire des
-- migrations, qui contournent RLS) peuvent le faire. Correctif de sécurité
-- construit dès la conception (voir en-tête), jamais une policy d'écriture
-- ouverte puis restreinte après coup.
drop policy if exists "parent_ia_config_select" on public.parent_ia_config;
create policy "parent_ia_config_select" on public.parent_ia_config
  for select using (public.parent_ia_visible(fiche_eleve_id));

drop policy if exists "parent_ia_historique_select" on public.parent_ia_historique;
create policy "parent_ia_historique_select" on public.parent_ia_historique
  for select using (public.parent_ia_visible(fiche_eleve_id));

-- ---------------------------------------------------------------------------
-- 4. Activation / désactivation — SEULE l'élève propriétaire de la fiche
--    peut agir (jamais un parent, jamais le personnel) ; verrou de 30 jours
--    calculé et posé ICI, infalsifiable côté client.
-- ---------------------------------------------------------------------------
create or replace function public.activer_parent_ia(
  p_fiche_eleve_id uuid,
  p_consentement boolean
)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_etab uuid;
  v_verrou timestamptz;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;

  select etablissement_id into v_etab
  from public.fiches_eleves
  where id = p_fiche_eleve_id and profile_id = auth.uid() and deleted_at is null;

  if v_etab is null then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  if p_consentement is not true then
    raise exception 'CONSENTEMENT_REQUIS' using errcode = '22023';
  end if;

  v_verrou := now() + interval '30 days';

  insert into public.parent_ia_config
    (fiche_eleve_id, etablissement_id, actif, date_activation, verrouille_jusquau, consentement_eleve)
  values
    (p_fiche_eleve_id, v_etab, true, now(), v_verrou, true)
  on conflict (fiche_eleve_id) do update
    set actif = true,
        date_activation = now(),
        verrouille_jusquau = v_verrou,
        consentement_eleve = true,
        updated_at = now();

  return jsonb_build_object('actif', true, 'verrouille_jusquau', v_verrou);
end;
$$;

revoke execute on function public.activer_parent_ia(uuid, boolean) from public, anon;
grant execute on function public.activer_parent_ia(uuid, boolean) to authenticated;

create or replace function public.desactiver_parent_ia(p_fiche_eleve_id uuid)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_config record;
  v_jours int;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;

  if not exists (
    select 1 from public.fiches_eleves
    where id = p_fiche_eleve_id and profile_id = auth.uid() and deleted_at is null
  ) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  select * into v_config from public.parent_ia_config where fiche_eleve_id = p_fiche_eleve_id;

  if v_config is null or v_config.actif is not true then
    raise exception 'PARENT_IA_INACTIF' using errcode = '22023';
  end if;

  if v_config.verrouille_jusquau is not null and v_config.verrouille_jusquau > now() then
    v_jours := ceil(extract(epoch from (v_config.verrouille_jusquau - now())) / 86400);
    raise exception 'PARENT_IA_VERROUILLE % jour(s) restant(s).', v_jours using errcode = '42501';
  end if;

  update public.parent_ia_config
     set actif = false, verrouille_jusquau = null, updated_at = now()
   where fiche_eleve_id = p_fiche_eleve_id;

  return jsonb_build_object('actif', false);
end;
$$;

revoke execute on function public.desactiver_parent_ia(uuid) from public, anon;
grant execute on function public.desactiver_parent_ia(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Préparation d'une déclaration d'usage — lit le score de risque RÉUTILISÉ
--    (jamais recalculé), ne fait AUCUN appel Anthropic (couche SQL pure,
--    l'Edge Function `analyser_usage_parent_ia` s'en charge ensuite). « Pas
--    de consentement = pas d'analyse », comme la source.
-- ---------------------------------------------------------------------------
create or replace function public.preparer_declaration_usage_parent_ia(
  p_fiche_eleve_id uuid,
  p_app_principale text,
  p_minutes int
)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_etab uuid;
  v_annee uuid;
  v_risque numeric;
  v_niveau int;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;

  select etablissement_id into v_etab
  from public.fiches_eleves
  where id = p_fiche_eleve_id and profile_id = auth.uid() and deleted_at is null;

  if v_etab is null then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  if p_app_principale is null or length(trim(p_app_principale)) = 0 then
    raise exception 'APP_INVALIDE' using errcode = '22023';
  end if;
  if p_minutes is null or p_minutes < 0 or p_minutes > 1440 then
    raise exception 'MINUTES_INVALIDES' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.parent_ia_config
    where fiche_eleve_id = p_fiche_eleve_id and actif = true
  ) then
    raise exception 'PARENT_IA_INACTIF' using errcode = '22023';
  end if;

  select id into v_annee from public.annees_scolaires
  where etablissement_id = v_etab and courante
  limit 1;

  if v_annee is not null then
    -- Rafraîchit la source unique avant de lire — jamais un second calcul
    -- (même discipline que `preparer_analyse_risque_echec`, sous-3/7).
    perform public.materialiser_risque_reussite(v_etab, v_annee);
  end if;

  v_risque := public.risque_reussite_actuel(p_fiche_eleve_id);
  -- Repli neutre à 50/100 si l'élève n'a encore aucune donnée matérialisée
  -- — même comportement que la source pour un élève sans note récente.
  v_niveau := coalesce(round(v_risque * 100), 50);

  return jsonb_build_object(
    'fiche_eleve_id', p_fiche_eleve_id,
    'etablissement_id', v_etab,
    'app_principale', trim(p_app_principale),
    'minutes', p_minutes,
    'niveau_risque_echec', v_niveau
  );
end;
$$;

revoke execute on function public.preparer_declaration_usage_parent_ia(uuid, text, int) from public, anon;
grant execute on function public.preparer_declaration_usage_parent_ia(uuid, text, int) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Écriture de la restriction + notification — appelée par l'Edge
--    Function APRÈS la décision de Claude, jamais par le client. Re-vérifie
--    TOUT (propriété de la fiche, PARENT IA actif) — jamais une confiance
--    dans le fait que `preparer_declaration_usage_parent_ia` l'ait déjà fait
--    un instant plus tôt (même discipline que `obtenir_detail_risque_
--    echec_interne`, sous-3/7).
-- ---------------------------------------------------------------------------
create or replace function public.enregistrer_restriction_parent_ia(
  p_fiche_eleve_id uuid,
  p_app_principale text,
  p_minutes int,
  p_niveau_risque int,
  p_message text,
  p_matiere text default null
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_etab uuid;
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;

  select etablissement_id into v_etab
  from public.fiches_eleves
  where id = p_fiche_eleve_id and profile_id = auth.uid() and deleted_at is null;

  if v_etab is null then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.parent_ia_config
    where fiche_eleve_id = p_fiche_eleve_id and actif = true
  ) then
    raise exception 'PARENT_IA_INACTIF' using errcode = '22023';
  end if;

  insert into public.parent_ia_historique
    (fiche_eleve_id, etablissement_id, app_concernee, temps_usage_minutes, niveau_risque_echec, matiere_a_risque, source_donnee)
  values
    (p_fiche_eleve_id, v_etab, p_app_principale, p_minutes, p_niveau_risque, p_matiere, 'declaration_manuelle')
  returning id into v_id;

  insert into public.notifications
    (etablissement_id, destinataire, type, canal, contenu, statut, date_envoi, variables)
  values
    (
      v_etab, auth.uid(), 'parent_ia_restriction', 'push',
      coalesce(p_message, 'Ton usage du téléphone a été jugé élevé au vu de ton profil scolaire actuel.'),
      'envoyee', now(),
      jsonb_build_object('appConcernee', p_app_principale, 'minutes', p_minutes, 'matiereARisque', p_matiere)
    );

  return v_id;
end;
$$;

revoke execute on function public.enregistrer_restriction_parent_ia(uuid, text, int, int, text, text) from public, anon;
grant execute on function public.enregistrer_restriction_parent_ia(uuid, text, int, int, text, text) to authenticated;

-- ============================================================================
-- Fin M16 4/7 — Parent IA (déclaration manuelle).
-- ============================================================================
