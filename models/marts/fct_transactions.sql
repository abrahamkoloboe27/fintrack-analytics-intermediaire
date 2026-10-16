-- ============================================================
-- MODÈLE À CONVERTIR EN INCRÉMENTAL (Partie 2 — Section 3.1)
-- ============================================================
-- Ce modèle est actuellement en matérialisation "table".
-- Votre mission : le convertir en modèle incrémental.
--
-- Points à traiter :
--   1. Choisir la colonne de marqueur incrémental
--   2. Gérer le full_refresh
--   3. Traiter les transactions dont le statut change (en_attente → validee)
-- ============================================================

with enrichies as (
    select * from {{ ref('int_transactions_enrichies') }}
)

select
    transaction_id,
    compte_id,
    categorie_id,
    date_transaction,
    mois_transaction,
    montant,
    montant_signe,
    type_operation,
    nom_client,
    nom_categorie,
    groupe,
    statut

from enrichies
where statut = 'validee'
