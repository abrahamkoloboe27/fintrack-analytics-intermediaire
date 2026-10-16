-- Test singulier : chaque virement de fct_virements doit être équilibré
-- (écriture en partie double) :
--   - exactement 2 mouvements : un 'sortant' et un 'entrant' ;
--   - montants signés tous renseignés et de somme nulle (-montant + montant = 0).
-- Renvoie les virement_id en échec (aucune ligne = test réussi).
-- Un virement chargé avec une seule jambe fausserait les soldes des deux
-- comptes dans mart_solde_mensuel.
select
    virement_id,
    count(*)                                            as nb_mouvements,
    sum(case when sens = 'sortant' then 1 else 0 end)   as nb_sortants,
    sum(case when sens = 'entrant' then 1 else 0 end)   as nb_entrants,
    sum(montant_signe)                                  as somme_montants_signes

from {{ ref('fct_virements') }}
group by virement_id
having count(*) <> 2
    or sum(case when sens = 'sortant' then 1 else 0 end) <> 1
    or sum(case when sens = 'entrant' then 1 else 0 end) <> 1
    or count(montant_signe) <> 2
    or sum(montant_signe) <> 0
