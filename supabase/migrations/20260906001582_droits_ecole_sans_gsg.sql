-- ============================================================================
-- EcoShop — Correction de REG-26 : les actions de l'école restent à l'école
-- ============================================================================
-- REG-26 (migration 1575) a délégué douze contrôles « Direction seulement »
-- aux postes du personnel en les réécrivant avec `a_permission`. Or
-- `a_permission` (migration 1570) répond aussi vrai à l'Administrateur GSG :
-- sans le vouloir, GSG pouvait depuis publier des annonces d'une école,
-- proclamer ses résultats, fixer ses mentions finales, enregistrer ses
-- identifiants Orange Money, acheter ses crédits SMS, agréer ses vendeurs ou
-- débloquer le code de ses membres. Le test pgTAP 56 (« ce palier appartient
-- à l'établissement, pas à GSG ») l'a révélé.
--
-- Règle rétablie : ces actions appartiennent à l'école — sa Direction, ou un
-- poste de l'école qui porte le droit (délégation REG-26 conservée), jamais
-- GSG. `a_permission` lui-même ne change pas (ses autres usages gardent
-- l'accès de l'Administrateur GSG).
-- ============================================================================

create or replace function public.a_permission_ecole(p_etablissement uuid, p_code text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.est_direction(p_etablissement), false)
      or exists (
        select 1 from public.mes_permissions(p_etablissement) c where c = p_code
      );
$$;
grant execute on function public.a_permission_ecole(uuid, text) to authenticated;

comment on function public.a_permission_ecole(uuid, text) is
  'Vrai si l''appelant agit pour l''école : sa Direction, ou un poste de l''école qui porte le code. Jamais l''Administrateur GSG.';

-- Réécriture des douze fonctions déléguées par REG-26 (idempotente).
do $$
declare
  v_nom text;
  v_proc record;
  v_def text;
begin
  foreach v_nom in array array[
    'publier_annonce', 'annonces_etablissement', 'portees_annonce', 'masquer_annonce',
    'masquer_message_liaison', 'proclamer_classe', 'definir_mention_finale',
    'enregistrer_identifiants_orange_money', 'initier_achat_credits_sms',
    'decider_agrement_vendeur_etablissement', 'personnes_debloquables', 'debloquer_code_membre'
  ] loop
    for v_proc in
      select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = v_nom
    loop
      v_def := pg_get_functiondef(v_proc.oid);
      if position('public.a_permission(' in v_def) > 0 then
        execute replace(v_def, 'public.a_permission(', 'public.a_permission_ecole(');
      end if;
    end loop;
  end loop;
end;
$$;
