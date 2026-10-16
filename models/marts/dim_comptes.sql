with comptes as (
    select * from {{ ref('stg_comptes') }}
)

select
    compte_id,
    nom_client,
    email,
    type_compte,
    date_ouverture,
    solde_initial,
    statut,
    datediff('day', date_ouverture, current_date()) as anciennete_jours

from comptes
