-- ============================================================
-- MODÈLE À ADAPTER (Partie 2 — Section 3.3)
-- ============================================================
-- Ce modèle calcule le solde mensuel par compte à partir des
-- transactions uniquement. Votre mission : l'adapter pour
-- intégrer aussi les virements internes (fct_virements).
--
-- Réfléchissez aussi à la matérialisation optimale.
-- ============================================================

with transactions_mensuelles as (
    select
        compte_id,
        mois_transaction as mois,
        sum(case when type_operation = 'credit' then montant else 0 end) as total_credits,
        sum(case when type_operation = 'debit'  then montant else 0 end) as total_debits,
        sum(montant_signe) as solde_net_mois
    from {{ ref('fct_transactions') }}
    group by compte_id, mois_transaction
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
    tm.compte_id,
    c.nom_client,
    c.type_compte,
    tm.mois,
    tm.total_credits,
    tm.total_debits,
    tm.solde_net_mois,
    c.solde_initial + sum(tm.solde_net_mois) over (
        partition by tm.compte_id
        order by tm.mois
        rows between unbounded preceding and current row
    ) as solde_cumule

from transactions_mensuelles tm
inner join comptes c on tm.compte_id = c.compte_id
