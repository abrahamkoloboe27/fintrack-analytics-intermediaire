{#
  ============================================================
  PAGE D'ACCUEIL DU SITE dbt docs (Partie 9.3 — bonus)
  ============================================================
  Le doc block nommé __overview__ remplace la page d'accueil par défaut
  du site produit par `dbt docs generate` puis `dbt docs serve`.

  - Les liens « #!/model/model.fintrack_analytics.<modèle> » ouvrent la
    page du nœud dans le site (préfixe = `name:` de dbt_project.yml).
  - Le contenu d'un doc block est rendu par Jinja : les exemples qui
    contiennent des balises Jinja sont protégés par un bloc raw.
  - Les descriptions de colonnes réutilisables sont dans docs/doc_blocks.md.
  ============================================================
#}

{% docs __overview__ %}
# FinTrack Analytics — pipeline dbt (Partie 2)

Documentation du projet dbt **FinTrack Analytics** (dbt-core 1.12 + Snowflake). Chaque modèle, source, seed, snapshot, test, macro, analyse et exposure possède sa page ; le bouton de **lignage** (en bas à droite) affiche la chaîne complète *sources RAW → staging → intermediate → marts → exposures*.

## Contexte

FinTrack est une application de gestion budgétaire : ses clients suivent leurs comptes (courant, épargne, joint), leurs transactions, leurs virements internes et leurs budgets mensuels par catégorie. Six mois après la première version, la base d'utilisateurs a triplé et le volume dépasse 50 000 transactions par mois. Cette Partie 2 fait passer la pipeline au niveau supérieur :

| Besoin exprimé par la direction data | Réponse apportée dans le projet |
|---|---|
| Les runs reconstruisent tout et deviennent lents | Faits **incrémentaux** `fct_transactions` et `fct_virements` (stratégie `merge`) |
| Le support veut l'historique des changements de statut des comptes | **Snapshot SCD Type 2** `snap_comptes` et modèle `dim_comptes_historique` |
| Les mêmes patterns SQL sont copiés-collés partout | **Macros Jinja** : `generer_periode`, `convertir_centimes`, `generate_schema_name`… |
| Les tests sont basiques et rien n'alerte | Packages **dbt_utils** et **dbt_expectations**, test générique `taux_null`, tests unitaires, fraîcheur des sources |
| Les exécutions ne sont pas tracées | **Hooks** : journal des runs (`dbt_run_log`) et des watermarks incrémentaux (`dbt_watermark_log`) |
| On ignore qui consomme les données | **Exposures** : dashboard Metabase et rapport mensuel automatisé |
| La production doit être protégée | **Multi-environnement** dev / ci / prod et **CI/CD GitHub Actions** |

## Architecture

### Résumé du lignage

Les jointures de référence (vers `stg_comptes` et `stg_categories`) sont omises ; le graphe complet est dans le lignage du site.

```text
RAW (sources)         STAGING (vues)       INTERMEDIATE / MARTS
-------------         --------------       --------------------
raw_comptes ────────► stg_comptes ───────► dim_comptes
   └──► snap_comptes (snapshot SCD2) ────► dim_comptes_historique
raw_categories ─────► stg_categories ────► dim_categories  ◄── seed mapping_groupes
raw_transactions ───► stg_transactions ──► int_transactions_enrichies ──► fct_transactions
raw_virements ──────► stg_virements ─────► fct_virements
raw_budgets ────────► stg_budgets ───────► mart_budget_vs_reel  ◄── fct_transactions
raw_alertes ────────► stg_alertes  ◄── seed seuils_alerte

mart_solde_mensuel                       ◄── fct_transactions + fct_virements + dim_comptes
« Suivi budgétaire client » (dashboard)  ◄── mart_budget_vs_reel + dim_comptes
« Synthèse mensuelle » (rapport)         ◄── mart_solde_mensuel + fct_transactions + dim_categories
```

### Couches

| Couche | Dossier | Matérialisation | Schéma en prod | Rôle |
|---|---|---|---|---|
| Sources | `models/staging/_stg_sources.yml` | tables existantes | `RAW` | 6 tables brutes, en lecture seule ; fraîcheur contrôlée |
| Seeds | `seeds/` | table (CSV versionné) | `RAW` | Référentiels `mapping_groupes` et `seuils_alerte` |
| Staging | `models/staging/` | vue | `STAGING` | Un modèle par source : renommage, typage, nettoyage |
| Intermediate | `models/intermediate/` | éphémère (CTE injectée) | aucun | Enrichissement réutilisable des transactions |
| Marts | `models/marts/` | table, incrémental ou vue | `MARTS` | Dimensions, faits et agrégats consommés par la BI |
| Snapshots | `snapshots/` | table SCD2 | `SNAPSHOTS` | Historique des comptes |

### Modèles de la couche marts

| Modèle | Matérialisation | Grain | Tags |
|---|---|---|---|
| [dim_comptes](#!/model/model.fintrack_analytics.dim_comptes) | table | 1 ligne par compte | `daily` |
| [dim_categories](#!/model/model.fintrack_analytics.dim_categories) | table | 1 ligne par catégorie, avec ordre d'affichage et priorité dashboard | `daily` |
| [dim_comptes_historique](#!/model/model.fintrack_analytics.dim_comptes_historique) | vue | 1 ligne par version d'un compte | `weekly` |
| [fct_transactions](#!/model/model.fintrack_analytics.fct_transactions) | incrémental (`merge`) | 1 ligne par transaction validée | `daily`, `critical` |
| [fct_virements](#!/model/model.fintrack_analytics.fct_virements) | incrémental (`merge`) | 2 lignes par virement exécuté (`sortant` et `entrant`) | `daily`, `critical` |
| [mart_budget_vs_reel](#!/model/model.fintrack_analytics.mart_budget_vs_reel) | table | compte × catégorie × période | `daily` |
| [mart_solde_mensuel](#!/model/model.fintrack_analytics.mart_solde_mensuel) | table | compte × période (seulement les mois avec au moins un mouvement) | `daily`, `critical` |

## Environnements dev / ci / prod

La macro `generate_schema_name` décide du schéma de chaque objet selon la target :

| Target | Où sont créés les objets | Utilisation |
|---|---|---|
| `dev` | tout dans le schéma personnel de la target (ex. `DEV_ABRAHAM`) | développement local |
| `ci` | tout dans un schéma éphémère `CI_PR_<numéro de PR>` (`CI_RUN_<id>` en lancement manuel), supprimé en fin de job | validation des pull requests |
| `prod` | schéma personnalisé utilisé tel quel : `STAGING`, `MARTS`, `SNAPSHOTS`, `RAW` (seeds) | jobs de la CD GitHub Actions |

Hors production, aucun objet de production ne peut être écrasé : les modèles lisent les sources partagées de `RAW` mais n'écrivent que dans leur propre schéma. En pratique, seule la CD lance `--target prod`, avec des identifiants fournis par des secrets GitHub.

## Stratégies de chargement

### Faits incrémentaux

| | `fct_transactions` | `fct_virements` |
|---|---|---|
| Stratégie | `merge` sur `transaction_id` | `merge` sur `mouvement_id` (clé de substitution de `virement_id` + `sens`) |
| Colonne marqueur | `date_transaction` | `date_virement` |
| Fenêtre de recouvrement (lookback) | variable `lookback_jours_transactions` (3 jours par défaut) | variable `lookback_jours_virements` (3 jours par défaut) |
| Filtre métier | statut `validee` | statut `execute` |

À chaque run incrémental, le modèle ne relit, parmi les lignes qui passent le filtre métier, que :

1. les lignes dont la date est postérieure ou égale à « date maximale déjà chargée moins N jours », ce qui rattrape les retards et les corrections récentes ;
2. **plus** toute ligne absente de la table cible, quelle que soit sa date (anti-jointure sur `transaction_id` / `virement_id`) : une transaction passée de `en_attente` à `validee` plusieurs semaines plus tard est donc bien insérée.

Le `merge` met à jour les lignes déjà présentes au lieu de les dupliquer, `date_chargement` horodate le dernier traitement et `on_schema_change: fail` impose un `--full-refresh` délibéré si les colonnes changent. Le pre-hook `journaliser_watermark` consigne la date maximale déjà traitée avant chaque run incrémental (table `dbt_watermark_log`).

Ni le `merge` (une clé nouvelle présente deux fois dans la source est insérée deux fois) ni le `--full-refresh` ne contrôlent l'unicité des clés : ce sont les tests `unique` et `not_null` des modèles de staging qui protègent les faits, à condition de faire partie de la même commande `dbt build`, où leur échec bloque les modèles en aval. C'est pourquoi les commandes de la CD qui reconstruisent les faits sélectionnent aussi les vues de staging en amont et leurs tests (voir « CI/CD »).

**Limite assumée** : une annulation après chargement (`validee` → `rejetee`, `execute` → `annule`), quelle que soit sa date, ainsi que la correction d'une ligne déjà chargée hors de la fenêtre, ne sont pas propagées par l'incrémental : la ligne annulée sort du flux filtré sur le statut et le `merge` ne supprime jamais rien (de même pour une ligne supprimée de RAW). Le job hebdomadaire de la CD (lundi 04:15 UTC) reconstruit les modèles incrémentaux avec `--full-refresh`, soit au plus 7 jours d'écart.

### `mart_solde_mensuel` en table

Le solde cumulé dépend de tout l'historique du compte (somme cumulée depuis l'origine) : un incrémental devrait recalculer tous les mois postérieurs à chaque correction. L'agrégat est petit (comptes × mois) et lu souvent par les dashboards : une table reconstruite à chaque run est plus simple, plus sûre et peu coûteuse.

Grain : une ligne par compte et par mois **ayant au moins un mouvement**. Pour un mois sans mouvement, le solde de fin de mois d'un compte est le `solde_cumule` de sa dernière période antérieure ; un compte sans aucun mouvement (le compte 6 des données d'exemple) n'y figure pas, son solde reste son `solde_initial`.

### Snapshot SCD Type 2

[snap_comptes](#!/snapshot/snapshot.fintrack_analytics.snap_comptes) historise `raw_comptes` avec la stratégie **check** sur `statut`, `email` et `type_compte` (la source n'a pas de colonne `updated_at` fiable) et `hard_deletes: invalidate` (la version courante d'un compte disparu de la source est fermée). Chaque changement ferme la version courante (`dbt_valid_to`) et en ouvre une nouvelle (`dbt_valid_from`).

[dim_comptes_historique](#!/model/model.fintrack_analytics.dim_comptes_historique) expose cet historique avec `est_version_courante`, `numero_version` et `duree_jours` ; cette durée est calculée au moment de la requête, d'où la matérialisation en vue. Le protocole de test est décrit dans `scripts/04_snapshot_updates.sql` : snapshot initial, puis mises à jour des étapes B et C, chacune suivie d'un `dbt snapshot`.

## Macros

| Macro | Rôle |
|---|---|
| `generate_schema_name` | Choisit le schéma de chaque objet selon la target (voir ci-dessus) |
| `generer_periode(colonne_date)` | Expression `to_char(..., 'YYYY-MM')` qui produit la clé mensuelle `periode` |
| `convertir_centimes(colonne)` | Convertit un montant en euros en centimes entiers |
| test générique `taux_null` | Échoue si le pourcentage de valeurs nulles d'une colonne dépasse `seuil_pct` |
| `journaliser_fin_run(results)` | Hook `on-run-end` : une ligne par exécution dans `dbt_run_log` (statut, nombre de modèles) |
| `journaliser_watermark(colonne)` | Pre-hook de `fct_transactions` : journalise le watermark dans `dbt_watermark_log` |
| `supprimer_schema_ci()` | `run-operation` de nettoyage du schéma CI (refuse toute target autre que `ci`) |

Exemple d'appel dans un modèle : `{% raw %}{{ generer_periode('t.date_transaction') }} as periode{% endraw %}`.

## Tests et qualité des données

- **Tests génériques natifs** : `unique`, `not_null`, `accepted_values`, `relationships`, écrits avec la syntaxe dbt ≥ 1.10 (`data_tests:` et `arguments:`).
- **dbt_utils** : `expression_is_true` (signe cohérent avec le type d'opération, `depassement` cohérent avec `ecart`…), `unique_combination_of_columns` (grain des marts), `mutually_exclusive_ranges` (versions d'un compte sans chevauchement).
- **dbt_expectations** : montants strictement positifs, dates de transaction non futures, format de `periode`, solde cumulé des comptes épargne jamais négatif, une seule version courante par compte.
- **Test générique maison** `taux_null` : au plus 10 % de `motif` vides sur les virements.
- **Tests singuliers** (`tests/`) : virements équilibrés (un mouvement sortant et un entrant, de somme nulle) ; transactions qui dupliquent un virement (sévérité `warn`) ; alertes dont le montant ou le seuil n'est pas confirmé par les transactions validées (sévérité `warn`).
- **Tests unitaires** (`unit_tests`) : logique incrémentale des deux faits (fenêtre de recouvrement, validation ou exécution tardive), conversion en centimes et éclatement de chaque virement en deux mouvements.
- **Tests des sources** : clé `id` unique et non nulle sur les six tables RAW, et au moins une ligne dans `raw_comptes`. Quand ils font partie du même `dbt build` (run quotidien, build complet), ils s'exécutent avant les vues de staging et le snapshot `snap_comptes`, qu'ils sautent en cas d'échec : une table `raw_comptes` vide ou un compte en double ne fausse alors pas l'historique du snapshot (une lecture partielle n'est pas détectée, et `dbt snapshot` seul ne lance aucun test).
- **Fraîcheur des sources** : `raw_transactions` et `raw_virements` passent en avertissement après 24 h et en erreur après 48 h sans mise à jour (contrôle exécuté en production par la CD).

**Anomalies connues des données d'exemple** (signalées par des tests en `warn` plutôt que corrigées en silence) :

- **Virements saisis aussi comme transactions** : quatre transactions reprennent des virements déjà présents dans `raw_virements`, si bien que `mart_solde_mensuel` compte ces mouvements deux fois. Les transactions 41 à 43 (crédits de 300 € sur le compte 3) correspondent aux virements 1 à 3 : le solde du compte 3 est surévalué. La transaction 40 (débit de 500 € sur le compte 4) correspond au virement 4 : le solde du compte 4 est sous-évalué. Le test `assert_virements_non_dupliques_dans_transactions` signale ces 4 lignes plutôt que de supprimer des données en silence.
- **Alertes incohérentes avec les transactions** : quatre des six alertes de `raw_alertes` (alertes 2, 4, 5 et 6, toutes de type `depassement_80`) annoncent un `montant_reel` supérieur aux débits validés du même compte, de la même catégorie et du même mois, datés jusqu'à `date_generation` : par exemple 82,30 € pour l'alerte 2 contre 52,30 € débités, soit 52,3 % du budget pour un seuil de 80 %. Aucune des quatre n'atteint réellement son seuil, et aucune transaction en attente ou rejetée n'explique l'écart : l'incohérence vient de la source. Le test `assert_alertes_coherentes_avec_transactions` signale ces 4 alertes ; le test `expression_is_true` de `stg_alertes` (`taux_consommation_pct >= seuil_pct`) ne compare une alerte qu'à ses propres montants et ne peut pas détecter cette incohérence. `stg_alertes` reproduit fidèlement la source et n'alimente aujourd'hui aucun mart ni aucune exposure.

Sur ces données, `dbt build` se termine donc avec 2 avertissements (`WARN=2`, 4 lignes pour chacun de ces deux tests) et aucune erreur.

## Tags et sélecteurs

Les tags sont posés dans `dbt_project.yml` (dossiers, seeds, snapshots), dans `_stg_sources.yml` (source `fintrack_raw`) et dans la configuration des marts ; `selectors.yml` leur donne un nom réutilisable :

| Sélecteur | Contenu | Planification dans la CD |
|---|---|---|
| `daily` | tests des sources, staging, snapshot des comptes, dimensions, faits et marts quotidiens | chaque jour à 05:15 UTC |
| `weekly` | seeds, `dim_comptes_historique` | chaque lundi à 04:15 UTC, suivi de la reconstruction complète des incrémentaux (voir « CI/CD ») |
| `critical` | `fct_transactions`, `fct_virements`, `mart_solde_mensuel`, avec les vues de staging en amont (`stg_transactions`, `stg_comptes`, `stg_categories`, `stg_virements`) et leurs tests | à la demande (lancement manuel), pour une relance prioritaire après incident |

```bash
dbt ls --selector critical      # liste ce qui serait exécuté, sans rien lancer
dbt build --selector daily      # équivalent de : dbt build -s tag:daily
dbt build -s +tag:critical      # nœuds critiques et tout leur amont
```

## Exposures et analyses

- [Suivi budgétaire client](#!/exposure/exposure.fintrack_analytics.suivi_budgetaire_client) : dashboard Metabase des conseillers clientèle, alimenté par `mart_budget_vs_reel` et `dim_comptes`.
- [Synthèse mensuelle](#!/exposure/exposure.fintrack_analytics.synthese_mensuelle) : rapport automatisé envoyé chaque mois, alimenté par `mart_solde_mensuel`, `fct_transactions` et `dim_categories`.
- `dbt build -s +exposure:suivi_budgetaire_client` reconstruit et teste tout ce qui alimente le dashboard.
- L'analyse [retention_mensuelle](#!/analysis/analysis.fintrack_analytics.retention_mensuelle) calcule le taux de rétention mensuel des comptes actifs, avec une vue par cohortes : `dbt show -s retention_mensuelle` l'exécute, `dbt compile -s retention_mensuelle` écrit son SQL dans `target/compiled/`.

## CI/CD (GitHub Actions)

- **CI** (`.github/workflows/ci.yml`, à chaque pull request vers `main`) : un job `validation` (`dbt deps` et `dbt parse`, sans secret), puis un job `build-ci` qui construit et teste le projet dans un schéma éphémère `CI_PR_<n>`, en « slim CI » (`state:modified+` et `--defer` vers le manifest de production) quand un manifest de prod est disponible ; une seconde passe reconstruit ensuite les modèles incrémentaux concernés sur les tables que la première vient de créer, pour exécuter à chaque pull request le chemin incrémental (`merge`, contrôle `on_schema_change`, pre-hook `journaliser_watermark`), avant la suppression du schéma (`dbt run-operation supprimer_schema_ci`).
- **CD** (`.github/workflows/cd.yml`) : à chaque push sur `main`, déploiement en production des nœuds modifiés, de leurs descendants et des vues de staging en amont (avec leurs tests), reconstruits en `--full-refresh` (tout le projet au premier déploiement) ; runs planifiés quotidien (05:15 UTC, `--selector daily`) et hebdomadaire (lundi 04:15 UTC : `--selector weekly`, puis `--select +config.materialized:incremental+ --full-refresh`, soit les modèles incrémentaux, leurs descendants et leur amont de staging, tests des vues de staging et des sources compris) ; contrôle `dbt source freshness` (non bloquant) ; tests unitaires réservés à la CI ; génération de cette documentation (`dbt docs generate --static`), publiée en artefact avec le manifest de production réutilisé par le slim CI.
- **Authentification Snowflake** : aujourd'hui, la CI et la CD se connectent avec l'utilisateur existant `FINTRACK_USER` (utilisateur humain, rôle `FINTRACK_ROLE`) et son mot de passe, via trois secrets du dépôt : `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER` et `SNOWFLAKE_PASSWORD`. Cible documentée, pas encore en place : l'utilisateur de service `FINTRACK_CI` (dans `SNOWFLAKE_USER`), authentifié par paire de clés (secret `SNOWFLAKE_PRIVATE_KEY`, plus `SNOWFLAKE_PRIVATE_KEY_PASSPHRASE` si la clé est chiffrée), après quoi `SNOWFLAKE_PASSWORD` est supprimé ; migration à faire avant que Snowflake ne refuse le mot de passe seul sur ce compte. Dès que `SNOWFLAKE_PRIVATE_KEY` est renseigné, le connecteur utilise la clé et ignore le mot de passe. `ci/profiles.yml` ne contient que des appels à `env_var`.
- **Dépôt public** : les logs des runs et les artefacts (documentation et manifest de production compris) sont visibles par tout utilisateur GitHub ; les secrets restent masqués et les données sont fictives. GitHub désactive les workflows planifiés d'un dépôt public après 60 jours sans activité (`gh workflow enable cd.yml` pour les réactiver).
- **Protection de `main`** (recommandée ; réglage GitHub à faire par le propriétaire du dépôt) : pull request obligatoire, checks « Validation (dbt parse, sans connexion) » et « Build CI (schéma Snowflake éphémère) » requis, sans contournement possible pour les administrateurs. Tant qu'elle n'est pas en place, rien n'impose une CI verte avant la production : un push direct sur `main` déclenche le déploiement.

Mode d'emploi complet : `ci/README.md`.

## Démarrage rapide

Une seule fois :

- **Snowflake** : scripts `01` → `02` → `05` (rôle `SYSADMIN`) → `03` ; `04` uniquement pendant le protocole snapshot ; `06` uniquement si `02` a été rejoué. Le script `05` donne notamment à `FINTRACK_ROLE` le droit de créer le schéma `DEV_<NOM>` : sans lui, le premier `dbt seed` échoue (« Insufficient privileges »).
- **Profil dbt** : copier `profiles.yml.example` vers `~/.dbt/profiles.yml`, puis y renseigner ses identifiants et son schéma personnel `DEV_<NOM>` (target `dev`).

Puis :

```bash
dbt deps                                        # dbt_utils, dbt_expectations (+ dbt_date)
dbt debug                                       # teste la connexion (target dev)
dbt seed                                        # charge les référentiels
dbt snapshot                                    # état initial du SCD2
dbt build                                       # modèles + tests dans votre schéma de dev
dbt build -s fct_transactions --full-refresh    # reconstruit un incrémental de zéro
dbt build -s fct_transactions --vars '{lookback_jours_transactions: 7}'
dbt source freshness                            # fraîcheur des sources
dbt docs generate && dbt docs serve             # ce site, en local
```

## Conventions

- **Nommage** : `stg_` (un modèle par source), `int_` (intermédiaire), `dim_` et `fct_` (dimensions et faits), `mart_` (agrégats métier), `snap_` (snapshots) ; modèles, colonnes et commentaires en français, en snake_case.
- **Grain mensuel** : `periode` (`YYYY-MM`), accompagnée de `mois` (date du premier jour du mois) quand la BI en a besoin.
- **Montants** : en euros ; `montant_signe` est positif pour un flux entrant et négatif pour un flux sortant ; les colonnes `_centimes` sont des entiers.
- **Audit** : `date_chargement` (UTC) sur les tables de faits.
- **Doc blocks** (`docs/doc_blocks.md`) pour les colonnes communes, insérés avec `{% raw %}{{ doc('col_periode') }}{% endraw %}` : `col_periode`, `col_montant_signe`, `col_montant_centimes`, `col_date_chargement`, `col_compte_id`, `col_statut_compte`.
- **Documentation recopiée dans Snowflake** : `persist_docs` écrit les descriptions (doc blocks compris) en commentaires Snowflake sur les tables, vues et colonnes, visibles dans Snowsight et dans Metabase sans ouvrir ce site.

## Jeu de données de référence

Après les scripts `01`, `02`, `05` et `03` (et `06` pour dédoublonner RAW si le script `02` a été rejoué) : 6 comptes, 12 catégories, 102 transactions (dont 100 validées), 10 virements (dont 8 exécutés, soit 16 lignes dans `fct_virements`), 50 budgets et 6 alertes ; côté seeds, 6 groupes de catégories et 3 seuils d'alerte.
{% enddocs %}
