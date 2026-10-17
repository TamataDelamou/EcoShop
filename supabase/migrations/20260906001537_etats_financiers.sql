-- ============================================================================
-- EcoShop — REG-03, lot C4 : états financiers, produits constatés d'avance,
-- signaux d'aide étendus aux pièces
-- (proposition validée le 2026-10-17 : docs/propositions/REG-03_COMPTABILITE.md)
--
-- 1. `etat_financier(établissement, exercice)` : bilan (actif / passif) et
--    compte de résultat, colonne N et N-1, contrôle d'équilibre, comptes non
--    classés signalés, et tableau de trésorerie (encaissements /
--    décaissements, utile au Système minimal de trésorerie).
--      • SYSCOHADA (SMT et normal) : rubriques et références officielles
--        (AD… BZ, CA… DZ, TA… XI) relevées sur des liasses publiées ;
--      • SYCEBNL : présentation PROVISOIRE (fonds propres, fonds affectés,
--        générosité…), à valider par l'expert-comptable ;
--      • simplifié : bilan et compte de résultat par nature de compte.
--    Les rubriques sont des DONNÉES (`rubriques_etats_financiers`) : un
--    ajustement demandé par l'expert-comptable ne demande pas de code.
-- 2. Produits constatés d'avance (compte 477) : l'année scolaire chevauche
--    l'exercice civil ; à la clôture, la part des frais de scolarité, de
--    cantine et de transport qui couvre des mois de l'exercice suivant est
--    sortie du résultat (pièce validée au 31/12), puis réintégrée au premier
--    jour de l'exercice suivant (extourne). Prorata au nombre de jours de
--    l'année scolaire de l'inscription. Les frais d'inscription restent
--    acquis à l'encaissement.
-- 3. Prévision de trésorerie, tendances et anomalies lisent désormais aussi
--    les pièces (elles ne voyaient que les écritures M14).
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Rubriques des états financiers (données)
-- ---------------------------------------------------------------------------
create table if not exists public.rubriques_etats_financiers (
  plan text not null check (plan in ('syscohada', 'sycebnl', 'simplifie')),
  etat text not null check (etat in ('actif', 'passif', 'resultat')),
  reference text not null,
  libelle text not null,
  ordre smallint not null,
  -- brut_net : immobilisations (brut, amortissements 28/29, net)
  -- debiteur / crediteur : comptes pris à leur solde débiteur / créditeur
  -- signe_credit : solde créditeur positif, débiteur négatif (capitaux)
  -- produit / charge : compte de résultat
  -- resultat : résultat de l'exercice (référence du compte de résultat)
  -- total : somme signée de références précédentes
  mode text not null check (mode in ('brut_net', 'debiteur', 'crediteur', 'signe_credit', 'produit', 'charge', 'resultat', 'total')),
  prefixes text[] not null default '{}',
  exclusions text[] not null default '{}',
  types text[] not null default '{}',
  formule text[] not null default '{}',
  provisoire boolean not null default false,
  primary key (plan, etat, reference)
);

alter table public.rubriques_etats_financiers enable row level security;
drop policy if exists rubriques_lecture on public.rubriques_etats_financiers;
create policy rubriques_lecture on public.rubriques_etats_financiers
  for select using (auth.role() in ('authenticated', 'service_role'));
revoke insert, update, delete on public.rubriques_etats_financiers from public, anon, authenticated;
grant select on public.rubriques_etats_financiers to authenticated;

delete from public.rubriques_etats_financiers;

-- 1.1 SYSCOHADA révisé — bilan actif
insert into public.rubriques_etats_financiers (plan, etat, reference, libelle, ordre, mode, prefixes, exclusions, formule) values
  ('syscohada', 'actif', 'AD', 'Immobilisations incorporelles', 10, 'brut_net', '{21}', '{}', '{}'),
  ('syscohada', 'actif', 'AJ', 'Terrains', 20, 'brut_net', '{22}', '{}', '{}'),
  ('syscohada', 'actif', 'AK', 'Bâtiments', 21, 'brut_net', '{231,232,233,237}', '{}', '{}'),
  ('syscohada', 'actif', 'AL', 'Aménagements, agencements et installations', 22, 'brut_net', '{234,235,238}', '{}', '{}'),
  ('syscohada', 'actif', 'AM', 'Matériel, mobilier et actifs biologiques', 23, 'brut_net', '{24}', '{245}', '{}'),
  ('syscohada', 'actif', 'AN', 'Matériel de transport', 24, 'brut_net', '{245}', '{}', '{}'),
  ('syscohada', 'actif', 'AI', 'IMMOBILISATIONS CORPORELLES', 25, 'total', '{}', '{}', '{AJ,AK,AL,AM,AN}'),
  ('syscohada', 'actif', 'AP', 'Avances et acomptes versés sur immobilisations', 30, 'brut_net', '{25}', '{}', '{}'),
  ('syscohada', 'actif', 'AQ', 'Immobilisations financières', 31, 'brut_net', '{26,27}', '{}', '{}'),
  ('syscohada', 'actif', 'AZ', 'TOTAL ACTIF IMMOBILISÉ', 39, 'total', '{}', '{}', '{AD,AI,AP,AQ}'),
  ('syscohada', 'actif', 'BA', 'Actif circulant HAO', 40, 'debiteur', '{485,488}', '{}', '{}'),
  ('syscohada', 'actif', 'BB', 'Stocks et encours', 41, 'debiteur', '{3}', '{}', '{}'),
  ('syscohada', 'actif', 'BH', 'Fournisseurs, avances versées', 42, 'debiteur', '{40}', '{}', '{}'),
  ('syscohada', 'actif', 'BI', 'Clients', 43, 'debiteur', '{41}', '{}', '{}'),
  ('syscohada', 'actif', 'BJ', 'Autres créances', 44, 'debiteur', '{42,43,44,45,46,47,48}', '{485,488}', '{}'),
  ('syscohada', 'actif', 'BK', 'TOTAL ACTIF CIRCULANT', 49, 'total', '{}', '{}', '{BA,BB,BH,BI,BJ}'),
  ('syscohada', 'actif', 'BQ', 'Titres de placement', 50, 'debiteur', '{50}', '{}', '{}'),
  ('syscohada', 'actif', 'BR', 'Valeurs à encaisser', 51, 'debiteur', '{51}', '{}', '{}'),
  ('syscohada', 'actif', 'BS', 'Banques, chèques postaux, caisse et assimilés', 52, 'debiteur', '{52,53,54,55,56,57,58}', '{}', '{}'),
  ('syscohada', 'actif', 'BT', 'TOTAL TRÉSORERIE-ACTIF', 59, 'total', '{}', '{}', '{BQ,BR,BS}'),
  ('syscohada', 'actif', 'BZ', 'TOTAL GÉNÉRAL', 99, 'total', '{}', '{}', '{AZ,BK,BT}');

