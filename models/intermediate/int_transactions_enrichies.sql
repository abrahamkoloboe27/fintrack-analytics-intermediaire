with transactions as (
    select * from {{ ref('stg_transactions') }}
),

comptes as (
    select * from {{ ref('stg_comptes') }}
),

categories as (
    select * from {{ ref('stg_categories') }}
)

select
    t.transaction_id,
    t.compte_id,
    t.date_transaction,
    t.montant,
    t.montant_signe,
    t.type_operation,
    t.categorie_id,
    t.description,
    t.statut,
    -- Clé mensuelle commune à tout le projet ('YYYY-MM', Partie 5.2) :
    -- remplace l'ancien date_trunc('month', ...)::date as mois_transaction
    {{ generer_periode('t.date_transaction') }} as periode,

    c.nom_client,
    c.type_compte,

    cat.nom_categorie,
    cat.type_categorie,
    cat.groupe

from transactions t
left join comptes c on t.compte_id = c.compte_id
left join categories cat on t.categorie_id = cat.categorie_id
