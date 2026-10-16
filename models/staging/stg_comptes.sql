with source as (
    select * from {{ source('fintrack_raw', 'raw_comptes') }}
)

select
    id          as compte_id,
    nom_client,
    email,
    type_compte,
    date_ouverture,
    solde_initial,
    lower(statut) as statut

from source
