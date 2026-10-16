-- ============================================================
-- STAGING DES VIREMENTS INTERNES (Partie 2 — Section 1)
-- ============================================================
-- 1 ligne = 1 ordre de virement entre deux comptes FinTrack.
-- Renommage des colonnes et nettoyage léger uniquement :
--   - compte_dest_id devient compte_destination_id (nom explicite) ;
--   - un motif vide ou composé d'espaces devient NULL, pour que le
--     test taux_null (Partie 5.3) le compte comme absent ;
--   - statut normalisé (minuscules, sans espaces), comme stg_comptes.
--
-- « Filtrage éventuel » : AUCUN filtre sur le statut ici. Le staging
-- reste un miroir fidèle de la source (execute, en_attente, annule) :
-- les tests de qualité portent sur toutes les lignes et les virements
-- non exécutés restent disponibles pour l'analyse. Le filtre
-- statut = 'execute' est appliqué dans fct_virements.
-- ============================================================

with source as (
    select * from {{ source('fintrack_raw', 'raw_virements') }}
)

select
    id                              as virement_id,
    compte_source_id,
    compte_dest_id                  as compte_destination_id,
    montant,
    date_virement::timestamp_ntz    as date_virement,
    nullif(trim(motif), '')         as motif,
    lower(trim(statut))             as statut

from source
