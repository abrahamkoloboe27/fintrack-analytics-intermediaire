-- ============================================================
-- ANALYSE : RÉTENTION MENSUELLE DES COMPTES ACTIFS (Partie 9.1 — bonus)
-- ============================================================
-- Question métier : d'un mois sur l'autre, quelle part des comptes actifs
-- le mois M-1 l'est encore le mois M ?
--
-- Définitions
--   - Unité d'analyse : le compte (compte_id). FinTrack n'a pas de table
--     « utilisateurs » et un compte joint est partagé par plusieurs
--     personnes : un « utilisateur actif » est donc un compte actif.
--   - Compte actif le mois M : au moins une transaction validée
--     (fct_transactions) OU au moins un virement interne émis et exécuté
--     (fct_virements, sens = 'sortant') pendant le mois M. Recevoir un
--     virement est passif : ce n'est pas un signe d'activité du client.
--   - Taux de rétention (M) = actifs en M-1 ET en M / actifs en M-1.
--   - Les actifs du mois se décomposent en : retenus (déjà actifs en M-1)
--     + nouveaux (premier mois d'activité) + réactivés (actifs avant M-1,
--     inactifs en M-1). Perdus = actifs en M-1 mais inactifs en M.
--
-- Deux vues, choisies avec la variable dbt `vue_retention` :
--   - mensuelle (défaut) : une ligne par mois, rétention M-1 → M ;
--   - cohortes : une ligne par cohorte (mois de première activité) et par
--     mois écoulé depuis l'entrée dans la cohorte.
--
-- Une analyse n'est jamais matérialisée : dbt la compile seulement.
--   dbt compile -s retention_mensuelle
--     → SQL dans target/compiled/fintrack_analytics/analyses/retention_mensuelle.sql
--   dbt show -s retention_mensuelle --limit 50
--   dbt show -s retention_mensuelle --vars '{vue_retention: cohortes}' --limit 50
--
-- Résultat attendu sur le jeu de données (scripts 02 + 03), vue mensuelle :
--   periode | actifs | actifs M-1 | retenus | nouveaux | réactivés | perdus | rétention
--   2024-01 |      5 |          0 |       0 |        5 |         0 |      0 |      null
--   2024-02 |      4 |          5 |       4 |        0 |         0 |      1 |    80.0 %
--   2024-03 |      2 |          4 |       2 |        0 |         0 |      2 |    50.0 %
--   2024-04 |      3 |          2 |       1 |        0 |         2 |      1 |    50.0 %
--   2024-05 |      3 |          3 |       3 |        0 |         0 |      0 |   100.0 %
--   2024-06 |      3 |          3 |       3 |        0 |         0 |      0 |   100.0 %
-- Les comptes 2 et 4, inactifs en mars, sont réactivés en avril. Le compte 3
-- n'est actif de janvier à mars que grâce aux transactions 41 à 43, doublons
-- des virements 1 à 3 qu'il a reçus (cf. assert_virements_non_dupliques_dans_transactions).
-- ============================================================

