-- ============================================================
-- Budget prévu vs dépenses réelles (grain : compte × catégorie × mois)
-- ============================================================
-- Partie 2 — Section 5.2 : la clé mensuelle est désormais `periode`
-- ('YYYY-MM'), produite par la macro generer_periode() des deux côtés
-- de la jointure (budgets et dépenses), au lieu de DATE_TRUNC manuels.
-- `mois` (1er jour du mois, type date) est conservé pour les outils BI.
--
-- FULL OUTER JOIN : on garde à la fois
--   - les budgets sans aucune dépense (montant_reel = 0) ;
--   - les dépenses sans budget (montant_prevu = 0 → depassement = true,
--     taux_consommation_pct = null car division par zéro neutralisée).
-- ============================================================

{{ config(tags=['daily']) }}

with budgets as (
    select
        b.compte_id,
        b.categorie_id,
        {{ generer_periode('b.mois') }} as periode,
        b.montant_prevu,
        c.nom_client,
        cat.nom_categorie
    from {{ ref('stg_budgets') }} b
    left join {{ ref('stg_comptes') }} c on b.compte_id = c.compte_id
    left join {{ ref('stg_categories') }} cat on b.categorie_id = cat.categorie_id
),

depenses as (
    -- fct_transactions ne contient que des transactions validées
    select
        compte_id,
        categorie_id,
        periode,
        sum(montant) as montant_reel
    from {{ ref('fct_transactions') }}
    where type_operation = 'debit'
    group by compte_id, categorie_id, periode
),

budget_vs_reel as (
    select
        coalesce(b.compte_id, d.compte_id)              as compte_id,
        coalesce(b.nom_client, c2.nom_client)           as nom_client,
        coalesce(b.categorie_id, d.categorie_id)        as categorie_id,
        coalesce(b.nom_categorie, cat2.nom_categorie)   as nom_categorie,
        coalesce(b.periode, d.periode)                  as periode,
        coalesce(b.montant_prevu, 0)                    as montant_prevu,
        coalesce(d.montant_reel, 0)                     as montant_reel

    from budgets b
    full outer join depenses d
        on b.compte_id = d.compte_id
        and b.categorie_id = d.categorie_id
        and b.periode = d.periode
    left join {{ ref('stg_comptes') }} c2 on d.compte_id = c2.compte_id
    left join {{ ref('stg_categories') }} cat2 on d.categorie_id = cat2.categorie_id
)

select
    compte_id,
    nom_client,
    categorie_id,
    nom_categorie,
    periode,
    to_date(periode, 'YYYY-MM')                             as mois,
    montant_prevu,
    montant_reel,
    montant_prevu - montant_reel                            as ecart,
    montant_reel > montant_prevu                            as depassement,
    round(100 * montant_reel / nullif(montant_prevu, 0), 1) as taux_consommation_pct

from budget_vs_reel
