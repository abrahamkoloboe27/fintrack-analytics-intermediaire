-- Test singulier : aucun compte épargne ne doit avoir un solde cumulé négatif
select
    compte_id,
    mois,
    solde_cumule
from {{ ref('mart_solde_mensuel') }}
where type_compte = 'epargne'
  and solde_cumule < 0
