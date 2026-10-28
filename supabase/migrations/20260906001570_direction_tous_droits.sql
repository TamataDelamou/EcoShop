-- ============================================================================
-- EcoShop — REG-23 : la Direction détient toutes les permissions de son école
-- (retour du porteur de projet, 2026-10-28 : « je n'ai pas vu où créer une
-- année scolaire, où créer une classe »)
--
-- Constat : les modèles de poste « Fondateur » et « Directeur » portent la
-- mention « Tous les droits », mais aucune permission (`codes = '{}'`) ; et
-- `a_permission` ne regarde que le poste. Les politiques d'écriture des
-- années scolaires, périodes, classes, affectations, salles et emplois du
-- temps ne reconnaissaient donc pas la Direction : même avec un écran, la
-- base aurait refusé la création d'une année ou d'une classe.
--
-- Désormais `a_permission` répond vrai pour la Direction de l'école
-- (`est_direction`), comme la lecture par permission (REG-22 C1 : « la
-- direction de l'école : tout, comme avant »). Les postes du personnel ne
-- changent pas. Migration idempotente.
-- ============================================================================

create or replace function public.a_permission(p_etablissement uuid, p_code text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.est_admin_gsg()
      or coalesce(public.est_direction(p_etablissement), false)
      or exists (
        select 1 from public.mes_permissions(p_etablissement) c where c = p_code
      );
$$;
grant execute on function public.a_permission(uuid, text) to authenticated;

comment on function public.a_permission(uuid, text) is
  'Vrai si l''appelant détient la permission dans l''établissement : Administrateur GSG, Direction de l''école (tous les droits), ou poste qui porte le code.';
