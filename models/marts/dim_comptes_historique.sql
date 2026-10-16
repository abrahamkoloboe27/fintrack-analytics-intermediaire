-- ============================================================
-- Historique des comptes — SCD Type 2 (Partie 2 — Section 4.2)
-- ============================================================
-- Une ligne par VERSION d'un compte, lue depuis le snapshot
-- snap_comptes (stratégie check sur statut, email et type_compte) :
--   - valide_depuis / valide_jusqu_a : bornes de validité de la version
--     (dbt_valid_from / dbt_valid_to) ; valide_jusqu_a est null pour
--     la version en vigueur ;
--   - est_version_courante : true pour la version en vigueur ;
--   - numero_version : rang chronologique de la version (1 = première
--     version capturée par `dbt snapshot` pour ce compte) ;
--   - duree_jours : durée de la version en jours ; pour la version
--     courante, calculée jusqu'à l'instant de la requête.
--
-- Matérialisation : VUE (et non table). La durée de la version
-- courante dépend du moment où on interroge le modèle (sysdate()) :
-- dans une table, elle serait figée à la date du dernier build (ce
-- modèle n'est reconstruit qu'une fois par semaine : tag weekly).
-- La vue ne stocke rien et reflète toujours le dernier état du snapshot.
--
-- Fuseau horaire : sur Snowflake, dbt snapshot (stratégie check) remplit
-- dbt_valid_from / dbt_valid_to avec
-- to_timestamp_ntz(convert_timezone('UTC', current_timestamp())),
-- soit un timestamp_ntz en UTC. sysdate() renvoie lui aussi l'heure UTC
-- en timestamp_ntz : les deux bornes du datediff sont donc comparables
-- (current_timestamp() serait, lui, à l'heure locale de la session).
--
-- Compte supprimé de la source (hard_deletes: invalidate) : sa dernière
-- version est fermée (valide_jusqu_a renseigné), il n'a donc plus de
-- version courante.
-- ============================================================

{{ config(materialized='view', tags=['weekly']) }}

with snapshot_comptes as (
    select * from {{ ref('snap_comptes') }}
)

select
    dbt_scd_id              as version_id,
    id                      as compte_id,
    nom_client,
    email,
    type_compte,
    lower(statut)           as statut,
    date_ouverture,
    solde_initial,
    dbt_valid_from          as valide_depuis,
    dbt_valid_to            as valide_jusqu_a,
    dbt_valid_to is null    as est_version_courante,
    row_number() over (
        partition by id
        order by dbt_valid_from
    )                       as numero_version,
    datediff('day', dbt_valid_from, coalesce(dbt_valid_to, sysdate())) as duree_jours

from snapshot_comptes