{# Contrôle d'espaces Jinja : uniquement à droite des balises (-%}). Un tiret
   à gauche ({%-) supprimerait le saut de ligne qui termine le commentaire
   SQL précédent et y collerait le SQL suivant, qui serait alors commenté. #}
{% set vue_retention = var('vue_retention', 'mensuelle') -%}
{% if vue_retention not in ['mensuelle', 'cohortes'] -%}
    {{ exceptions.raise_compiler_error(
        "retention_mensuelle : vue_retention = '" ~ vue_retention
        ~ "' est invalide (valeurs possibles : 'mensuelle', 'cohortes')."
    ) }}
{% endif -%}
{# Plafond du calendrier mensuel : generator() exige un nombre de lignes
   constant. 600 mois = 50 ans d'historique, largement suffisant. #}
{% set nb_mois_max = 600 -%}

with transactions as (
    select * from {{ ref('fct_transactions') }}
),

virements as (
    select * from {{ ref('fct_virements') }}
),

-- 1. Activité : une ligne par (compte, mois) où le compte a été actif ----------
-- `union` (et non `union all`) dédoublonne : un compte actif le même mois via
-- une transaction ET un virement n'est compté qu'une fois. Chaque ligne étant
-- unique par (compte_id, mois), count(*) compte ensuite des comptes distincts.
activite_mensuelle as (
    select
        compte_id,
        to_date(periode, 'YYYY-MM') as mois
    from transactions
    where statut = 'validee'        -- déjà garanti par fct_transactions, rappelé pour expliciter la règle

    union

    select
        compte_id,
        to_date(periode, 'YYYY-MM') as mois
    from virements
    where sens = 'sortant'          -- seul l'émetteur d'un virement est considéré comme actif
      and statut = 'execute'        -- déjà garanti par fct_virements
),

-- 2. Calendrier continu des mois (« month spine ») ------------------------------
-- Du premier au dernier mois d'activité, SANS trou : un mois sans aucune
-- activité doit apparaître avec 0 compte actif, sinon le « mois précédent »
-- serait faux (mars comparé à janvier si février était vide).
-- dbt_utils.date_spine n'est pas utilisé : il calcule le nombre de mois à la
-- compilation (requête lancée par dbt), donc avec des bornes figées ; ici les
-- bornes sont lues dans les données au moment de l'exécution.
bornes as (
    select
        min(mois) as premier_mois,
        max(mois) as dernier_mois
    from activite_mensuelle
),

-- Entiers 0, 1, 2… : seq4() peut présenter des trous, row_number() les comble
entiers as (
    select row_number() over (order by seq4()) - 1 as rang
    from table(generator(rowcount => {{ nb_mois_max }}))
),

calendrier_mois as (
    select dateadd('month', e.rang, b.premier_mois) as mois
    from bornes b
    cross join entiers e
    where e.rang <= datediff('month', b.premier_mois, b.dernier_mois)
),

-- 3. Briques communes aux deux vues -----------------------------------------------
-- Mois de première activité de chaque compte (= sa cohorte)
premiere_activite as (
    select
        compte_id,
        min(mois) as mois_cohorte
    from activite_mensuelle
    group by compte_id
),

actifs_par_mois as (
    select
        mois,
        count(*) as nb_comptes_actifs
    from activite_mensuelle
    group by mois
),

-- Comptes actifs le mois M ET le mois M-1 (auto-jointure décalée d'un mois)
retenus_par_mois as (
    select
        courant.mois,
        count(*) as nb_comptes_retenus
    from activite_mensuelle courant
    inner join activite_mensuelle precedent
        on precedent.compte_id = courant.compte_id
        and precedent.mois = dateadd('month', -1, courant.mois)
    group by courant.mois
),

nouveaux_par_mois as (
    select
        mois_cohorte as mois,
        count(*) as nb_nouveaux_comptes
    from premiere_activite
    group by mois_cohorte
),

-- 4. Vue mensuelle : rétention M-1 → M --------------------------------------------
indicateurs_mensuels as (
    select
        cal.mois,
        coalesce(act.nb_comptes_actifs, 0)      as nb_comptes_actifs,
        coalesce(prec.nb_comptes_actifs, 0)     as nb_comptes_actifs_mois_precedent,
        coalesce(ret.nb_comptes_retenus, 0)     as nb_comptes_retenus,
        coalesce(nouv.nb_nouveaux_comptes, 0)   as nb_nouveaux_comptes
    from calendrier_mois cal
    left join actifs_par_mois act
        on act.mois = cal.mois
    left join actifs_par_mois prec
        on prec.mois = dateadd('month', -1, cal.mois)
    left join retenus_par_mois ret
        on ret.mois = cal.mois
    left join nouveaux_par_mois nouv
        on nouv.mois = cal.mois
),

retention_mensuelle as (
    select
        {{ generer_periode('mois') }}                                     as periode,
        mois,
        nb_comptes_actifs,
        nb_comptes_actifs_mois_precedent,
        nb_comptes_retenus,
        nb_nouveaux_comptes,
        nb_comptes_actifs - nb_comptes_retenus - nb_nouveaux_comptes      as nb_comptes_reactives,
        nb_comptes_actifs_mois_precedent - nb_comptes_retenus             as nb_comptes_perdus,
        -- taux non défini (null) quand aucun compte n'était actif le mois précédent
        round(100 * nb_comptes_retenus
            / nullif(nb_comptes_actifs_mois_precedent, 0), 1)             as taux_retention_pct,
        round(100 * (nb_comptes_actifs_mois_precedent - nb_comptes_retenus)
            / nullif(nb_comptes_actifs_mois_precedent, 0), 1)             as taux_attrition_pct
    from indicateurs_mensuels
),

-- 5. Vue par cohortes : devenir de chaque cohorte mois après mois -----------------
taille_cohortes as (
    select
        mois_cohorte,
        count(*) as taille_cohorte
    from premiere_activite
    group by mois_cohorte
),

actifs_par_cohorte as (
    select
        p.mois_cohorte,
        a.mois,
        count(*) as nb_comptes_actifs
    from activite_mensuelle a
    inner join premiere_activite p
        on p.compte_id = a.compte_id
    group by p.mois_cohorte, a.mois
),

retention_cohortes as (
    select
        {{ generer_periode('t.mois_cohorte') }}          as periode_cohorte,
        {{ generer_periode('cal.mois') }}                as periode,
        datediff('month', t.mois_cohorte, cal.mois)      as mois_depuis_entree,
        t.taille_cohorte,
        coalesce(a.nb_comptes_actifs, 0)                 as nb_comptes_actifs,
        -- 100 % au mois 0 par construction
        round(100 * coalesce(a.nb_comptes_actifs, 0) / t.taille_cohorte, 1) as taux_retention_cohorte_pct
    from taille_cohortes t
    inner join calendrier_mois cal
        on cal.mois >= t.mois_cohorte
    left join actifs_par_cohorte a
        on a.mois_cohorte = t.mois_cohorte
        and a.mois = cal.mois
)

{% if vue_retention == 'cohortes' -%}
select * from retention_cohortes
order by periode_cohorte, mois_depuis_entree
{% else -%}
select * from retention_mensuelle
order by periode
{% endif %}
