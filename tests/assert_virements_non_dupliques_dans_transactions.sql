{{ config(severity='warn') }}

-- Test singulier (sévérité WARN) : transactions de fct_transactions qui
-- dupliquent un virement interne de fct_virements, c'est-à-dire même
-- compte, même montant, même horodatage et même sens :
--   crédit ↔ jambe 'entrant', débit ↔ jambe 'sortant'.
-- Ces mouvements sont alors comptés deux fois dans mart_solde_mensuel
-- (une fois comme transaction, une fois comme virement).
--
-- Cas connus dans le jeu de données :
--   - transactions 41-43 (compte 3, crédit 300, 15/01 → 15/03 10:00)
--     = jambes entrantes des virements 1-3 ;
--   - transaction 40 (compte 4, débit 500, 20/01 10:00)
--     = jambe sortante du virement 4.
-- Sévérité warn : le test documente l'anomalie sans bloquer la
-- pipeline ; on ne supprime pas de données silencieusement, la
-- correction doit venir de la source (ne plus saisir le virement comme
-- transaction).
select
    t.transaction_id,
    v.virement_id,
    v.mouvement_id,
    t.compte_id,
    t.type_operation,
    v.sens,
    t.montant,
    t.date_transaction

from {{ ref('fct_transactions') }} t
inner join {{ ref('fct_virements') }} v
    on t.compte_id = v.compte_id
    and t.montant = v.montant
    and t.date_transaction = v.date_virement
    and (
        (t.type_operation = 'credit' and v.sens = 'entrant')
        or (t.type_operation = 'debit' and v.sens = 'sortant')
    )
