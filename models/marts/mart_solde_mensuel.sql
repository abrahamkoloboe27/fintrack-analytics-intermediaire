-- ============================================================
-- Solde mensuel par compte (Partie 2 — Section 3.3)
-- ============================================================
-- Grain : une ligne par compte et par `periode` ('YYYY-MM') ayant
-- au moins un mouvement. Deux sources de mouvements :
--   - fct_transactions : transactions validées (crédits / débits) ;
--   - fct_virements    : virements internes exécutés, une ligne
--                        'entrant' ou 'sortant' par compte concerné.
-- FULL OUTER JOIN entre les deux agrégats mensuels : un mois avec
-- uniquement des virements (ex : compte 4 en 2024-02) ou uniquement
-- des transactions est conservé, les montants absents valent 0.
--
-- Matérialisation : TABLE (reconstruite à chaque run), et non
-- incrémentale, car :
--   - solde_cumule est un cumul depuis l'origine, sur TOUT l'historique
--     du compte : une transaction validée en retard dans un mois M
--     modifie le solde de tous les mois >= M. Un incrémental devrait
--     recalculer toute la « queue » de chaque compte touché → logique
--     complexe et risque de soldes faux ;
--   - l'agrégat est petit (nb comptes × nb mois) : le reconstruire
--     entièrement coûte peu, même avec des faits incrémentaux en amont ;
--   - les dashboards le lisent souvent : une table évite de rejouer
--     agrégations et fonction de fenêtre à chaque requête (≠ vue).
--
-- Point d'attention (données sources) : certains virements existent
-- AUSSI sous forme de transactions, ils sont alors comptés deux fois
-- dans le solde. Dans le jeu de données :
--   - transactions 41-43 (crédits de 300 sur le compte 3) = virements 1-3 ;
--   - transaction 40 (débit de 500 sur le compte 4) = virement 4.
-- On ne supprime pas ces lignes silencieusement : le test singulier
-- assert_virements_non_dupliques_dans_transactions (sévérité warn)
-- les signale pour correction à la source.
-- ============================================================

{{ config(materialized='table', tags=['daily', 'critical']) }}

with transactions_mensuelles as (
    select
        compte_id,
        periode,
        sum(case when type_operation = 'credit' then montant else 0 end) as total_credits,
        sum(case when type_operation = 'debit'  then montant else 0 end) as total_debits,
        sum(montant_signe) as solde_net_transactions
    from {{ ref('fct_transactions') }}
    group by compte_id, periode
),

virements_mensuels as (
    select
        compte_id,
        periode,
        sum(case when sens = 'entrant' then montant else 0 end) as total_virements_entrants,
        sum(case when sens = 'sortant' then montant else 0 end) as total_virements_sortants,
        sum(montant_signe) as solde_net_virements
    from {{ ref('fct_virements') }}
    group by compte_id, periode
),

mouvements_mensuels as (
    select
        coalesce(tm.compte_id, vm.compte_id)            as compte_id,
        coalesce(tm.periode, vm.periode)                as periode,
        coalesce(tm.total_credits, 0)                   as total_credits,
        coalesce(tm.total_debits, 0)                    as total_debits,
        coalesce(vm.total_virements_entrants, 0)        as total_virements_entrants,
        coalesce(vm.total_virements_sortants, 0)        as total_virements_sortants,
        coalesce(tm.solde_net_transactions, 0)          as solde_net_transactions,
        coalesce(vm.solde_net_virements, 0)             as solde_net_virements

    from transactions_mensuelles tm
    full outer join virements_mensuels vm
        on tm.compte_id = vm.compte_id
        and tm.periode = vm.periode
),

comptes as (
    select
        compte_id,
        nom_client,
        type_compte,
        solde_initial
    from {{ ref('dim_comptes') }}
)

select
    mm.compte_id,
    c.nom_client,
    c.type_compte,
    mm.periode,
    to_date(mm.periode, 'YYYY-MM') as mois,
    mm.total_credits,
    mm.total_debits,
    mm.total_virements_entrants,
    mm.total_virements_sortants,
    mm.solde_net_transactions,
    mm.solde_net_virements,
    mm.solde_net_transactions + mm.solde_net_virements as solde_net_mois,
    c.solde_initial + sum(mm.solde_net_transactions + mm.solde_net_virements) over (
        partition by mm.compte_id
        order by mm.periode
        rows between unbounded preceding and current row
    ) as solde_cumule

from mouvements_mensuels mm
inner join comptes c on mm.compte_id = c.compte_id
