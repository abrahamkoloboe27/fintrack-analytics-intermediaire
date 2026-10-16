{{ config(severity='warn') }}

-- Test singulier (sévérité WARN) : alertes de dépassement de budget
-- (stg_alertes) incohérentes avec les transactions validées.
-- Pour chaque alerte, les dépenses sont recalculées depuis
-- fct_transactions : débits validés du même compte, de la même
-- catégorie et de la même période, datés au plus tard à date_generation
-- (montant_reel est la dépense « au moment de l'alerte »). Renvoie les
-- alertes :
--   - dont montant_reel diffère de ce recalcul ;
--   - ou dont le seuil du type d'alerte (seuil_pct) n'était pas atteint
--     par les débits recalculés.
-- On ne compare PAS à mart_budget_vs_reel.montant_reel : il couvre le
-- mois entier, dépenses postérieures à l'alerte comprises (faux positifs
-- en fonctionnement normal).
-- Limite : RAW n'a pas de date de validation ; une transaction validée
-- après l'alerte mais datée avant elle entre dans le recalcul.
--
-- Cas connus dans le jeu de données (seuil de 80 % jamais atteint) :
--   - alerte 2 (compte 2, catégorie 3, 2024-02) : 82,30 annoncés, 52,30 validés ;
--   - alerte 4 (compte 1, catégorie 3, 2024-03) : 132,10 annoncés, 92,10 validés ;
--   - alerte 5 (compte 2, catégorie 7, 2024-01) : 43,00 annoncés, 35,00 validés ;
--   - alerte 6 (compte 1, catégorie 7, 2024-01) : 52,00 annoncés, 42,00 validés.
-- Sévérité warn : stg_alertes reste un miroir fidèle de la source ; la
-- correction doit venir de l'application qui génère les alertes (aucun
-- modèle ni exposure ne consomme stg_alertes aujourd'hui).
with debits_avant_alerte as (

    select
        a.alerte_id,
        a.compte_id,
        a.categorie_id,
        a.periode,
        a.type_alerte,
        a.seuil_pct,
        a.montant_prevu,
        a.montant_reel,
        a.date_generation,
        coalesce(sum(t.montant), 0) as montant_reel_recalcule

    from {{ ref('stg_alertes') }} a
    left join {{ ref('fct_transactions') }} t
        on t.compte_id = a.compte_id
        and t.categorie_id = a.categorie_id
        and t.periode = a.periode
        and t.type_operation = 'debit'
        and t.date_transaction <= a.date_generation
    group by
        a.alerte_id,
        a.compte_id,
        a.categorie_id,
        a.periode,
        a.type_alerte,
        a.seuil_pct,
        a.montant_prevu,
        a.montant_reel,
        a.date_generation

)

select
    alerte_id,
    compte_id,
    categorie_id,
    periode,
    type_alerte,
    seuil_pct,
    montant_prevu,
    montant_reel,
    montant_reel_recalcule,
    round(100 * montant_reel_recalcule / nullif(montant_prevu, 0), 1) as taux_recalcule_pct,
    date_generation

from debits_avant_alerte
where montant_reel_recalcule <> montant_reel
    or 100 * montant_reel_recalcule / nullif(montant_prevu, 0) < seuil_pct
