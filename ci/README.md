# CI/CD GitHub Actions — FinTrack Analytics (dbt + Snowflake)

Ce dossier documente l'intégration continue (CI) et le déploiement continu (CD) du projet dbt
sur GitHub Actions, pour le dépôt **public** `abrahamkoloboe27/fintrack-analytics-intermediaire`
(branche `main`). Ce que la visibilité publique implique (coûts, logs et artefacts lisibles par tous,
protection de branche disponible) : sections 7 et 8.

| Fichier | Rôle |
|---|---|
| `.github/workflows/ci.yml` | CI de chaque Pull Request vers `main` : validation puis build dans un schéma Snowflake éphémère |
| `.github/workflows/cd.yml` | Production : déploiement à chaque push sur `main` (fusion d'une PR), runs planifiés (quotidien, hebdomadaire), lancement manuel ; publication de la documentation dbt sur GitHub Pages |
| `.github/dependabot.yml` | Mises à jour hebdomadaires des actions GitHub (épinglées par SHA) et de dbt (`requirements.txt`) |
| `ci/profiles.yml` | Profil dbt de la CI/CD (targets `ci` et `prod`). Versionné : il ne contient **aucun secret**, uniquement des `env_var()` |
| `macros/supprimer_schema_ci.sql` | Opération qui supprime le schéma CI éphémère (garde-fous : target `ci` et schéma `CI_*` uniquement) |
| `requirements.txt` | Versions figées de dbt-core et dbt-snowflake, identiques au poste local ; les dépendances transitives sont résolues à l'installation |

```
Pull Request vers main ──► ci.yml
   ├─ validation : pip install → dbt deps → dbt parse (targets ci et prod)     [aucun secret]
   └─ build-ci   : dbt build dans FINTRACK_DB.CI_PR_<n> (slim ou complet)
                   → seconde passe incrémentale (MERGE) des modèles incrémentaux
                   → suppression du schéma CI_PR_<n>, même en cas d'échec

Push sur main (fusion) ──► cd.yml : freshness → dbt build state:modified+ et vues de staging en amont,
                                    --full-refresh → artefacts : manifest, résultats, documentation
                                    → si succès : documentation publiée sur GitHub Pages
Chaque jour 05:15 UTC  ──► cd.yml : dbt build --selector daily
Chaque lundi 04:15 UTC ──► cd.yml : dbt build --selector weekly
                                    + dbt build --select +config.materialized:incremental+ --full-refresh
Lancement manuel       ──► cd.yml : sélecteur (tout / daily / weekly / critical) et --full-refresh au choix
```

Documentation dbt de la production (mise à jour après chaque run de production réussi) : https://abrahamkoloboe27.github.io/fintrack-analytics-intermediaire/

---

## 1. Prérequis Snowflake

1. **Scripts Snowflake, dans cet ordre** : `scripts/01` → `02` → **`05_droits_dbt_partie2.sql`**
   (SYSADMIN) → `03` (tables RAW de la Partie 2, table `MARTS.dbt_run_log`). Sans le script 05,
   `FINTRACK_ROLE` ne peut ni exécuter le script 03, ni créer les schémas `DEV_<NOM>` (développement),
   `CI_*` (CI) et `SNAPSHOTS` (production), ni charger les seeds dans `RAW`. Le script `04` ne sert
   qu'au protocole de test du snapshot ; le `06` uniquement si le script `02` a été rejoué (doublons
   dans RAW).
2. Un **utilisateur Snowflake pour GitHub Actions**, avec le rôle `FINTRACK_ROLE`. Cible : un
   utilisateur de service dédié, `FINTRACK_CI`, authentifié par paire de clés (section 2).
   **État actuel** : authentification par mot de passe (secret `SNOWFLAKE_PASSWORD`) avec
   l'utilisateur existant `FINTRACK_USER` ; pas encore d'utilisateur `FINTRACK_CI` ni de paire de
   clés. Migration à faire avant le blocage du mot de passe seul (section 2) : créer `FINTRACK_CI`
   (`TYPE=SERVICE`), poser la clé publique, définir `SNOWFLAKE_USER=FINTRACK_CI` et
   `SNOWFLAKE_PRIVATE_KEY`, puis supprimer `SNOWFLAKE_PASSWORD` (procédure en section 3).

## 2. Authentification : mot de passe aujourd'hui, paire de clés à terme

