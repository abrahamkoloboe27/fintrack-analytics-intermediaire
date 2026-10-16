with budgets as (
    select
        b.compte_id,
        b.categorie_id,
        b.mois,
        b.montant_prevu,
        c.nom_client,
        cat.nom_categorie
    from {{ ref('stg_budgets') }} b
    left join {{ ref('stg_comptes') }} c on b.compte_id = c.compte_id
    left join {{ ref('stg_categories') }} cat on b.categorie_id = cat.categorie_id
),

depenses as (
    select
        compte_id,
        categorie_id,
        mois_transaction as mois,
        sum(montant) as montant_reel
    from {{ ref('fct_transactions') }}
    where type_operation = 'debit'
    group by compte_id, categorie_id, mois_transaction
)

select
    coalesce(b.compte_id, d.compte_id)       as compte_id,
    coalesce(b.nom_client, c2.nom_client)     as nom_client,
    coalesce(b.categorie_id, d.categorie_id)  as categorie_id,
    coalesce(b.nom_categorie, cat2.nom_categorie) as nom_categorie,
    coalesce(b.mois, d.mois)                  as mois,
    coalesce(b.montant_prevu, 0)              as montant_prevu,
    coalesce(d.montant_reel, 0)               as montant_reel,
    coalesce(b.montant_prevu, 0) - coalesce(d.montant_reel, 0) as ecart,
    coalesce(d.montant_reel, 0) > coalesce(b.montant_prevu, 0) as depassement

from budgets b
full outer join depenses d
    on b.compte_id = d.compte_id
    and b.categorie_id = d.categorie_id
    and b.mois = d.mois
left join {{ ref('stg_comptes') }} c2 on d.compte_id = c2.compte_id
left join {{ ref('stg_categories') }} cat2 on d.categorie_id = cat2.categorie_id
