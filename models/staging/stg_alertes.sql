-- ============================================================
-- STAGING DES ALERTES DE DÉPASSEMENT DE BUDGET (Partie 2 — Section 1)
-- ============================================================
-- 1 ligne = 1 alerte (compte x catégorie x mois).
-- Renommage des colonnes, puis enrichissement avec le seed
-- seuils_alerte (seuil en %, sévérité, libellé) sur
-- type_alerte = code_alerte.
--
-- Choix techniques :
--   - LEFT JOIN : une alerte dont le type est absent du seed est
--     conservée (seuil_pct / severite à NULL) au lieu d'être perdue
--     silencieusement ; les tests relationships (type_alerte) et
--     not_null (severite) de _stg_schema.yml la signalent.
--   - periode (YYYY-MM) via la macro generer_periode (Partie 5.2) :
--     même clé mensuelle que les autres modèles du projet.
--   - taux_consommation_pct : nullif évite la division par zéro
--     quand le budget prévu vaut 0 (le taux est alors NULL).
-- ============================================================

with source as (
    select * from {{ source('fintrack_raw', 'raw_alertes') }}
),

seuils as (
    select * from {{ ref('seuils_alerte') }}
),

alertes as (
    select
        id                              as alerte_id,
        compte_id,
        categorie_id,
        mois::date                      as mois,
        lower(trim(type_alerte))        as type_alerte,
        montant_prevu,
        montant_reel,
        date_generation::timestamp_ntz  as date_generation,
        acquittee                       as est_acquittee

    from source
)

select
    a.alerte_id,
    a.compte_id,
    a.categorie_id,
    a.mois,
    {{ generer_periode('a.mois') }}     as periode,
    a.type_alerte,
    s.seuil_pct,
    s.severite,
    s.description                       as description_alerte,
    a.montant_prevu,
    a.montant_reel,
    round(100 * a.montant_reel / nullif(a.montant_prevu, 0), 1) as taux_consommation_pct,
    a.date_generation,
    a.est_acquittee

from alertes a
left join seuils s
    on a.type_alerte = s.code_alerte