Snowflake retire progressivement la connexion par mot de passe seul
([calendrier officiel](https://docs.snowflake.com/en/user-guide/security-mfa-rollout)) : la phase 3
(août à octobre 2026, déployée compte par compte) impose un second facteur (MFA) à **tous les
utilisateurs humains** (`TYPE=PERSON` ou type non renseigné) qui se connectent par mot de passe, quel
que soit le client. Un job automatisé ne peut pas fournir ce second facteur. Les comptes d'essai
(trial) et les comptes lecteurs (reader accounts) ne sont pas concernés par ce calendrier.

- **Aujourd'hui** : la CI/CD se connecte avec le mot de passe de `FINTRACK_USER`, l'utilisateur
  personnel du poste local (humain, `TYPE=PERSON`, sans MFA). Cela fonctionne : ce compte semble être
  un compte d'essai, non concerné par ce calendrier. Contreparties :
  - la CI/CD partage l'identité du développeur et son rôle `FINTRACK_ROLE`, qui écrit en production ;
  - **verrouillage** : par défaut, Snowflake verrouille un utilisateur pendant 15 minutes après
    5 échecs de connexion consécutifs, poste local et CI/CD confondus. Après un changement de mot de
    passe, mettre à jour le secret `SNOWFLAKE_PASSWORD` sans attendre : chaque run lancé avec l'ancien
    échoue à l'étape « Tester la connexion Snowflake » et compte comme un échec.
- **Cible : une paire de clés** sur un utilisateur de service dédié, `FINTRACK_CI` (`TYPE=SERVICE` :
  ni mot de passe, ni MFA). À mettre en place avant la conversion du compte en compte payant, ou dès
  que Snowflake annonce une date d'application pour ce compte (migration : section 3). Les workflows
  acceptent les deux méthodes : dès que le secret `SNOWFLAKE_PRIVATE_KEY` existe, le connecteur
  Snowflake utilise la clé et ignore le mot de passe.

Générer la clé (sur votre poste, hors du dépôt : `.gitignore` exclut de toute façon `*.p8`, `*.pem`
et `rsa_key*`) :

```bash
mkdir -p ~/.snowflake && cd ~/.snowflake
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out rsa_key_fintrack_ci.p8 -nocrypt
openssl rsa -in rsa_key_fintrack_ci.p8 -pubout -out rsa_key_fintrack_ci.pub
chmod 600 rsa_key_fintrack_ci.p8
# Clé publique sur une seule ligne, sans les délimiteurs BEGIN/END (pour le SQL ci-dessous) :
grep -v -- '-----' rsa_key_fintrack_ci.pub | tr -d '\n'; echo
```

Créer l'utilisateur de service dans Snowsight (rôles `USERADMIN`, puis `SECURITYADMIN`) :

```sql
use role useradmin;
create user if not exists FINTRACK_CI
    type = service                 -- utilisateur non humain : ni mot de passe, ni MFA
    default_role = FINTRACK_ROLE
    default_warehouse = FINTRACK_WH
    comment = 'CI/CD GitHub Actions du projet dbt FinTrack';
alter user FINTRACK_CI set rsa_public_key = '<clé publique sur une ligne>';

use role securityadmin;
grant role FINTRACK_ROLE to user FINTRACK_CI;
```

Pour une clé chiffrée (plus sûre), remplacer `-nocrypt` par `-v2 aes-256-cbc` et créer aussi le
secret `SNOWFLAKE_PRIVATE_KEY_PASSPHRASE`. Vérification de l'empreinte : `desc user FINTRACK_CI`
(propriété `RSA_PUBLIC_KEY_FP`), à comparer avec
`openssl rsa -pubin -in rsa_key_fintrack_ci.pub -outform DER | openssl dgst -sha256 -binary | openssl enc -base64`.

## 3. Secrets et variables GitHub

Secrets **de dépôt** (Settings > Secrets and variables > Actions). Dépôt public : les environnements
GitHub sont disponibles, mais volontairement non utilisés. Un relecteur obligatoire sur le job de
`cd.yml` bloquerait aussi les runs planifiés (quotidien, hebdomadaire) jusqu'à une approbation
manuelle. Option possible : un environnement `production` sans relecteur, limité à la branche `main`
(règle de déploiement par branche), portant les secrets de production ; le job `build-ci` de la CI,
qui ne les verrait plus, aurait alors besoin de ses propres secrets.

**État actuel** : `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER` (`FINTRACK_USER`) et `SNOWFLAKE_PASSWORD`
sont créés, soit une authentification par mot de passe avec l'utilisateur existant ; pas encore de
`SNOWFLAKE_PRIVATE_KEY` ni d'utilisateur `FINTRACK_CI` (migration ci-dessous). Aucune variable :
valeurs par défaut.

| Nom | Type | Obligatoire | Contenu |
|---|---|---|---|
| `SNOWFLAKE_ACCOUNT` | secret | oui | Identifiant du compte, **le même que dans `~/.dbt/profiles.yml`** (`monorg-moncompte` ou `xy12345.eu-west-1`), sans `.snowflakecomputing.com` |
| `SNOWFLAKE_USER` | secret | oui | `FINTRACK_CI` (paire de clés, section 2) ou, temporairement, votre utilisateur personnel `FINTRACK_USER` (mot de passe) |
| `SNOWFLAKE_PRIVATE_KEY` | secret | oui, ou le mot de passe | Contenu complet du fichier `rsa_key_fintrack_ci.p8` (lignes BEGIN/END comprises) |
| `SNOWFLAKE_PRIVATE_KEY_PASSPHRASE` | secret | si la clé est chiffrée | Phrase de passe de la clé |
| `SNOWFLAKE_PASSWORD` | secret | à défaut de clé | Mot de passe de `FINTRACK_USER` (utilisateur `PERSON`), uniquement tant que le compte accepte le mot de passe seul (compte d'essai, ou avant la phase 3) ; impossible avec `FINTRACK_CI` (`TYPE=SERVICE`) |
| `SNOWFLAKE_ROLE` | variable | non | Défaut `FINTRACK_ROLE` |
| `SNOWFLAKE_WAREHOUSE` | variable | non | Défaut `FINTRACK_WH` |
| `SNOWFLAKE_DATABASE` | variable | non | Défaut `FINTRACK_DB` |

Création avec la CLI GitHub. Sans `--body`, `gh` demande la valeur dans une invite masquée : la
valeur ne passe ni dans l'historique du shell ni à l'écran. Ne jamais écrire un secret en clair dans
une commande.

```bash
REPO=abrahamkoloboe27/fintrack-analytics-intermediaire
gh auth status

gh secret set SNOWFLAKE_ACCOUNT --repo "$REPO"     # saisir l'identifiant du compte
gh secret set SNOWFLAKE_USER --repo "$REPO"        # FINTRACK_CI (clé) ou FINTRACK_USER (mot de passe)
# Configuration actuelle (mot de passe seul, tant que le compte l'accepte) :
gh secret set SNOWFLAKE_PASSWORD --repo "$REPO"
# Configuration cible (paire de clés, section 2) :
# gh secret set SNOWFLAKE_PRIVATE_KEY --repo "$REPO" < ~/.snowflake/rsa_key_fintrack_ci.p8
# gh secret set SNOWFLAKE_PRIVATE_KEY_PASSPHRASE --repo "$REPO"   # clé chiffrée uniquement

gh secret list --repo "$REPO"                      # affiche les noms, jamais les valeurs

# Variables facultatives (valeurs non sensibles), seulement si elles diffèrent des défauts :
# gh variable set SNOWFLAKE_WAREHOUSE --repo "$REPO" --body FINTRACK_WH
```

**Passer à la paire de clés** (dans cet ordre, en dehors des horaires planifiés de la section 7) :

1. Créer `FINTRACK_CI` et sa clé, puis vérifier l'empreinte (section 2).
2. Remplacer les deux secrets l'un après l'autre, sans run entre les deux : dès que
   `SNOWFLAKE_PRIVATE_KEY` existe, le connecteur n'utilise plus le mot de passe.

   ```bash
   gh secret set SNOWFLAKE_PRIVATE_KEY --repo "$REPO" < ~/.snowflake/rsa_key_fintrack_ci.p8
   gh secret set SNOWFLAKE_USER --repo "$REPO"        # saisir FINTRACK_CI
   ```

3. Lancer la CI à la main et attendre un run vert. L'étape « Tester la connexion Snowflake » valide la
   clé, et le build n'écrit que dans un schéma `CI_RUN_<id>` :
   `gh workflow run ci.yml --repo "$REPO" --ref main`.
4. Supprimer le mot de passe : `gh secret delete SNOWFLAKE_PASSWORD --repo "$REPO"`.

## 4. CI : `ci.yml`

Déclencheurs : Pull Request vers `main` (ouverture, nouveau push, réouverture) et lancement manuel
(`gh workflow run ci.yml --ref <branche>`). Un nouveau push sur une PR annule le run en cours de
cette PR ; son nettoyage s'exécute quand même.

**Job `validation`** (check « Validation (dbt parse, sans connexion) » ; aucun secret, aucune
connexion) : installe `requirements.txt`, `dbt deps` (versions figées par `package-lock.yml`), puis
`dbt parse` sur les targets `ci` et `prod` avec des identifiants factices. Il détecte les erreurs
Jinja et YAML et les `ref()` cassés. Il fait aussi échouer la PR à la moindre dépréciation dbt
(`--warn-error-options '{"error": ["Deprecations"]}'`) : le projet n'en contient aucune, et elles
deviennent des erreurs dans les versions suivantes de dbt. Retirer cette option pour revenir à de
simples avertissements. Le job s'exécute sur toutes les PR, y compris celles de Dependabot.

**Job `build-ci`** (check « Build CI (schéma Snowflake éphémère) » ; secrets Snowflake) :

1. Schéma éphémère `FINTRACK_DB.CI_PR_<numéro de PR>` (`CI_RUN_<id>` en lancement manuel) : la macro
   `generate_schema_name` place tous les objets de la target `ci` dans ce seul schéma.
2. **Slim CI** : le job télécharge (`gh run download`, jeton `GITHUB_TOKEN` en lecture seule) le
   `manifest.json` du dernier run réussi de `cd.yml` sur `main`, c'est-à-dire l'état de la production.
   - S'il existe : `dbt build --select state:modified+ --defer --state <manifest>`. Seuls les nœuds
     modifiés par la PR et leurs descendants sont construits et testés. Les parents non modifiés sont
     lus directement dans les schémas de production (`--defer`). Une PR qui ne touche aucun modèle ne
     construit rien. `dbt build` n'exécute un test unitaire qu'avec son modèle : les tests unitaires
     modifiés seuls sont donc lancés en plus par
     `dbt test --select "state:modified,test_type:unit"`.
   - Sinon (aucun déploiement réussi, artefact de plus de 90 jours) : `dbt build` complet (seeds,
     snapshot, modèles, tests unitaires et tests de données) dans le schéma CI.
3. **Seconde passe, incrémentale** : les modèles incrémentaux sont ensuite reconstruits une seconde
   fois, sur les tables que la première passe vient de créer. `is_incremental()` est alors vrai : le
   `MERGE`, le contrôle `on_schema_change` et la branche incrémentale du pre-hook
   `journaliser_watermark` s'exécutent à chaque PR, et non pour la première fois au run quotidien de
   production.
   - build complet : `dbt build --select config.materialized:incremental+` (faits incrémentaux, marts
     en aval et leurs tests) ;
   - slim CI : `dbt build --select "state:modified+,config.materialized:incremental" --defer --state <manifest>`
     (`Nothing to do` si aucun modèle incrémental n'est modifié ni en aval d'un nœud modifié).

   Les tests unitaires, déjà exécutés, sont exclus (`--exclude-resource-type unit_test`). Les
   résultats de cette passe sont écrits dans `target/passe_incrementale/`, pour ne pas écraser ceux
   de la première.
4. Le schéma CI est supprimé puis recréé vide au début du job (au cas où un run précédent aurait été
   interrompu ; les tests unitaires y créent des tables temporaires). Il est supprimé à la fin,
   **même si le build échoue ou si le run est annulé** :
   `dbt run-operation supprimer_schema_ci --target ci`.
5. Artefact `dbt-run-results-ci` (`run_results.json` de chaque passe, 14 jours) et résumé des deux
   passes dans l'onglet du run.

**PR depuis un fork ou ouverte par Dependabot** : par défaut, GitHub ne leur transmet pas les secrets
Actions. Le job `build-ci` est alors **ignoré** (statut « skipped », qui compte comme réussi et ne
bloque pas la PR, même avec la protection de la section 8) avec une notice explicative ; seul
`validation` s'exécute. Pour construire une PR Dependabot dans Snowflake, lancer la CI à la main sur
sa branche : `gh workflow run ci.yml --repo "$REPO" --ref <branche-dependabot>`.

## 5. CD : `cd.yml`

Le job ne s'exécute que sur `main` : un lancement manuel depuis une autre branche est ignoré.
Les runs de production s'exécutent l'un après l'autre (groupe de concurrence `dbt-prod`, avec
`queue: max`) : un run en cours n'est jamais annulé, et les runs suivants attendent leur tour dans
l'ordre d'arrivée (jusqu'à 100 en attente) ; aucun n'est annulé. Un run planifié ou manuel ne peut
donc pas remplacer un déploiement en attente. actionlint 1.7.12 ne connaît pas encore la clé `queue` :
pour valider les workflows en local, `actionlint -ignore 'unexpected key "queue" for "concurrency" section'`.

**Relance d'un run** (« Re-run jobs ») : GitHub réutilise le commit du run d'origine. La relance n'est
acceptée que si ce commit est toujours la tête de `main` ; sinon le run échoue aussitôt, avant toute
connexion à Snowflake, plutôt que de redéployer un code ancien. Lancer alors un nouveau run :
`gh workflow run cd.yml --repo "$REPO" --ref main`.

| Déclencheur | Commande dbt (target `prod`) |
|---|---|
| Push sur `main` (fusion d'une PR) | `dbt build --select "state:modified+ @state:modified,config.materialized:view" --full-refresh --state <manifest du dernier run réussi>`. **Repli** : `dbt build --full-refresh` complet s'il n'existe aucun manifest exploitable (premier déploiement, artefact expiré) ou si le **dernier déploiement sur push n'a pas réussi** |
| Chaque jour, 05:15 UTC | `dbt build --selector daily` (tests des sources, staging, snapshot, dimensions, faits incrémentaux, marts) |
| Chaque lundi, 04:15 UTC | `dbt build --selector weekly` (seeds, `dim_comptes_historique`), puis `dbt build --select +config.materialized:incremental+ --full-refresh` |
| Manuel | `dbt build [--selector daily, weekly ou critical] [--full-refresh]` |

- **Pourquoi `--full-refresh` au déploiement** : les modèles incrémentaux sont configurés avec
  `on_schema_change='fail'`. Un changement de colonnes doit recréer la table ; un changement de logique
  doit retraiter tout l'historique. Les volumes sont faibles, la reconstruction est peu coûteuse.
  Le snapshot `snap_comptes` n'est jamais effacé par `--full-refresh` : son historique est conservé.
- **Pourquoi les vues de staging en amont** (`@state:modified,config.materialized:view` au
  déploiement, préfixe `+` du full refresh hebdomadaire) : ni le `MERGE` (une clé nouvelle présente
  deux fois dans la source est insérée deux fois) ni le `--full-refresh` (CTAS) ne contrôlent
  l'unicité des clés. Ce sont les tests `unique` et `not_null` du staging (et des sources, le lundi)
  qui protègent les faits, à condition de faire partie de la même commande `dbt build` : leur échec
  bloque alors la reconstruction des faits, qui gardent leur version précédente. Ces vues sont
  recréées à l'identique ; aucun seed ni snapshot n'est ajouté (`+state:modified+` les embarquerait).
- **Full refresh hebdomadaire** : il rattrape ce que l'incrémental ne corrige pas : les annulations
  après chargement, quelle que soit leur date (transaction validée puis rejetée, virement exécuté puis
  annulé), et les corrections hors de la fenêtre de recouvrement (lookback).
- **Pas de tests unitaires en production** (`DBT_EXCLUDE_RESOURCE_TYPES=unit_test`, recommandation
  dbt) : leurs données sont figées et déjà validées par la CI. Les tests de données s'exécutent à
  chaque build.
- **Fraîcheur des sources** : `dbt source freshness` s'exécute avant chaque build, avec les seuils de
  `models/staging/_stg_sources.yml` (avertissement à 24 h, erreur à 48 h). Un dépassement **ne bloque
  pas** le déploiement : il produit un avertissement visible sur le run, et `sources.json` est publié.
  Les tables RAW n'ont pas de colonne d'horodatage de chargement : la fraîcheur repose sur la date de
  dernière modification des tables dans Snowflake. Avec les données de démonstration statiques, des
  avertissements sont donc attendus quelques jours après le chargement.
- **Artefacts** (onglet « Summary » du run, ou `gh run download`), **lisibles par tous** sur ce dépôt
  public (section 8) :

| Artefact | Contenu | Conservation |
|---|---|---|
| `dbt-manifest-prod` | `manifest.json` de la production, publié seulement si le build réussit. Référence du slim CI et du prochain déploiement | 90 jours |
| `dbt-run-results-prod` | `run_results.json` (dernière commande dbt du run) et `sources.json` (fraîcheur) | 30 jours |
| `dbt-docs` | `static_index.html` : documentation dbt complète (lineage compris) dans un seul fichier, produite par `dbt docs generate --static` | 30 jours |

- **Documentation en ligne (GitHub Pages)** : après chaque run de production réussi, le job
  `Documentation (GitHub Pages)` publie le même `static_index.html` (renommé `index.html`) sur
  **https://abrahamkoloboe27.github.io/fintrack-analytics-intermediaire/**. Le site reflète donc
  toujours le dernier état réellement déployé ; si le run de production échoue, il n'est pas mis à jour.
  - Activation (déjà faite, une seule fois) : Settings → Pages → Source « GitHub Actions », ou
    `gh api --method POST repos/$REPO/pages -f build_type=workflow`. GitHub crée alors
    l'environnement `github-pages`, limité à la branche `main` : une PR ne peut pas publier.
  - Le job n'a que les permissions `pages: write` et `id-token: write` (jeton OIDC exigé par
    `actions/deploy-pages`) et ne reçoit aucun secret Snowflake.

Télécharger une version précédente de la documentation (artefact `dbt-docs`, 30 jours) :

```bash
RUN_ID=$(gh run list --repo "$REPO" --workflow cd.yml --branch main --status success --limit 1 --json databaseId --jq '.[0].databaseId')
gh run download "$RUN_ID" --repo "$REPO" --name dbt-docs --dir /tmp/dbt-docs
xdg-open /tmp/dbt-docs/static_index.html
```

## 6. Premier déploiement en production

Le premier déploiement **doit reconstruire tout le projet avec `--full-refresh`**. Les tables de la
Partie 1 (par exemple `MARTS.FCT_TRANSACTIONS` avec sa colonne `mois_transaction`) n'ont pas le schéma
attendu, et un run incrémental échouerait (`on_schema_change='fail'`).

1. Snowflake prêt (sections 1 et 2) et secrets créés (section 3), **avant** de pousser les workflows
   sur `main`. S'assurer que `SNOWFLAKE_USER` contient l'utilisateur propriétaire du mot de passe
   stocké dans `SNOWFLAKE_PASSWORD` (aujourd'hui `FINTRACK_USER`), et `SNOWFLAKE_ACCOUNT` le même
   identifiant que `~/.dbt/profiles.yml` ; en cas de doute, ressaisir le secret (`gh secret set`).
   Sinon, la CI de la PR échoue à l'étape « Tester la connexion Snowflake ».
2. Pousser le code sur une **branche** et ouvrir une Pull Request. **Jamais de push direct sur
   `main`** : tant que `main` n'est pas protégée (section 8), un push direct déclenche aussitôt
   `cd.yml`, donc un déploiement en production, sans aucune CI. La CI de la PR construit tout le projet
   dans `CI_PR_<n>` (pas encore de manifest de production, donc build complet). Corriger jusqu'au vert.
3. Fusionner la PR une fois les deux checks verts. Le run `cd.yml` déclenché par le push ne trouve
   aucun déploiement précédent : il exécute automatiquement `dbt build --full-refresh` sur tout le
   projet.
4. Si ce run a échoué (secrets absents à ce moment, script Snowflake manquant...) ou pour repartir de
   zéro, lancer explicitement le déploiement complet :

   ```bash
   gh workflow run cd.yml --repo "$REPO" --ref main -f selector=tout -f full_refresh=true
   gh run watch --repo "$REPO"        # choisir le run « CD » en cours
   ```

5. Vérifier dans Snowsight :

   ```sql
   show schemas in database FINTRACK_DB;          -- STAGING, MARTS, RAW, SNAPSHOTS
   select * from FINTRACK_DB.MARTS.dbt_run_log order by started_at desc limit 5;
   ```

À relancer de la même façon (`full_refresh=true`, `selector=tout`) après une modification globale que
la comparaison d'états ne voit pas : macro `generate_schema_name`, configuration des schémas dans
`dbt_project.yml`, changement de rôle ou de base.

## 7. Planification et coûts

- Les horaires sont en **UTC** et ne s'appliquent qu'à la branche `main`. GitHub peut retarder un run
  planifié en période de forte charge ; les minutes sont décalées de l'heure pile pour limiter ce risque.
  Le run hebdomadaire (04:15) précède le run quotidien du lundi (05:15).
- **Désactivation automatique** : sur un dépôt public, GitHub désactive les workflows planifiés après
  60 jours sans activité dans le dépôt (aucun nouveau commit, par exemple). Les runs quotidien et
  hebdomadaire, et avec eux le contrôle de fraîcheur des sources, s'arrêtent alors. Pour les
  réactiver : `gh workflow enable cd.yml --repo "$REPO"`.
- **GitHub Actions** : sur un dépôt public, les minutes des runners standard (`ubuntu-latest`) sont
  gratuites et le stockage des artefacts n'est pas facturé ; les durées de conservation de la section 5
  s'appliquent toujours. Pour mémoire, un dépôt privé consommerait le quota du compte (sur le plan Free
  à ce jour : 2 000 minutes par mois, minute entamée due par job, et 500 Mo de stockage d'artefacts).
  Ordre de grandeur : 4 à 6 minutes par run de CD (environ 35 runs planifiés par mois) et 5 à 8 minutes
  par push sur une PR (deux jobs). L'installation de dbt est accélérée par le cache pip.
- **Snowflake** : `FINTRACK_WH` (XSMALL) consomme 1 crédit par heure d'activité, facturé à la seconde
  avec 60 secondes minimum à chaque reprise ; il se suspend après 60 secondes d'inactivité (script 01).
  Un run garde l'entrepôt actif quelques minutes, soit quelques centièmes de crédit. Comptez de l'ordre
  de 1 à 3 crédits par mois pour les runs planifiés, plus la CI. Suivi (rôle ayant accès à
  `SNOWFLAKE.ACCOUNT_USAGE`) :

  ```sql
  -- Crédits consommés par jour par l'entrepôt
  select date_trunc('day', start_time) as jour, sum(credits_used) as credits
  from snowflake.account_usage.warehouse_metering_history
  where warehouse_name = 'FINTRACK_WH' and start_time >= dateadd('day', -30, current_timestamp())
  group by 1 order by 1;

  -- Requêtes dbt par run GitHub (query_tag = dbt_fintrack_<target>_<id du run>)
  select query_tag, count(*) as nb_requetes, round(sum(total_elapsed_time) / 1000) as secondes
  from snowflake.account_usage.query_history
  where query_tag like 'dbt_fintrack_%' and start_time >= dateadd('day', -7, current_timestamp())
  group by 1 order by 1;
  ```

- **Réduire les coûts** : commenter le bloc `schedule:` de `cd.yml` quand le projet n'est pas utilisé.
  `gh workflow disable cd.yml` coupe aussi le déploiement au push sur `main`.

## 8. Sécurité

- **Dépôt public** : le code, les logs des runs (conservés 90 jours) et les artefacts (14 à 90 jours,
  dont la documentation `dbt-docs` et le manifest de la production) sont lisibles par tout utilisateur
  GitHub, et la documentation dbt est publiée sur GitHub Pages (catalogue de la production : noms des
  tables et colonnes, descriptions, SQL compilé, nombre de lignes ; aucune donnée). C'est acceptable
  ici : les données sont fictives, GitHub masque la valeur des secrets dans les logs (y compris le
  compte et l'utilisateur affichés par `dbt debug`), et aucun identifiant n'est écrit dans le dépôt ni
  dans la documentation. À reconsidérer avant tout usage avec des données réelles (dépôt privé, pas de
  documentation publiée en artefact ni sur Pages).
- **Aucun secret dans le dépôt** : `ci/profiles.yml` ne contient que des `env_var()`. Le `.gitignore`
  exclut tout autre `profiles.yml` et les fichiers de clés. Les workflows n'affichent que des noms de
  secrets.
- **Actions épinglées** : `actions/checkout`, `actions/setup-python` et `actions/upload-artifact` sont
  référencées par le SHA complet d'un commit, suivi de la version en commentaire, et non par un tag
  `@v7` déplaçable : le code exécuté avec les secrets ne peut pas changer à notre insu. Dependabot
  propose les mises à jour (SHA et commentaire ensemble).
- **Moindre privilège** : jeton GitHub en lecture seule (`contents: read`), plus `actions: read`
  uniquement pour les jobs qui téléchargent le manifest de production. `persist-credentials: false` au
  checkout. Les entrées du lancement manuel passent par des variables d'environnement validées, jamais
  interpolées dans le script.
- **Forks et Dependabot** : déclencheur `pull_request` (et non `pull_request_target`), donc aucun
  secret n'est exposé au code d'un fork. Le manifest de production n'est lu que depuis des runs
  `push`, `schedule` ou `workflow_dispatch` de `main`, que seul un membre du dépôt peut déclencher.
- **Isolation** : la target par défaut de `ci/profiles.yml` est `ci`. Hors target `prod`, tout est
  écrit dans le schéma de la target. `supprimer_schema_ci` refuse toute autre target et tout schéma
  ne commençant pas par `CI_`.
- **Protection de `main`** (recommandée ; réglage GitHub à faire par le propriétaire du dépôt) :
  disponible gratuitement sur ce dépôt public, mais **pas encore activée**. Sans elle, rien n'impose
  une CI verte avant la production : un push direct sur `main`, même par erreur, déclenche aussitôt
  `cd.yml`, donc un déploiement en production. Après le premier run de CI d'une PR (les checks sont
  alors proposés dans la liste), créer un ruleset : Settings > Rules > Rulesets > New ruleset >
  New branch ruleset :
  - *Enforcement status* : Active ; *Bypass list* : vide (sinon l'administrateur peut toujours
    pousser directement sur `main`) ; *Target branches* : la branche par défaut (`main`) ;
  - *Restrict deletions* et *Block force pushes* ;
  - *Require a pull request before merging*, avec 0 approbation (un seul mainteneur) ;
  - *Require status checks to pass*, avec les checks « Validation (dbt parse, sans connexion) » et
    « Build CI (schéma Snowflake éphémère) » (noms des jobs de `ci.yml`). Un job ignoré compte comme
    réussi : les PR de Dependabot, dont le build Snowflake est ignoré, restent fusionnables.

  Équivalent en protection de branche classique (Settings > Branches) : mêmes règles, avec « Do not
  allow bypassing the above settings ». Également gratuits sur un dépôt public : *secret scanning* et
  *push protection* (Settings > Code security).
- **Pistes d'amélioration** :
  - la paire de clés sur l'utilisateur de service `FINTRACK_CI` (sections 2 et 3), à la place du mot
    de passe d'un utilisateur humain ;
  - un rôle Snowflake dédié à la CI : `SELECT` sur les schémas de production (pour `--defer`),
    `CREATE SCHEMA` sur la base, mais aucun droit d'écriture sur la production ;
  - l'authentification sans secret par fédération d'identité (OIDC GitHub vers Snowflake), prise en
    charge par dbt-snowflake (`authenticator: workload_identity`).

## 9. Reproduire la CI en local

```bash
export DBT_PROFILES_DIR="$PWD/ci"
export SNOWFLAKE_ACCOUNT='<identifiant du compte>' SNOWFLAKE_USER='<utilisateur>'
# Mot de passe (configuration actuelle), saisie masquée :
read -rs SNOWFLAKE_PASSWORD && export SNOWFLAKE_PASSWORD
# ou paire de clés (configuration cible) :
# export SNOWFLAKE_PRIVATE_KEY="$(cat ~/.snowflake/rsa_key_fintrack_ci.p8)"
export DBT_CI_SCHEMA=CI_LOCAL_ABRAHAM                      # doit commencer par CI_

# Slim CI contre le manifest de production, puis seconde passe incrémentale
RUN_ID=$(gh run list --workflow cd.yml --branch main --status success --limit 1 --json databaseId --jq '.[0].databaseId')
gh run download "$RUN_ID" --name dbt-manifest-prod --dir /tmp/etat-prod
dbt build --target ci --select state:modified+ --defer --state /tmp/etat-prod
dbt build --target ci --select "state:modified+,config.materialized:incremental" --defer \
  --state /tmp/etat-prod --exclude-resource-type unit_test --target-path target/passe_incrementale

dbt run-operation supprimer_schema_ci --target ci          # nettoyage
```

## 10. Dépannage

```bash
gh run list --repo "$REPO" --limit 10                # derniers runs CI et CD
gh run view <id du run> --repo "$REPO" --log-failed  # logs des seules étapes en échec
```

| Symptôme | Cause et solution |
|---|---|
| Notice « Build CI ignoré » | Secrets indisponibles : PR de fork ou de Dependabot (normal), ou secrets non créés (section 3) |
| `Secrets Snowflake manquants` | Créer les secrets listés dans le message (section 3) |
| `Incorrect username or password` | Valeur d'un secret erronée : ressaisir `SNOWFLAKE_USER`, `SNOWFLAKE_PASSWORD` et `SNOWFLAKE_ACCOUNT` (section 3). Attention : 5 échecs consécutifs verrouillent l'utilisateur pendant 15 minutes, poste local compris (section 2) |
| Utilisateur verrouillé (`User temporarily locked`) | Trop d'échecs de connexion : attendre 15 minutes, ou débloquer avec un rôle administrateur (`alter user <utilisateur> set mins_to_unlock = 0;`), puis corriger le secret |
| MFA exigée, authentification à un facteur refusée | Snowflake impose désormais un second facteur à cet utilisateur humain : passer à la paire de clés (sections 2 et 3) |
| `JWT token is invalid` | Clé publique absente ou différente, ou `SNOWFLAKE_USER` qui ne désigne pas l'utilisateur de la clé : comparer les empreintes (section 2) |
| `Relance d'un run ancien` | Relance (« Re-run ») d'un run dont le commit n'est plus la tête de `main` : lancer un nouveau run (`gh workflow run cd.yml --repo "$REPO" --ref main`) |
| Plus aucun run planifié | Workflows planifiés désactivés après 60 jours sans activité (section 7) : `gh workflow enable cd.yml --repo "$REPO"` |
| `Insufficient privileges` à la création d'un schéma | Script `scripts/05_droits_dbt_partie2.sql` non exécuté (section 1) |
| `Env var required but not provided: 'DBT_CI_SCHEMA'` | Profil CI utilisé sans la variable `DBT_CI_SCHEMA` (section 9) |
| `Nothing to do` dans le build | Slim CI, seconde passe ou déploiement sans nœud concerné : normal |
| Avertissement de fraîcheur des sources | Tables RAW non rechargées depuis plus de 24 ou 48 h : non bloquant (section 5) |
| Schémas `CI_*` orphelins | Run interrompu brutalement : `show schemas like 'CI_%' in database FINTRACK_DB;` puis `drop schema FINTRACK_DB.CI_PR_<n> cascade;` |
| Modèle supprimé du projet mais toujours présent en production | La CD ne supprime pas les objets orphelins : `drop table` (ou `drop view`) manuel |
