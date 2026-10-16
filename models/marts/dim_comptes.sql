-- Dimension des comptes : état courant de chaque compte (une ligne par compte).
-- L'historique des changements (statut, email, type) est exposé par
-- dim_comptes_historique, construit à partir du snapshot snap_comptes.
--
-- anciennete_jours : calculée par rapport à la date de Paris au moment du
-- build. current_date() dépend du paramètre TIMEZONE de la session
-- (America/Los_Angeles par défaut sur Snowflake) : au build quotidien de
-- la CD (05:15 UTC), il renverrait encore la veille. Même convention que
-- les tests « date pas dans le futur » (_fct_schema.yml).

{{ config(tags=['daily']) }}

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
    datediff('day', date_ouverture, convert_timezone('Europe/Paris', current_timestamp())::date) as anciennete_jours

from comptes