-- 1.2 SYSCOHADA révisé — bilan passif
insert into public.rubriques_etats_financiers (plan, etat, reference, libelle, ordre, mode, prefixes, exclusions, formule) values
  ('syscohada', 'passif', 'CA', 'Capital', 10, 'signe_credit', '{101,102,103,104}', '{}', '{}'),
  ('syscohada', 'passif', 'CD', 'Primes liées au capital social', 11, 'signe_credit', '{105}', '{}', '{}'),
  ('syscohada', 'passif', 'CE', 'Écarts de réévaluation', 12, 'signe_credit', '{106}', '{}', '{}'),
  ('syscohada', 'passif', 'CF', 'Réserves indisponibles', 13, 'signe_credit', '{111,112,113}', '{}', '{}'),
  ('syscohada', 'passif', 'CG', 'Réserves libres', 14, 'signe_credit', '{118}', '{}', '{}'),
  ('syscohada', 'passif', 'CH', 'Report à nouveau (+ ou −)', 15, 'signe_credit', '{12,13}', '{}', '{}'),
  ('syscohada', 'passif', 'CJ', 'Résultat net de l''exercice (bénéfice + ou perte −)', 16, 'resultat', '{}', '{}', '{XI}'),
  ('syscohada', 'passif', 'CL', 'Subventions d''investissement', 17, 'signe_credit', '{14}', '{}', '{}'),
  ('syscohada', 'passif', 'CM', 'Provisions réglementées', 18, 'signe_credit', '{15}', '{}', '{}'),
  ('syscohada', 'passif', 'CP', 'TOTAL CAPITAUX PROPRES ET RESSOURCES ASSIMILÉES', 19, 'total', '{}', '{}', '{CA,CD,CE,CF,CG,CH,CJ,CL,CM}'),
  ('syscohada', 'passif', 'DA', 'Emprunts et dettes financières diverses', 20, 'signe_credit', '{16,18}', '{}', '{}'),
  ('syscohada', 'passif', 'DB', 'Dettes de location acquisition', 21, 'signe_credit', '{17}', '{}', '{}'),
  ('syscohada', 'passif', 'DC', 'Provisions pour risques et charges', 22, 'signe_credit', '{19}', '{}', '{}'),
  ('syscohada', 'passif', 'DD', 'TOTAL DETTES FINANCIÈRES ET RESSOURCES ASSIMILÉES', 23, 'total', '{}', '{}', '{DA,DB,DC}'),
  ('syscohada', 'passif', 'DF', 'TOTAL RESSOURCES STABLES', 29, 'total', '{}', '{}', '{CP,DD}'),
  ('syscohada', 'passif', 'DH', 'Dettes circulantes HAO', 30, 'crediteur', '{48}', '{}', '{}'),
  ('syscohada', 'passif', 'DI', 'Clients, avances reçues', 31, 'crediteur', '{419}', '{}', '{}'),
  ('syscohada', 'passif', 'DJ', 'Fournisseurs d''exploitation', 32, 'crediteur', '{40}', '{}', '{}'),
  ('syscohada', 'passif', 'DK', 'Dettes fiscales et sociales', 33, 'crediteur', '{42,43,44}', '{}', '{}'),
  ('syscohada', 'passif', 'DM', 'Autres dettes (y compris produits constatés d''avance)', 34, 'crediteur', '{41,45,46,47}', '{419}', '{}'),
  ('syscohada', 'passif', 'DN', 'Provisions pour risques à court terme', 35, 'crediteur', '{499}', '{}', '{}'),
  ('syscohada', 'passif', 'DP', 'TOTAL PASSIF CIRCULANT', 39, 'total', '{}', '{}', '{DH,DI,DJ,DK,DM,DN}'),
  ('syscohada', 'passif', 'DQ', 'Banques, crédits d''escompte', 40, 'crediteur', '{564,565}', '{}', '{}'),
  ('syscohada', 'passif', 'DR', 'Banques, établissements financiers et crédits de trésorerie', 41, 'crediteur', '{50,51,52,53,54,55,56,57,58}', '{564,565}', '{}'),
  ('syscohada', 'passif', 'DT', 'TOTAL TRÉSORERIE-PASSIF', 49, 'total', '{}', '{}', '{DQ,DR}'),
  ('syscohada', 'passif', 'DZ', 'TOTAL GÉNÉRAL', 99, 'total', '{}', '{}', '{DF,DP,DT}');

