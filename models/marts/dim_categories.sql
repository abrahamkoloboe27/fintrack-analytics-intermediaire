-- ============================================================
-- Dimension des catégories (Partie 2 — Section 2 : seeds)
-- ============================================================
-- Enrichit chaque catégorie avec les métadonnées de son groupe,
-- issues du seed mapping_groupes (chargé par `dbt seed`) :
--   - ordre_affichage    : ordre des groupes dans les dashboards
--   - priorite_dashboard : niveau de mise en avant (haute → info)
-- LEFT JOIN : une catégorie dont le groupe serait absent du seed
-- reste visible (colonnes du seed à null) ; le test not_null sur
-- ordre_affichage (_marts_schema.yml) signale alors le trou dans
-- le référentiel au lieu de faire disparaître la catégorie.
-- ============================================================

{{ config(tags=['daily']) }}

with categories as (
    select * from {{ ref('stg_categories') }}
),

mapping_groupes as (
    select * from {{ ref('mapping_groupes') }}
)

select
    c.categorie_id,
    c.nom_categorie,
    c.type_categorie,
    c.groupe,
    m.ordre_affichage,
    m.priorite_dashboard

from categories c
left join mapping_groupes m on c.groupe = m.groupe
