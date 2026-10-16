-- ============================================================
-- FAITS : TRANSACTIONS VALIDÉES — INCRÉMENTAL (Partie 2 — Section 3.1)
-- ============================================================
-- Grain : une ligne par transaction validée (clé : transaction_id).
-- Contrat : seules les transactions au statut 'validee' impactent les
-- soldes ; 'en_attente' et 'rejetee' sont exclues.
--
-- 1. Colonne de marqueur : date_transaction + fenêtre de recouvrement (lookback)
--    RAW n'a aucune colonne technique d'ingestion ou de mise à jour
--    (pas de _loaded_at / updated_at) : la date métier est le seul
--    marqueur disponible. Un run incrémental re-sélectionne toutes les
--    transactions validées dont la date est >= max(date_transaction)
--    déjà chargé - N jours (var `lookback_jours_transactions`, défaut 3,
--    ex. --vars '{lookback_jours_transactions: 7}' ; entier >= 0, sinon
--    erreur de compilation explicite). Cette fenêtre re-traite les
--    lignes récentes DÉJÀ chargées : une correction à la
--    source (montant, catégorie) dans les N jours est appliquée par le
--    MERGE. Les lignes nouvelles, même arrivées en retard, sont captées
--    par la fenêtre ou par l'anti-jointure (point 2). Le marqueur est
--    relatif au contenu de la table et non à current_date() : après une
--    semaine sans run, tout ce qui est postérieur au dernier chargement
--    est bien rattrapé.
--
-- 2. Transactions dont le statut change (en_attente → validee)
--    Une transaction validée tardivement garde sa date_transaction
--    d'origine, souvent HORS fenêtre : la fenêtre seule la raterait.
--    D'où l'anti-jointure (not exists sur transaction_id) : toute
--    transaction validée absente de la table est insérée, quelle que
--    soit sa date. Effet bonus : un marqueur « empoisonné » (date future
--    erronée) ne bloque pas les nouvelles lignes (et le test
--    « date pas dans le futur » le signale).
--    Stratégie merge + unique_key = 'transaction_id' : les lignes
--    re-sélectionnées sont mises à jour, les nouvelles insérées ; rejouer
--    un run ne crée jamais de doublon (idempotence), si la source n'a
--    pas deux fois la même clé. Le MERGE n'échoue que si une clé en
--    double dans la source existe déjà dans la cible ; une clé nouvelle
--    en double est insérée deux fois, et un --full-refresh (CTAS) ne
--    contrôle rien. La protection repose sur les tests unique / not_null
--    de staging (stg_transactions.transaction_id...) et des sources, qui
--    doivent faire partie de la même commande dbt build : un test ne
--    bloque les nœuds en aval que s'il est sélectionné (cf. cd.yml et le
--    sélecteur critical de selectors.yml).
--
-- 3. Gestion du full_refresh
--    - Premier run (table absente) ou `dbt run --full-refresh` :
--      is_incremental() = false → table reconstruite sur tout
--      l'historique ; la table cible (this) n'est jamais lue dans
--      cette branche, elle peut donc ne pas exister.
--    - Premier déploiement en prod : la table MARTS.fct_transactions de
--      la Partie 1 n'a pas le même schéma (mois_transaction, pas de
--      periode / montant_centimes / date_chargement) → un run
--      incrémental échouerait (on_schema_change='fail') : ce déploiement
--      DOIT passer --full-refresh (géré par le workflow CD).
--    - Réconciliation hebdomadaire : le job CD du lundi reconstruit les
--      modèles incrémentaux en --full-refresh, ce qui corrige les cas
--      listés au point 4. On ne fixe donc PAS full_refresh=false.
--
-- 4. Limites connues (corrigées au plus tard au --full-refresh hebdo)
--    - Annulation après chargement (validee → rejetee) : la ligne sort
--      du flux (filtre statut = 'validee'), le MERGE ne la voit plus ;
--      elle reste en table comme validée (solde faux) jusqu'à la
--      reconstruction. Idem pour une suppression physique dans RAW.
--      (Alternative écartée pour rester simple : un post-hook qui
--      supprime de la table les transactions dont le statut source
--      n'est plus 'validee'.)
--    - Correction d'une ligne déjà chargée HORS fenêtre, ou changement
--      d'un attribut dénormalisé (nom_client, nom_categorie, groupe) :
--      non propagé aux lignes hors fenêtre.
--    - Coût : l'anti-jointure lit toutes les transactions validées et la
--      seule colonne transaction_id de la cible (pas d'élagage par date) :
--      négligeable aux volumes actuels (~50 000 lignes/mois). Si la
--      volumétrie explose : borner l'anti-jointure (ex. 90 jours) ou
--      exploiter une colonne technique de mise à jour côté source.
--
-- 5. on_schema_change = 'fail'
--    Toute évolution de colonnes doit être délibérée : 'append_new_columns'
--    laisserait la nouvelle colonne à NULL sur l'historique (donnée
--    partiellement fausse, sans alerte), 'sync_all_columns' pourrait
--    supprimer une colonne lue par les marts / dashboards, 'ignore'
--    écarterait la nouvelle colonne en silence. Avec 'fail', le run
--    s'arrête avec un message explicite : on relance avec --full-refresh,
--    qui recalcule la colonne sur tout l'historique.
--
-- Pre-hook (Partie 7.2) : journaliser_watermark('date_transaction')
-- trace le max(date_transaction) déjà chargé avant chaque run incrémental.
-- date_chargement = sysdate() (UTC) : date du dernier (re)traitement par
-- dbt, rafraîchie par le MERGE pour les lignes re-traitées.
-- Tests unitaires (modes incrémental et full-refresh) : _fct_schema.yml.
-- ============================================================

{{
    config(
        materialized='incremental',
        unique_key='transaction_id',
        incremental_strategy='merge',
        on_schema_change='fail',
        pre_hook="{{ journaliser_watermark('date_transaction') }}",
        tags=['daily', 'critical']
    )
}}

{#- Fenêtre de recouvrement : entier >= 0, contrôlé dès le parsing. Sans
    ce contrôle, -2 produirait « dateadd('day', --2, ...) » (la fin de la
    ligne devient un commentaire SQL) et un texte comme « 7j » deviendrait
    0 en silence (filtre int). -#}
{%- set lookback_brut = var('lookback_jours_transactions', 3) | string | trim -%}
{%- if not modules.re.match('^[0-9]+$', lookback_brut) -%}
    {{ exceptions.raise_compiler_error(
        "fct_transactions : la variable lookback_jours_transactions doit être "
        ~ "un entier >= 0 (reçu : " ~ lookback_brut ~ ")."
    ) }}
{%- endif -%}
{%- set lookback_jours = lookback_brut | int %}

with transactions_validees as (
    select *
    from {{ ref('int_transactions_enrichies') }}
    where statut = 'validee'
),

{% if is_incremental() %}
-- Marqueur : date de la transaction la plus récente déjà chargée
dernier_chargement as (
    select max(date_transaction) as max_date_transaction
    from {{ this }}
),
{% endif %}

transactions_a_charger as (
    select t.*
    from transactions_validees t
    {% if is_incremental() %}
    where
        -- (1) fenêtre de recouvrement (lookback) : les N derniers jours
        --     sous le marqueur sont re-traités (arrivées tardives,
        --     corrections → MERGE)
        t.date_transaction >= (
            select dateadd('day', -{{ lookback_jours }}, max_date_transaction)
            from dernier_chargement
        )
        -- (2) anti-jointure : transaction validée absente de la table,
        --     insérée quelle que soit sa date (validation tardive)
        or not exists (
            select 1
            from {{ this }} as cible
            where cible.transaction_id = t.transaction_id
        )
    {% endif %}
)

select
    transaction_id,
    compte_id,
    categorie_id,
    date_transaction,
    periode,
    montant,
    {{ convertir_centimes('montant') }} as montant_centimes,
    montant_signe,
    {{ convertir_centimes('montant_signe') }} as montant_signe_centimes,
    type_operation,
    nom_client,
    nom_categorie,
    groupe,
    statut,
    sysdate() as date_chargement

from transactions_a_charger