-- 1.3 SYSCOHADA révisé — compte de résultat
insert into public.rubriques_etats_financiers (plan, etat, reference, libelle, ordre, mode, prefixes, exclusions, formule) values
  ('syscohada', 'resultat', 'TA', 'Ventes de marchandises', 10, 'produit', '{701}', '{}', '{}'),
  ('syscohada', 'resultat', 'RA', 'Achats de marchandises', 11, 'charge', '{601}', '{}', '{}'),
  ('syscohada', 'resultat', 'RB', 'Variation de stocks de marchandises', 12, 'charge', '{6031}', '{}', '{}'),
  ('syscohada', 'resultat', 'XA', 'MARGE COMMERCIALE', 13, 'total', '{}', '{}', '{TA,-RA,-RB}'),
  ('syscohada', 'resultat', 'TB', 'Ventes de produits fabriqués', 20, 'produit', '{702,703,704}', '{}', '{}'),
  ('syscohada', 'resultat', 'TC', 'Travaux, services vendus', 21, 'produit', '{705,706}', '{}', '{}'),
  ('syscohada', 'resultat', 'TD', 'Produits accessoires', 22, 'produit', '{707}', '{}', '{}'),
  ('syscohada', 'resultat', 'XB', 'CHIFFRE D''AFFAIRES', 23, 'total', '{}', '{}', '{TA,TB,TC,TD}'),
  ('syscohada', 'resultat', 'TE', 'Production stockée (ou déstockage)', 30, 'produit', '{73}', '{}', '{}'),
  ('syscohada', 'resultat', 'TF', 'Production immobilisée', 31, 'produit', '{72}', '{}', '{}'),
  ('syscohada', 'resultat', 'TG', 'Subventions d''exploitation', 32, 'produit', '{71}', '{}', '{}'),
  ('syscohada', 'resultat', 'TH', 'Autres produits', 33, 'produit', '{75,708}', '{}', '{}'),
  ('syscohada', 'resultat', 'TI', 'Transferts de charges d''exploitation', 34, 'produit', '{781}', '{}', '{}'),
  ('syscohada', 'resultat', 'RC', 'Achats de matières premières et fournitures liées', 35, 'charge', '{602}', '{}', '{}'),
  ('syscohada', 'resultat', 'RD', 'Variation de stocks de matières premières et fournitures liées', 36, 'charge', '{6032}', '{}', '{}'),
  ('syscohada', 'resultat', 'RE', 'Autres achats', 37, 'charge', '{604,605,608}', '{}', '{}'),
  ('syscohada', 'resultat', 'RF', 'Variation de stocks d''autres approvisionnements', 38, 'charge', '{6033}', '{}', '{}'),
  ('syscohada', 'resultat', 'RG', 'Transports', 39, 'charge', '{61}', '{}', '{}'),
  ('syscohada', 'resultat', 'RH', 'Services extérieurs', 40, 'charge', '{62,63}', '{}', '{}'),
  ('syscohada', 'resultat', 'RI', 'Impôts et taxes', 41, 'charge', '{64}', '{}', '{}'),
  ('syscohada', 'resultat', 'RJ', 'Autres charges', 42, 'charge', '{65}', '{}', '{}'),
  ('syscohada', 'resultat', 'XC', 'VALEUR AJOUTÉE', 43, 'total', '{}', '{}', '{XB,TE,TF,TG,TH,TI,-RA,-RB,-RC,-RD,-RE,-RF,-RG,-RH,-RI,-RJ}'),
  ('syscohada', 'resultat', 'RK', 'Charges de personnel', 50, 'charge', '{66}', '{}', '{}'),
  ('syscohada', 'resultat', 'XD', 'EXCÉDENT BRUT D''EXPLOITATION', 51, 'total', '{}', '{}', '{XC,-RK}'),
  ('syscohada', 'resultat', 'TJ', 'Reprises d''amortissements, provisions et dépréciations', 52, 'produit', '{791,798,799}', '{}', '{}'),
  ('syscohada', 'resultat', 'RL', 'Dotations aux amortissements, aux provisions et dépréciations', 53, 'charge', '{68,691}', '{}', '{}'),
  ('syscohada', 'resultat', 'XE', 'RÉSULTAT D''EXPLOITATION', 54, 'total', '{}', '{}', '{XD,TJ,-RL}'),
  ('syscohada', 'resultat', 'TK', 'Revenus financiers et assimilés', 60, 'produit', '{77}', '{}', '{}'),
  ('syscohada', 'resultat', 'TL', 'Reprises de provisions et dépréciations financières', 61, 'produit', '{797}', '{}', '{}'),
  ('syscohada', 'resultat', 'TM', 'Transferts de charges financières', 62, 'produit', '{787}', '{}', '{}'),
  ('syscohada', 'resultat', 'RM', 'Frais financiers et charges assimilées', 63, 'charge', '{67}', '{}', '{}'),
  ('syscohada', 'resultat', 'RN', 'Dotations aux provisions et aux dépréciations financières', 64, 'charge', '{697}', '{}', '{}'),
  ('syscohada', 'resultat', 'XF', 'RÉSULTAT FINANCIER', 65, 'total', '{}', '{}', '{TK,TL,TM,-RM,-RN}'),
  ('syscohada', 'resultat', 'XG', 'RÉSULTAT DES ACTIVITÉS ORDINAIRES', 66, 'total', '{}', '{}', '{XE,XF}'),
  ('syscohada', 'resultat', 'TN', 'Produits des cessions d''immobilisations', 70, 'produit', '{82}', '{}', '{}'),
  ('syscohada', 'resultat', 'TO', 'Autres produits HAO', 71, 'produit', '{84,86,88}', '{}', '{}'),
  ('syscohada', 'resultat', 'RO', 'Valeurs comptables des cessions d''immobilisations', 72, 'charge', '{81}', '{}', '{}'),
  ('syscohada', 'resultat', 'RP', 'Autres charges HAO', 73, 'charge', '{83,85}', '{}', '{}'),
  ('syscohada', 'resultat', 'XH', 'RÉSULTAT HORS ACTIVITÉS ORDINAIRES', 74, 'total', '{}', '{}', '{TN,TO,-RO,-RP}'),
  ('syscohada', 'resultat', 'RQ', 'Participation des travailleurs', 80, 'charge', '{87}', '{}', '{}'),
  ('syscohada', 'resultat', 'RS', 'Impôts sur le résultat', 81, 'charge', '{89}', '{}', '{}'),
  ('syscohada', 'resultat', 'XI', 'RÉSULTAT NET', 99, 'total', '{}', '{}', '{XG,XH,-RQ,-RS}');

