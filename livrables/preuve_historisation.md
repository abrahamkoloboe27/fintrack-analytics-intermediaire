# Preuve d'historisation — snapshot `snap_comptes` (SCD Type 2)

Environnement : target `dev`, schéma `FINTRACK_DB.DEV_ABRAHAM`, 16/10/2026.
Snapshot : [`snapshots/snap_comptes.yml`](../snapshots/snap_comptes.yml). Il porte sur la source `raw_comptes`, avec la stratégie `check` sur `statut`, `email` et `type_compte`, la clé `id` et `hard_deletes: invalidate`.

Le protocole a été déroulé en dev. Depuis, `RAW.raw_comptes` reste dans l'état final du protocole (comptes 2 `cloture`, 4 `inactif`, 5 `actif`). L'historique de production (schéma `SNAPSHOTS`) démarre donc au premier déploiement, avec cet état comme première version.

## Protocole suivi (script `scripts/04_snapshot_updates.sql`)

| Étape | Action | Horodatage du snapshot (UTC) | Résultat dbt |
|---|---|---|---|
| A | `dbt build`, qui inclut le premier `dbt snapshot` (état initial) | 2026-10-16 12:05:55 | 6 versions créées |
| B | `UPDATE` : Emma (5) redevient `actif`, Bob (2) passe `cloture`, puis `dbt snapshot` | 2026-10-16 12:10:35 | 2 versions fermées, 2 ouvertes |
| C | `UPDATE` : David (4) passe `inactif`, puis `dbt snapshot` | 2026-10-16 12:11:18 | 1 version fermée, 1 ouverte |

## 1. Table snapshot brute

```sql
select id as compte_id, nom_client, statut, email, type_compte, dbt_valid_from, dbt_valid_to
from FINTRACK_DB.DEV_ABRAHAM.SNAP_COMPTES
order by id, dbt_valid_from;
```

| compte_id | nom_client | statut | email | type_compte | dbt_valid_from | dbt_valid_to |
|---|---|---|---|---|---|---|
| 1 | Alice Dupont | actif | alice.dupont@email.fr | courant | 2026-10-16 12:05:55.322 | *NULL* |
| 2 | Bob Martin | actif | bob.martin@email.fr | courant | 2026-10-16 12:05:55.322 | 2026-10-16 12:10:35.299 |
| 2 | Bob Martin | **cloture** | bob.martin@email.fr | courant | 2026-10-16 12:10:35.299 | *NULL* |
| 3 | Claire Leroy | actif | claire.leroy@email.fr | epargne | 2026-10-16 12:05:55.322 | *NULL* |
| 4 | David Moreau | actif | david.moreau@email.fr | joint | 2026-10-16 12:05:55.322 | 2026-10-16 12:11:18.285 |
| 4 | David Moreau | **inactif** | david.moreau@email.fr | joint | 2026-10-16 12:11:18.285 | *NULL* |
| 5 | Emma Bernard | inactif | emma.bernard@email.fr | courant | 2026-10-16 12:05:55.322 | 2026-10-16 12:10:35.299 |
| 5 | Emma Bernard | **actif** | emma.bernard@email.fr | courant | 2026-10-16 12:10:35.299 | *NULL* |
| 6 | Frank Petit | cloture | frank.petit@email.fr | courant | 2026-10-16 12:05:55.322 | *NULL* |

La table contient 9 lignes : les 6 versions initiales, plus 3 nouvelles versions pour les comptes modifiés aux étapes B et C. Chaque version remplacée a un `dbt_valid_to` égal au `dbt_valid_from` de la suivante. La version courante a toujours `dbt_valid_to = NULL`.

## 2. Modèle `dim_comptes_historique` (Partie 4.2)

```sql
select compte_id, numero_version, statut, est_version_courante, valide_depuis, valide_jusqu_a, duree_jours
from FINTRACK_DB.DEV_ABRAHAM.DIM_COMPTES_HISTORIQUE
order by compte_id, numero_version;
```

| compte_id | numero_version | statut | est_version_courante | valide_depuis | valide_jusqu_a | duree_jours |
|---|---|---|---|---|---|---|
| 1 | 1 | actif | true | 2026-10-16 12:05:55 | | 0 |
| 2 | 1 | actif | false | 2026-10-16 12:05:55 | 2026-10-16 12:10:35 | 0 |
| 2 | 2 | cloture | true | 2026-10-16 12:10:35 | | 0 |
| 3 | 1 | actif | true | 2026-10-16 12:05:55 | | 0 |
| 4 | 1 | actif | false | 2026-10-16 12:05:55 | 2026-10-16 12:11:18 | 0 |
| 4 | 2 | inactif | true | 2026-10-16 12:11:18 | | 0 |
| 5 | 1 | inactif | false | 2026-10-16 12:05:55 | 2026-10-16 12:10:35 | 0 |
| 5 | 2 | actif | true | 2026-10-16 12:10:35 | | 0 |
| 6 | 1 | cloture | true | 2026-10-16 12:05:55 | | 0 |

`duree_jours` vaut 0 parce que les trois snapshots ont été pris le même jour, à quelques minutes d'intervalle. Pour la version courante, la durée court jusqu'à l'instant de la requête : le modèle est une vue. Les tests associés passent :
- une seule version courante par compte ;
- des versions contiguës, sans chevauchement (`dbt_utils.mutually_exclusive_ranges`) ;
- `version_id` unique.

## 3. Journal des exécutions (hook `on-run-end`), extrait

Chaque commande dbt du protocole a écrit une ligne dans `DEV_ABRAHAM.DBT_RUN_LOG`. En prod, la table est `MARTS.DBT_RUN_LOG`. L'extrait ci-dessous couvre les quatre commandes du protocole ; les runs suivants y ont ajouté leurs propres lignes.

| run_id | started_at (UTC) | completed_at (UTC) | status | nb_models |
|---|---|---|---|---|
| d0a36b72-… (`dbt build`, étape A) | 12:04:23 | 12:08:23 | warn | 13 |
| d338912f-… (`dbt run` incrémental des faits) | 12:08:57 | 12:09:24 | success | 2 |
| 1cc3877f-… (`dbt snapshot`, étape B) | 12:10:27 | 12:10:46 | success | 0 |
| c009e7cc-… (`dbt snapshot`, étape C) | 12:11:09 | 12:11:28 | success | 0 |

Le statut `warn` de ce build venait du test `assert_virements_non_dupliques_dans_transactions`. Ce test signale volontairement les 4 mouvements présents à la fois dans les transactions et dans les virements. Le test `assert_alertes_coherentes_avec_transactions`, ajouté après la revue, produit lui aussi un avertissement. `nb_models` vaut 0 pour `dbt snapshot`, qui n'exécute aucun modèle.
