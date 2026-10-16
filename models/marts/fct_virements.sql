-- ============================================================
-- FAITS : MOUVEMENTS DE VIREMENTS INTERNES — INCRÉMENTAL (Partie 2 — Section 3.2)
-- ============================================================
-- Grain : une ligne par virement exécuté ET par sens. Chaque virement
-- produit deux mouvements (écriture en partie double) :
--   - 'sortant' : compte_id = compte source,      montant_signe = -montant
--   - 'entrant' : compte_id = compte destination, montant_signe = +montant
-- La somme des montant_signe d'un virement vaut donc toujours 0 (test
-- singulier assert_virements_equilibres), et mart_solde_mensuel agrège
-- virements et transactions de la même façon, par compte_id.
-- Clé : mouvement_id = hash(virement_id, sens) (dbt_utils.generate_surrogate_key).
--
-- Seuls les virements exécutés sont retenus (statut = 'execute') :
-- 'en_attente' et 'annule' n'ont pas (ou plus) d'effet sur les soldes.
-- stg_virements conserve tous les statuts : le filtrage se fait ici.
--
-- Noms des clients (titulaire et contrepartie) : LEFT JOIN sur
-- stg_comptes, pour ne jamais perdre un mouvement d'argent si un compte
-- manquait au référentiel (l'intégrité est contrôlée par les tests
-- relationships de stg_virements et de ce modèle).
--
-- Incrémental : même stratégie que fct_transactions (voir son en-tête).
--   - Marqueur date_virement (date de l'ordre) + fenêtre de recouvrement
--     (lookback) de N jours (var `lookback_jours_virements`, défaut 3,
--     entier >= 0 contrôlé à la compilation), re-traitée par MERGE.
--   - Anti-jointure sur virement_id : un virement passé de 'en_attente'
--     à 'execute' après coup est inséré quelle que soit sa date.
--   - unique_key = mouvement_id ; on_schema_change = 'fail' (toute
--     évolution de colonnes impose un --full-refresh délibéré).
--   - Unicité : ni le MERGE (une clé nouvelle en double est insérée deux
--     fois) ni le --full-refresh ne la contrôlent ; les tests unique /
--     not_null de stg_virements et de raw_virements doivent faire partie
--     de la même commande dbt build (cf. fct_transactions, point 2).
--   - Premier run / --full-refresh : reconstruction complète, la table
--     cible n'est pas lue.
-- Limite connue : un virement chargé puis annulé (execute → annule) ou
-- supprimé de RAW n'est plus sélectionné et reste en table jusqu'au
-- --full-refresh hebdomadaire (job CD du lundi), qui reconstruit tout.
-- ============================================================

{{
    config(
        materialized='incremental',
        unique_key='mouvement_id',
        incremental_strategy='merge',
        on_schema_change='fail',
        tags=['daily', 'critical']
    )
}}

{#- Fenêtre de recouvrement : entier >= 0, contrôlé dès le parsing (même
    contrôle que fct_transactions : une valeur négative produirait « -- »,
    un texte deviendrait 0 en silence). -#}
{%- set lookback_brut = var('lookback_jours_virements', 3) | string | trim -%}
{%- if not modules.re.match('^[0-9]+$', lookback_brut) -%}
    {{ exceptions.raise_compiler_error(
        "fct_virements : la variable lookback_jours_virements doit être "
        ~ "un entier >= 0 (reçu : " ~ lookback_brut ~ ")."
    ) }}
{%- endif -%}
{%- set lookback_jours = lookback_brut | int %}

with virements_executes as (
    select *
    from {{ ref('stg_virements') }}
    where statut = 'execute'
),

{% if is_incremental() %}
-- Marqueur : date du virement le plus récent déjà chargé
dernier_chargement as (
    select max(date_virement) as max_date_virement
    from {{ this }}
),
{% endif %}

virements_a_charger as (
    select v.*
    from virements_executes v
    {% if is_incremental() %}
    where
        -- (1) fenêtre de recouvrement (lookback) : les N derniers jours
        --     sous le marqueur sont re-traités (arrivées tardives,
        --     corrections → MERGE)
        v.date_virement >= (
            select dateadd('day', -{{ lookback_jours }}, max_date_virement)
            from dernier_chargement
        )
        -- (2) anti-jointure : virement exécuté absent de la table,
        --     inséré quelle que soit sa date (exécution tardive)
        or not exists (
            select 1
            from {{ this }} as cible
            where cible.virement_id = v.virement_id
        )
    {% endif %}
),

comptes as (
    select
        compte_id,
        nom_client,
        type_compte
    from {{ ref('stg_comptes') }}
),

-- Partie double : une jambe sortante + une jambe entrante par virement
mouvements as (
    select
        virement_id,
        'sortant'               as sens,
        compte_source_id        as compte_id,
        compte_destination_id   as compte_contrepartie_id,
        compte_source_id,
        compte_destination_id,
        montant,
        -montant                as montant_signe,
        date_virement,
        motif,
        statut
    from virements_a_charger

    union all

    select
        virement_id,
        'entrant'               as sens,
        compte_destination_id   as compte_id,
        compte_source_id        as compte_contrepartie_id,
        compte_source_id,
        compte_destination_id,
        montant,
        montant                 as montant_signe,
        date_virement,
        motif,
        statut
    from virements_a_charger
)

select
    {{ dbt_utils.generate_surrogate_key(['m.virement_id', 'm.sens']) }} as mouvement_id,
    m.virement_id,
    m.sens,
    m.compte_id,
    titulaire.nom_client,
    titulaire.type_compte,
    m.compte_contrepartie_id,
    contrepartie.nom_client as nom_client_contrepartie,
    m.compte_source_id,
    m.compte_destination_id,
    m.montant,
    {{ convertir_centimes('m.montant') }} as montant_centimes,
    m.montant_signe,
    {{ convertir_centimes('m.montant_signe') }} as montant_signe_centimes,
    m.date_virement,
    {{ generer_periode('m.date_virement') }} as periode,
    m.motif,
    m.statut,
    sysdate() as date_chargement

from mouvements m
left join comptes titulaire on m.compte_id = titulaire.compte_id
left join comptes contrepartie on m.compte_contrepartie_id = contrepartie.compte_id