-- 1.4 SYCEBNL — présentation PROVISOIRE (à valider par l'expert-comptable)
insert into public.rubriques_etats_financiers (plan, etat, reference, libelle, ordre, mode, prefixes, exclusions, formule, provisoire) values
  ('sycebnl', 'actif', 'A1', 'Immobilisations incorporelles', 10, 'brut_net', '{21}', '{}', '{}', true),
  ('sycebnl', 'actif', 'A2', 'Immobilisations corporelles', 11, 'brut_net', '{22,23,24}', '{}', '{}', true),
  ('sycebnl', 'actif', 'A3', 'Immobilisations financières et avances', 12, 'brut_net', '{25,26,27}', '{}', '{}', true),
  ('sycebnl', 'actif', 'AZ', 'TOTAL ACTIF IMMOBILISÉ', 19, 'total', '{}', '{}', '{A1,A2,A3}', true),
  ('sycebnl', 'actif', 'B1', 'Stocks', 20, 'debiteur', '{3}', '{}', '{}', true),
  ('sycebnl', 'actif', 'B2', 'Adhérents et usagers (familles)', 21, 'debiteur', '{41}', '{419}', '{}', true),
  ('sycebnl', 'actif', 'B3', 'Bailleurs et subventions à recevoir', 22, 'debiteur', '{46}', '{}', '{}', true),
  ('sycebnl', 'actif', 'B4', 'Autres créances', 23, 'debiteur', '{40,42,43,44,45,47,48}', '{}', '{}', true),
  ('sycebnl', 'actif', 'BK', 'TOTAL ACTIF CIRCULANT', 29, 'total', '{}', '{}', '{B1,B2,B3,B4}', true),
  ('sycebnl', 'actif', 'BS', 'Trésorerie-actif (banques, Orange Money, caisse)', 30, 'debiteur', '{5}', '{}', '{}', true),
  ('sycebnl', 'actif', 'BZ', 'TOTAL GÉNÉRAL', 99, 'total', '{}', '{}', '{AZ,BK,BS}', true),
  ('sycebnl', 'passif', 'C1', 'Dotations', 10, 'signe_credit', '{10}', '{}', '{}', true),
  ('sycebnl', 'passif', 'C2', 'Réserves', 11, 'signe_credit', '{11}', '{}', '{}', true),
  ('sycebnl', 'passif', 'C3', 'Report à nouveau (+ ou −)', 12, 'signe_credit', '{12,13}', '{}', '{}', true),
  ('sycebnl', 'passif', 'C4', 'Résultat de l''exercice (excédent + ou déficit −)', 13, 'resultat', '{}', '{}', '{XI}', true),
  ('sycebnl', 'passif', 'C5', 'Subventions d''investissement', 14, 'signe_credit', '{14}', '{}', '{}', true),
  ('sycebnl', 'passif', 'C6', 'Fonds affectés et fonds reportés', 15, 'signe_credit', '{15,16,17}', '{}', '{}', true),
  ('sycebnl', 'passif', 'CP', 'TOTAL FONDS PROPRES ET RESSOURCES ASSIMILÉES', 19, 'total', '{}', '{}', '{C1,C2,C3,C4,C5,C6}', true),
  ('sycebnl', 'passif', 'D1', 'Emprunts, dettes financières et provisions', 20, 'signe_credit', '{18,19}', '{}', '{}', true),
  ('sycebnl', 'passif', 'D2', 'Fournisseurs', 30, 'crediteur', '{40}', '{}', '{}', true),
  ('sycebnl', 'passif', 'D3', 'Familles et usagers, avances reçues', 31, 'crediteur', '{41}', '{}', '{}', true),
  ('sycebnl', 'passif', 'D4', 'Dettes fiscales et sociales', 32, 'crediteur', '{42,43,44}', '{}', '{}', true),
  ('sycebnl', 'passif', 'D5', 'Autres dettes (y compris produits constatés d''avance)', 33, 'crediteur', '{45,46,47,48}', '{}', '{}', true),
  ('sycebnl', 'passif', 'DP', 'TOTAL PASSIF CIRCULANT', 39, 'total', '{}', '{}', '{D2,D3,D4,D5}', true),
  ('sycebnl', 'passif', 'DT', 'Trésorerie-passif', 40, 'crediteur', '{5}', '{}', '{}', true),
  ('sycebnl', 'passif', 'DZ', 'TOTAL GÉNÉRAL', 99, 'total', '{}', '{}', '{CP,D1,DP,DT}', true),
  ('sycebnl', 'resultat', 'P1', 'Cotisations des adhérents', 10, 'produit', '{701}', '{}', '{}', true),
  ('sycebnl', 'resultat', 'P2', 'Revenus liés à la générosité (dons, legs, deniers du culte…)', 11, 'produit', '{704}', '{}', '{}', true),
  ('sycebnl', 'resultat', 'P3', 'Ventes et prestations (frais scolaires)', 12, 'produit', '{705}', '{}', '{}', true),
  ('sycebnl', 'resultat', 'P4', 'Autres revenus des activités', 13, 'produit', '{702,703,706,707,708}', '{}', '{}', true),
  ('sycebnl', 'resultat', 'P5', 'Subventions d''exploitation', 14, 'produit', '{71}', '{}', '{}', true),
  ('sycebnl', 'resultat', 'P6', 'Autres produits et reprises', 15, 'produit', '{72,73,75,78,79}', '{}', '{}', true),
  ('sycebnl', 'resultat', 'XP', 'TOTAL DES PRODUITS D''EXPLOITATION', 19, 'total', '{}', '{}', '{P1,P2,P3,P4,P5,P6}', true),
  ('sycebnl', 'resultat', 'Q1', 'Achats', 20, 'charge', '{60}', '{}', '{}', true),
  ('sycebnl', 'resultat', 'Q2', 'Transports et services extérieurs', 21, 'charge', '{61,62,63}', '{}', '{}', true),
  ('sycebnl', 'resultat', 'Q3', 'Impôts et taxes', 22, 'charge', '{64}', '{}', '{}', true),
  ('sycebnl', 'resultat', 'Q4', 'Autres charges (y compris subventions versées)', 23, 'charge', '{65}', '{}', '{}', true),
  ('sycebnl', 'resultat', 'Q5', 'Charges de personnel', 24, 'charge', '{66}', '{}', '{}', true),
  ('sycebnl', 'resultat', 'Q6', 'Dotations aux amortissements, provisions et fonds affectés', 25, 'charge', '{68,69}', '{}', '{}', true),
  ('sycebnl', 'resultat', 'XQ', 'TOTAL DES CHARGES D''EXPLOITATION', 29, 'total', '{}', '{}', '{Q1,Q2,Q3,Q4,Q5,Q6}', true),
  ('sycebnl', 'resultat', 'XE', 'RÉSULTAT D''EXPLOITATION', 30, 'total', '{}', '{}', '{XP,-XQ}', true),
  ('sycebnl', 'resultat', 'F1', 'Revenus financiers', 40, 'produit', '{77}', '{}', '{}', true),
  ('sycebnl', 'resultat', 'F2', 'Frais financiers', 41, 'charge', '{67}', '{}', '{}', true),
  ('sycebnl', 'resultat', 'XF', 'RÉSULTAT FINANCIER', 42, 'total', '{}', '{}', '{F1,-F2}', true),
  ('sycebnl', 'resultat', 'H1', 'Produits hors activités ordinaires', 50, 'produit', '{82,84,86,88}', '{}', '{}', true),
  ('sycebnl', 'resultat', 'H2', 'Charges hors activités ordinaires', 51, 'charge', '{81,83,85,87,89}', '{}', '{}', true),
  ('sycebnl', 'resultat', 'XH', 'RÉSULTAT HORS ACTIVITÉS ORDINAIRES', 52, 'total', '{}', '{}', '{H1,-H2}', true),
  ('sycebnl', 'resultat', 'XI', 'EXCÉDENT OU DÉFICIT DE L''EXERCICE', 99, 'total', '{}', '{}', '{XE,XF,XH}', true);

-- 1.5 Comptabilité simplifiée — par nature de compte
insert into public.rubriques_etats_financiers (plan, etat, reference, libelle, ordre, mode, types, formule) values
  ('simplifie', 'actif', 'S1', 'Immobilisations et autres actifs', 10, 'debiteur', '{actif,autre,passif}', '{}'),
  ('simplifie', 'actif', 'S2', 'Trésorerie (banques, Orange Money, caisse)', 20, 'debiteur', '{banque,caisse}', '{}'),
  ('simplifie', 'actif', 'BZ', 'TOTAL ACTIF', 99, 'total', '{}', '{S1,S2}'),
  ('simplifie', 'passif', 'S3', 'Capitaux et report', 10, 'signe_credit', '{capitaux}', '{}'),
  ('simplifie', 'passif', 'S4', 'Résultat de l''exercice', 11, 'resultat', '{}', '{XI}'),
  ('simplifie', 'passif', 'S5', 'Dettes et autres passifs', 20, 'crediteur', '{passif,autre,actif}', '{}'),
  ('simplifie', 'passif', 'S6', 'Trésorerie-passif (découverts)', 30, 'crediteur', '{banque,caisse}', '{}'),
  ('simplifie', 'passif', 'DZ', 'TOTAL PASSIF', 99, 'total', '{}', '{S3,S4,S5,S6}'),
  ('simplifie', 'resultat', 'S7', 'Produits', 10, 'produit', '{produit}', '{}'),
  ('simplifie', 'resultat', 'S8', 'Charges', 20, 'charge', '{charge}', '{}'),
  ('simplifie', 'resultat', 'XI', 'RÉSULTAT', 99, 'total', '{}', '{S7,-S8}');

-- ---------------------------------------------------------------------------
-- 2. Calcul des états
-- ---------------------------------------------------------------------------
create or replace function public.code_correspond(p_code text, p_prefixes text[], p_exclusions text[])
returns boolean
language sql
immutable
as $$
  select exists (select 1 from unnest(p_prefixes) x where left(p_code, char_length(x)) = x)
     and not exists (select 1 from unnest(p_exclusions) x where left(p_code, char_length(x)) = x);
$$;

-- Calcule les trois états pour un intervalle ; renvoie {ref: montant} et le
-- détail des lignes (brut / amortissements pour l'actif immobilisé).
create or replace function public.calculer_etats(p_etablissement uuid, p_plan text, p_debut date, p_fin date)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  r public.rubriques_etats_financiers;
  v_valeurs jsonb := '{}'::jsonb;
  v_lignes jsonb := '[]'::jsonb;
  v_montant numeric;
  v_brut numeric;
  v_amort numeric;
  v_ref text;
  v_classes uuid[] := '{}';
  v_non_classes jsonb;
  v_etat text;
begin
  create temp table if not exists _soldes (compte_id uuid, code text, type text, solde numeric) on commit drop;
  truncate _soldes;
  insert into _soldes
  select c.id, c.code, c.type, sum(m.debit - m.credit)
    from public.mouvements_comptables(p_etablissement, p_debut, p_fin) m
    join public.plans_comptables c on c.id = m.compte_id
   group by c.id, c.code, c.type
  having sum(m.debit - m.credit) <> 0;

  foreach v_etat in array array['resultat', 'actif', 'passif'] loop
    for r in select * from public.rubriques_etats_financiers
              where plan = p_plan and etat = v_etat order by ordre loop
      v_brut := null;
      v_amort := null;
      if r.mode = 'total' or r.mode = 'resultat' then
        v_montant := 0;
        foreach v_ref in array r.formule loop
          if left(v_ref, 1) = '-' then
            v_montant := v_montant - coalesce((v_valeurs->>substr(v_ref, 2))::numeric, 0);
          else
            v_montant := v_montant + coalesce((v_valeurs->>v_ref)::numeric, 0);
          end if;
        end loop;
      elsif r.mode = 'brut_net' then
        select coalesce(sum(s.solde), 0), coalesce(array_agg(s.compte_id), '{}') into v_brut, v_classes
          from _soldes s
         where left(s.code, 2) not in ('28', '29')
           and public.code_correspond(s.code, r.prefixes, r.exclusions);
        -- 28x / 29x : amortissements et dépréciations du compte « 2x ».
        select coalesce(-sum(s.solde), 0) into v_amort
          from _soldes s
         where left(s.code, 2) in ('28', '29')
           and public.code_correspond('2' || substr(s.code, 3), r.prefixes, r.exclusions);
        v_montant := v_brut - v_amort;
      else
        select coalesce(sum(case r.mode
                  when 'debiteur' then greatest(s.solde, 0)
                  when 'crediteur' then greatest(-s.solde, 0)
                  when 'signe_credit' then -s.solde
                  when 'produit' then -s.solde
                  when 'charge' then s.solde end), 0)
          into v_montant
          from _soldes s
         where (p_plan = 'simplifie' and s.type = any (r.types))
            or (p_plan <> 'simplifie' and left(s.code, 2) not in ('28', '29')
                and public.code_correspond(s.code, r.prefixes, r.exclusions));
      end if;

      v_valeurs := v_valeurs || jsonb_build_object(r.reference, v_montant);
      v_lignes := v_lignes || jsonb_build_array(jsonb_build_object(
        'etat', r.etat, 'reference', r.reference, 'libelle', r.libelle,
        'total', r.mode = 'total', 'montant', v_montant, 'brut', v_brut, 'amortissements', v_amort));
    end loop;
  end loop;

  -- Comptes de bilan qu'aucune rubrique ne reprend (à signaler, jamais ignorés en silence).
  if p_plan <> 'simplifie' then
    select coalesce(jsonb_agg(jsonb_build_object('code', s.code, 'solde', s.solde) order by s.code), '[]'::jsonb)
      into v_non_classes
      from _soldes s
     where not exists (
       select 1 from public.rubriques_etats_financiers rb
        where rb.plan = p_plan and rb.mode in ('brut_net', 'debiteur', 'crediteur', 'signe_credit', 'produit', 'charge')
          and (public.code_correspond(s.code, rb.prefixes, rb.exclusions)
               or (left(s.code, 2) in ('28', '29') and rb.mode = 'brut_net'
                   and public.code_correspond('2' || substr(s.code, 3), rb.prefixes, rb.exclusions))));
  else
    v_non_classes := '[]'::jsonb;
  end if;

  return jsonb_build_object('valeurs', v_valeurs, 'lignes', v_lignes, 'non_classes', v_non_classes);
end;
$$;

create or replace function public.etat_financier(p_etablissement uuid, p_exercice_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  x public.exercices_comptables;
  v_prec public.exercices_comptables;
  v_ref text := public.referentiel_comptable_de(p_etablissement);
  v_plan text := coalesce(public.plan_du_referentiel(public.referentiel_comptable_de(p_etablissement)), 'simplifie');
  v_fin date;
  v_n jsonb;
  v_n1 jsonb;
  v_lignes jsonb := '[]'::jsonb;
  l jsonb;
  v_tresorerie jsonb;
begin
  if not coalesce(public.est_comptable(p_etablissement), false) then
    raise exception 'COMPTABLE_REQUIS' using errcode = '42501';
  end if;
  select * into x from public.exercices_comptables where id = p_exercice_id and etablissement_id = p_etablissement;
  if x.id is null then
    raise exception 'EXERCICE_INTROUVABLE' using errcode = '22023';
  end if;
  -- Toutes les pièces de l'exercice (y compris les régularisations datées du
  -- 31/12) ; un exercice ouvert donne une situation PROVISOIRE.
  v_fin := x.date_fin;

  v_n := public.calculer_etats(p_etablissement, v_plan, x.date_debut, v_fin);
  select * into v_prec from public.exercices_comptables
   where etablissement_id = p_etablissement and date_fin = x.date_debut - 1;
  if v_prec.id is not null then
    v_n1 := public.calculer_etats(p_etablissement, v_plan, v_prec.date_debut, v_prec.date_fin);
  end if;

  for l in select * from jsonb_array_elements(v_n->'lignes') loop
    v_lignes := v_lignes || jsonb_build_array(l || jsonb_build_object(
      'montant_n1', case when v_n1 is null then null else v_n1->'valeurs'->(l->>'reference') end));
  end loop;

  -- Tableau de trésorerie : comptes de trésorerie (classe 5, ou banque/caisse).
  select jsonb_build_object(
           'solde_debut', coalesce(sum(m.debit - m.credit) filter (where p.origine = 'a_nouveaux'), 0),
           'encaissements', coalesce(sum(greatest(m.debit, 0) + greatest(-m.credit, 0)) filter (where p.origine is distinct from 'a_nouveaux'), 0),
           'decaissements', coalesce(sum(greatest(m.credit, 0) + greatest(-m.debit, 0)) filter (where p.origine is distinct from 'a_nouveaux'), 0),
           'solde_fin', coalesce(sum(m.debit - m.credit), 0))
    into v_tresorerie
    from public.mouvements_comptables(p_etablissement, x.date_debut, v_fin) m
    join public.plans_comptables c on c.id = m.compte_id
    left join public.pieces_comptables p on p.reference = m.reference and p.etablissement_id = p_etablissement
   where c.type in ('banque', 'caisse') or (v_plan <> 'simplifie' and left(c.code, 1) = '5');

  return jsonb_build_object(
    'referentiel', v_ref,
    'plan', v_plan,
    'provisoire', x.statut = 'ouvert'
                  or exists (select 1 from public.rubriques_etats_financiers where plan = v_plan and provisoire),
    'exercice', jsonb_build_object('id', x.id, 'libelle', x.libelle, 'date_debut', x.date_debut,
                                   'date_fin', x.date_fin, 'cloture', x.statut = 'cloture',
                                   'situation_au', case when x.statut = 'ouvert' then least(current_date, x.date_fin) else x.date_fin end),
    'exercice_precedent', case when v_prec.id is null then null else v_prec.libelle end,
    'lignes', v_lignes,
    'total_actif', v_n->'valeurs'->'BZ',
    'total_passif', v_n->'valeurs'->'DZ',
    'equilibre', abs(coalesce((v_n->'valeurs'->>'BZ')::numeric, 0) - coalesce((v_n->'valeurs'->>'DZ')::numeric, 0)) < 0.01,
    'resultat', v_n->'valeurs'->'XI',
    'non_classes', v_n->'non_classes',
    'tresorerie', v_tresorerie
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Produits constatés d'avance (année scolaire ≠ exercice civil)
-- ---------------------------------------------------------------------------
alter table public.pieces_comptables drop constraint if exists pieces_comptables_source_type_check;
alter table public.pieces_comptables add constraint pieces_comptables_source_type_check
  check (source_type is null or source_type in ('encaissement_scolarite', 'produits_constates_avance', 'extourne_pca'));

insert into public.plans_comptables_reference (plan, code, intitule, type, extension_ecoshop, a_relire) values
  ('syscohada', '476', 'Charges constatées d''avance', 'actif', false, false),
  ('syscohada', '477', 'Produits constatés d''avance', 'passif', false, false),
  ('sycebnl', '477', 'Produits constatés d''avance', 'passif', false, true)
on conflict (plan, code) do update set intitule = excluded.intitule, type = excluded.type;

-- Calcul (sans rien écrire) : part des frais encaissés dans l'exercice qui
-- couvre des jours de l'année scolaire postérieurs à la fin de l'exercice.
create or replace function public.calcul_produits_constates_avance(p_exercice_id uuid)
returns table (compte_id uuid, code text, intitule text, encaisse numeric, montant numeric)
language sql
stable
security definer
set search_path = public
as $$
  with x as (select * from public.exercices_comptables where id = p_exercice_id),
  produits as (
    select p.id as piece_id, l.compte_id, l.credit as montant, a.date_debut, a.date_fin
      from x
      join public.pieces_comptables p on p.exercice_id = x.id and p.statut = 'validee'
       and p.source_type = 'encaissement_scolarite' and p.origine = 'automatique' and p.annulee_par_piece_id is null
      join public.encaissements_scolarite e on e.id = p.source_id and e.type_frais in ('scolarite', 'cantine', 'transport')
      join public.inscriptions i on i.id = e.inscription_id
      join public.annees_scolaires a on a.id = i.annee_scolaire_id
      join public.lignes_pieces_comptables l on l.piece_id = p.id and l.credit > 0
  )
  select c.id, c.code, c.intitule, sum(pr.montant),
         round(sum(pr.montant
               * greatest(0, (pr.date_fin - greatest(pr.date_debut, (select date_fin from x) + 1) + 1))::numeric
               / greatest(1, (pr.date_fin - pr.date_debut + 1))), 0)
    from produits pr
    join public.plans_comptables c on c.id = pr.compte_id
   group by c.id, c.code, c.intitule
  having round(sum(pr.montant
               * greatest(0, (pr.date_fin - greatest(pr.date_debut, (select date_fin from x) + 1) + 1))::numeric
               / greatest(1, (pr.date_fin - pr.date_debut + 1))), 0) > 0
   order by c.code;
$$;

create or replace function public.passer_produits_constates_avance(p_exercice_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  x public.exercices_comptables;
  v_suivant public.exercices_comptables;
  v_plan text;
  v_477 uuid;
  v_journal uuid;
  v_piece uuid;
  v_extourne uuid;
  v_total numeric := 0;
  v_ordre smallint := 0;
  r record;
begin
  select * into x from public.exercices_comptables where id = p_exercice_id for update;
  if x.id is null then
    raise exception 'EXERCICE_INTROUVABLE' using errcode = '22023';
  end if;
  if not coalesce(public.est_comptable_ecriture(x.etablissement_id), false) then
    raise exception 'COMPTABLE_ECRITURE_REQUIS' using errcode = '42501';
  end if;
  if x.statut <> 'ouvert' then
    raise exception 'EXERCICE_DEJA_CLOTURE' using errcode = '55000';
  end if;
  if public.date_comptable_figee(x.etablissement_id, x.date_fin) then
    raise exception 'PERIODE_CLOTUREE' using errcode = '55000';
  end if;
  if exists (select 1 from public.pieces_comptables
              where source_type = 'produits_constates_avance' and source_id = x.id and origine = 'automatique') then
    raise exception 'PCA_DEJA_PASSES' using errcode = '55000';
  end if;

  v_plan := public.plan_du_referentiel(public.referentiel_comptable_de(x.etablissement_id));
  if v_plan is null then
    raise exception 'REFERENTIEL_OHADA_REQUIS' using errcode = '55000';
  end if;

  -- Compte 477 : ajouté au plan s'il manque (plans chargés avant ce lot).
  perform set_config('ecoshop.chargement_plan_reference', 'on', true);
  insert into public.plans_comptables (etablissement_id, code, intitule, type, parent_id, actif, reglementaire)
  values (x.etablissement_id, '477', 'Produits constatés d''avance', 'passif',
          (select id from public.plans_comptables where etablissement_id = x.etablissement_id and code = '47' and deleted_at is null),
          true, true)
  on conflict (etablissement_id, code) do update set deleted_at = null, actif = true
  returning id into v_477;
  perform set_config('ecoshop.chargement_plan_reference', 'off', true);

  insert into public.journaux (etablissement_id, code, intitule, type)
  values (x.etablissement_id, 'OD', 'Opérations diverses', 'operations')
  on conflict (etablissement_id, code) do update set deleted_at = null
  returning id into v_journal;

  insert into public.pieces_comptables
    (etablissement_id, exercice_id, journal_id, date_piece, libelle, origine, cree_par, source_type, source_id)
  values (x.etablissement_id, x.id, v_journal, x.date_fin,
          'Produits constatés d''avance — frais de l''année scolaire couvrant l''exercice suivant',
          'automatique', auth.uid(), 'produits_constates_avance', x.id)
  returning id into v_piece;

  for r in select * from public.calcul_produits_constates_avance(x.id) loop
    insert into public.lignes_pieces_comptables (piece_id, etablissement_id, compte_id, libelle, debit, credit, ordre)
    values (v_piece, x.etablissement_id, r.compte_id, 'Part ' || r.intitule || ' reportée', r.montant, 0, v_ordre);
    v_ordre := v_ordre + 1;
    v_total := v_total + r.montant;
  end loop;

  if v_total = 0 then
    delete from public.pieces_comptables where id = v_piece;
    return jsonb_build_object('montant', 0, 'piece_id', null, 'extourne_id', null);
  end if;

  insert into public.lignes_pieces_comptables (piece_id, etablissement_id, compte_id, libelle, debit, credit, ordre)
  values (v_piece, x.etablissement_id, v_477, 'Produits constatés d''avance', 0, v_total, v_ordre);
  perform public.numeroter_et_valider_piece(v_piece, auth.uid());

  -- Extourne au premier jour de l'exercice suivant (créé au besoin).
  select * into v_suivant from public.exercices_comptables
   where etablissement_id = x.etablissement_id and date_debut = x.date_fin + 1;
  if v_suivant.id is null then
    insert into public.exercices_comptables (etablissement_id, libelle, date_debut, date_fin)
    values (x.etablissement_id, 'Exercice ' || to_char(x.date_fin + 1, 'YYYY'), x.date_fin + 1, (x.date_fin + interval '1 year')::date)
    returning * into v_suivant;
  end if;

  insert into public.pieces_comptables
    (etablissement_id, exercice_id, journal_id, date_piece, libelle, origine, cree_par, source_type, source_id)
  values (x.etablissement_id, v_suivant.id, v_journal, v_suivant.date_debut,
          'Extourne des produits constatés d''avance — ' || x.libelle,
          'automatique', auth.uid(), 'extourne_pca', x.id)
  returning id into v_extourne;
  insert into public.lignes_pieces_comptables (piece_id, etablissement_id, compte_id, libelle, debit, credit, ordre)
  select v_extourne, l.etablissement_id, l.compte_id, l.libelle, l.credit, l.debit, l.ordre
    from public.lignes_pieces_comptables l where l.piece_id = v_piece;
  perform public.numeroter_et_valider_piece(v_extourne, auth.uid());

  return jsonb_build_object('montant', v_total, 'piece_id', v_piece, 'extourne_id', v_extourne);
end;
$$;

create or replace function public.apercu_produits_constates_avance(p_exercice_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_etab uuid;
begin
  select etablissement_id into v_etab from public.exercices_comptables where id = p_exercice_id;
  if v_etab is null or not coalesce(public.est_comptable(v_etab), false) then
    raise exception 'COMPTABLE_REQUIS' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'deja_passes', exists (select 1 from public.pieces_comptables
                            where source_type = 'produits_constates_avance' and source_id = p_exercice_id),
    'lignes', coalesce((select jsonb_agg(jsonb_build_object(
                'code', c.code, 'intitule', c.intitule, 'encaisse', c.encaisse, 'montant', c.montant))
                from public.calcul_produits_constates_avance(p_exercice_id) c), '[]'::jsonb),
    'total', coalesce((select sum(montant) from public.calcul_produits_constates_avance(p_exercice_id)), 0));
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Signaux d'aide : désormais sur pièces + écritures M14
-- ---------------------------------------------------------------------------
create or replace function public.predire_tresorerie(p_etablissement uuid, p_jours int default 30)
returns table (jour date, solde_projete numeric)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not coalesce(public.est_comptable(p_etablissement), false) then
    raise exception 'COMPTABLE_REQUIS' using errcode = '42501';
  end if;

  return query
  with treso as (
    select m.date_mouvement, m.debit - m.credit as net, p.origine
      from public.mouvements_comptables(p_etablissement, null, current_date) m
      join public.plans_comptables c on c.id = m.compte_id
      left join public.pieces_comptables p on p.reference = m.reference and p.etablissement_id = p_etablissement
     where c.type in ('banque', 'caisse')
  ),
  flux as (
    select t.date_mouvement as j, sum(t.net) as net from treso t
     where t.date_mouvement >= current_date - 30 and t.origine is distinct from 'a_nouveaux'
     group by 1
  ),
  solde_actuel as (
    -- Solde de l'exercice en cours (à-nouveaux compris) ; sans exercice, cumul.
    select coalesce(sum(t.net), 0) as s from treso t
     where t.date_mouvement >= coalesce(
       (select x.date_debut from public.exercices_comptables x
         where x.etablissement_id = p_etablissement and current_date between x.date_debut and x.date_fin),
       '-infinity'::date)
  ),
  moyenne as (select coalesce(sum(net) / 30.0, 0) as m from flux),
  series as (select generate_series(current_date, current_date + p_jours, '1 day')::date as j)
  select s.j, round((select s from solde_actuel) + (select m from moyenne) * (row_number() over (order by s.j) - 1), 2)
    from series s
   order by s.j;
end;
$$;

create or replace function public.analyser_tendances(p_etablissement uuid, p_mois int default 12)
returns table (mois date, total_charges numeric, total_produits numeric, solde_net numeric)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not coalesce(public.est_comptable(p_etablissement), false) then
    raise exception 'COMPTABLE_REQUIS' using errcode = '42501';
  end if;

  return query
  select date_trunc('month', m.date_mouvement)::date,
         coalesce(sum(m.debit - m.credit) filter (where c.type = 'charge'), 0),
         coalesce(sum(m.credit - m.debit) filter (where c.type = 'produit'), 0),
         coalesce(sum(m.credit - m.debit) filter (where c.type = 'produit'), 0)
       - coalesce(sum(m.debit - m.credit) filter (where c.type = 'charge'), 0)
    from public.mouvements_comptables(p_etablissement,
           (date_trunc('month', current_date) - make_interval(months => p_mois))::date, null) m
    join public.plans_comptables c on c.id = m.compte_id
   where c.type in ('charge', 'produit')
   group by 1
   order by 1;
end;
$$;

create or replace function public.detecter_anomalies_comptables(p_etablissement uuid)
returns table (
  ecriture_id uuid,
  date_ecriture date,
  libelle text,
  montant numeric,
  anomalie text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not coalesce(public.est_comptable(p_etablissement), false) then
    raise exception 'COMPTABLE_REQUIS' using errcode = '42501';
  end if;

  return query
  select t.id, t.d, t.l, t.m, t.a from (
    select e.id, e.date_ecriture as d, e.libelle as l, e.montant as m,
           case when e.montant >= 10000000 then 'montant_eleve' else 'double_saisie' end as a
      from public.ecritures_comptables e
     where e.etablissement_id = p_etablissement and e.deleted_at is null
       and (e.montant >= 10000000
            or exists (select 1 from public.ecritures_comptables e2
                        where e2.etablissement_id = p_etablissement and e2.id <> e.id
                          and e2.compte_debit_id = e.compte_debit_id and e2.compte_credit_id = e.compte_credit_id
                          and e2.montant = e.montant and e2.date_ecriture = e.date_ecriture and e2.deleted_at is null))
    union all
    -- Pièces saisies à la main : montant élevé, ou même montant / journal /
    -- date / libellé qu'une autre pièce validée non annulée (doublon probable).
    select p.id, p.date_piece, p.libelle, s.total,
           case when s.total >= 10000000 then 'montant_eleve' else 'double_saisie' end
      from public.pieces_comptables p
      join lateral (select sum(l.debit) as total from public.lignes_pieces_comptables l where l.piece_id = p.id) s on true
     where p.etablissement_id = p_etablissement and p.statut = 'validee' and p.origine = 'saisie'
       and p.annulee_par_piece_id is null
       and (s.total >= 10000000
            or exists (select 1 from public.pieces_comptables p2
                        join lateral (select sum(l2.debit) as total from public.lignes_pieces_comptables l2 where l2.piece_id = p2.id) s2 on true
                        where p2.etablissement_id = p_etablissement and p2.id <> p.id and p2.statut = 'validee'
                          and p2.origine = 'saisie' and p2.annulee_par_piece_id is null
                          and p2.journal_id = p.journal_id and p2.date_piece = p.date_piece
                          and lower(p2.libelle) = lower(p.libelle) and s2.total = s.total))
  ) t
  order by t.d desc;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Droits
-- ---------------------------------------------------------------------------
do $$
declare
  f text;
begin
  foreach f in array array[
    'public.calculer_etats(uuid, text, date, date)',
    'public.calcul_produits_constates_avance(uuid)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
  foreach f in array array[
    'public.etat_financier(uuid, uuid)',
    'public.passer_produits_constates_avance(uuid)',
    'public.apercu_produits_constates_avance(uuid)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end;
$$;
