with source as (
    select * from {{ source('fintrack_raw', 'raw_budgets') }}
)

select
    id              as budget_id,
    compte_id,
    categorie_id,
    mois::date      as mois,
    montant_prevu

from source
