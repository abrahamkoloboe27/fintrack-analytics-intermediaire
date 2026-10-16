# Livrables — FinTrack Analytics, Partie 2

| Livrable attendu (brief) | Fichier |
|---|---|
| 1. Projet dbt complet et fonctionnel | le dépôt (modèles, snapshots, macros, tests, seeds, exposures, CI/CD dans `.github/` et `ci/`) |
| 2. Capture du lineage dbt docs | [`lineage_dbt_docs.png`](lineage_dbt_docs.png) |
| 3. Preuve d'historisation (snapshot) | [`preuve_historisation.md`](preuve_historisation.md) |
| 4. Rapport (20-25 lignes) | [`rapport.md`](rapport.md) |

Documentation dbt de la production, publiée par la CD sur GitHub Pages : https://abrahamkoloboe27.github.io/fintrack-analytics-intermediaire/
(vue « Lineage Graph » : bouton en bas à droite de la page).

## Capture du lineage

`dbt docs generate --static`, vue « Lineage Graph » du projet complet. Les tests singuliers et les tests unitaires sont masqués pour la lisibilité (`--exclude test_type:singular file:_fct_schema.yml`). La chaîne visible :
- les 6 sources RAW et les 2 seeds (`seuils_alerte`, `mapping_groupes`) ;
- le snapshot `snap_comptes` ;
- les 6 modèles de staging, dont `stg_virements` et `stg_alertes` ;
- `int_transactions_enrichies` ;
- les faits incrémentaux `fct_transactions` et `fct_virements` ;
- les dimensions, dont `dim_comptes_historique`, et les marts ;
- l'analyse `retention_mensuelle` ;
- les exposures « Suivi budgétaire client » et « Synthèse mensuelle ».

## Validation en dev (schéma `DEV_ABRAHAM`, 16/10/2026)

**`dbt build` complet : `PASS=203 WARN=2 ERROR=0 SKIP=0`.** Il couvre 207 nœuds : 13 modèles, 2 seeds, 1 snapshot, 13 tests de sources, 4 tests unitaires et les tests de données. Les deux avertissements sont attendus. Ils signalent des incohérences des données de cours, sans les masquer :
- `assert_virements_non_dupliques_dans_transactions` : les transactions 40 à 43 reprennent les virements 1 à 4 ;
- `assert_alertes_coherentes_avec_transactions` : les alertes 2, 4, 5 et 6 annoncent une dépense que les transactions validées ne montrent pas.

**Volumes.** Les faits comptent 100 transactions validées et 16 mouvements de virement (8 virements exécutés × 2). `mart_budget_vs_reel` compte 74 lignes et `mart_solde_mensuel` 20. Ces chiffres ont été recalculés à la main depuis RAW.

**Run incrémental.** Le pre-hook a journalisé le watermark `2024-06-22 10:00:00`, puis le `merge` n'a retraité que les lignes de la fenêtre de 3 jours : transactions 67, 68 et 102, et les deux mouvements du virement 10.

**Snapshot.** Le protocole du script 04 donne 9 versions ; détail dans [`preuve_historisation.md`](preuve_historisation.md).

**Fraîcheur.** `dbt source freshness` passe pour `raw_transactions` et `raw_virements` (seuils : avertissement à 24 h, erreur à 48 h).

**Journal des runs.** Le hook `on-run-end` a écrit une ligne par commande dans `dbt_run_log`.

Le test singulier `tests/assert_solde_mensuel_positif.sql` de la Partie 1 a été converti en test dbt-expectations, comme le demande la Partie 6.2. C'est le test `mart_solde_mensuel_epargne_solde_cumule_positif` dans `models/marts/_marts_schema.yml`.
