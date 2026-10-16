with source as (
    select * from {{ source('fintrack_raw', 'raw_categories') }}
)

select
    id      as categorie_id,
    nom     as nom_categorie,
    type    as type_categorie,
    groupe

from source
