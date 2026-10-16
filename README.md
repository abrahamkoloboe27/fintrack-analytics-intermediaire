# Projet Intermédiaire — Snowflake + dbt : FinTrack Analytics (Partie 2)

## Contexte du projet

**Durée estimée :** 5 à 7 jours  
**Niveau :** Intermédiaire  
**Prérequis :** Avoir complété le projet débutant FinTrack Analytics (Partie 1), ou disposer d'un compte Snowflake fonctionnel. Les scripts SQL de rattrapage sont fournis dans `scripts/`.

---

### Scénario

Six mois ont passé depuis votre première mission chez **FinTrack Analytics**. L'application a gagné en popularité : la base d'utilisateurs a triplé, le volume de transactions dépasse les 50 000 lignes par mois, et l'équipe produit demande de nouveaux indicateurs.

Le directeur data vous convoque :

> « Notre pipeline dbt fonctionne, mais il ne tient plus la route. Les `dbt run` prennent de plus en plus de temps parce qu'on reconstruit tout à chaque exécution. On a aussi besoin de tracer l'historique des changements de statut des comptes — le support client nous le demande chaque semaine. Et il faut industrialiser : les mêmes patterns SQL se répètent partout, nos tests sont basiques, et rien ne nous alerte quand la qualité des données se dégrade. Je compte sur vous pour faire passer la pipeline au niveau supérieur. »

### Objectifs pédagogiques

À l'issue de ce projet, vous serez capable de :

1. Implémenter des modèles incrémentaux pour optimiser les temps d'exécution
2. Mettre en place des snapshots dbt (SCD Type 2) pour historiser les changements
3. Écrire des macros Jinja réutilisables et les intégrer dans vos modèles
4. Utiliser les seeds pour gérer des données de référence
5. Exploiter les packages dbt-utils et dbt-expectations pour des tests avancés
6. Configurer des hooks pre/post-run
7. Déclarer des exposures pour documenter les consommateurs aval
8. Structurer un projet dbt multi-environnement (dev / prod)

---

## Contenu du dossier

```
fintrack-analytics-intermediaire/
│
├── README.md                     ← Ce fichier (briefing du projet)
│
├── dbt_project.yml               ← Configuration dbt (matérialisations pré-configurées)
├── packages.yml                  ← Packages dbt (dbt-utils installé, dbt-expectations à ajouter)
├── profiles.yml.example          ← Template de connexion Snowflake (à copier vers ~/.dbt/)
│
├── models/
│   ├── staging/                  ← Modèles staging de la Partie 1 (déjà écrits)
│   │   ├── _stg_sources.yml     ← Sources déclarées (4 tables Partie 1 + 2 nouvelles)
│   │   ├── _stg_schema.yml      ← Tests et documentation des modèles staging
│   │   ├── stg_comptes.sql
│   │   ├── stg_transactions.sql
│   │   ├── stg_categories.sql
│   │   └── stg_budgets.sql
│   ├── intermediate/
│   │   └── int_transactions_enrichies.sql   ← Déjà écrit
│   └── marts/
│       ├── dim_comptes.sql                  ← Déjà écrit
│       ├── dim_categories.sql               ← Déjà écrit
│       ├── fct_transactions.sql             ← À CONVERTIR en incrémental
│       ├── mart_solde_mensuel.sql           ← À ADAPTER (intégrer les virements)
│       └── mart_budget_vs_reel.sql          ← Déjà écrit
│
├── seeds/
│   ├── seuils_alerte.csv         ← Seuils de déclenchement des alertes
│   └── mapping_groupes.csv       ← Métadonnées des groupes de catégories
│
├── snapshots/                    ← À CRÉER (snapshot raw_comptes)
├── macros/                       ← À CRÉER (macros Jinja)
├── tests/
│   └── assert_solde_mensuel_positif.sql     ← Test singulier Partie 1
├── analyses/                     ← À CRÉER (bonus)
├── docs/                         ← À CRÉER (bonus — doc blocks)
│
└── scripts/
    ├── 01_setup_snowflake.sql    ← Création base/schémas/rôle (si pas déjà fait)
    ├── 02_tables_sources_partie1.sql   ← Tables + données Partie 1 (rattrapage)
    ├── 03_tables_sources_partie2.sql   ← Nouvelles tables + données Partie 2
    └── 04_snapshot_updates.sql         ← UPDATE séquentiels pour tester les snapshots
```

---

## Mise en route

1. **Configurer Snowflake :** Exécutez les scripts SQL dans l'ordre (`scripts/01` puis `02` puis `03`). Si vous venez de la Partie 1, passez directement au script `03`.

2. **Configurer dbt :** Copiez `profiles.yml.example` vers `~/.dbt/profiles.yml` et renseignez vos identifiants. Vérifiez avec `dbt debug`.

3. **Installer les dépendances :** `dbt deps` pour installer dbt-utils.

4. **Vérifier la base :** `dbt run` puis `dbt test` — tout doit passer avec les modèles existants avant de commencer vos modifications.

---

## Partie 1 — Nouveaux modèles staging

Deux nouvelles tables sources ont été ajoutées : `raw_virements` (virements entre comptes internes) et `raw_alertes` (alertes de dépassement de budget). Elles sont déjà déclarées dans `_stg_sources.yml`.

Créez les modèles staging correspondants :

- `stg_virements.sql` — renommage des colonnes, filtrage éventuel
- `stg_alertes.sql` — renommage, jointure avec le seed `seuils_alerte` pour enrichir le type d'alerte

Ajoutez les tests et la documentation dans `_stg_schema.yml`.

---

## Partie 2 — Seeds

Les fichiers CSV sont déjà en place dans `seeds/`. Chargez-les avec `dbt seed` et vérifiez qu'ils apparaissent dans Snowflake.

Utilisez `mapping_groupes` dans au moins un modèle mart pour enrichir les catégories avec l'ordre d'affichage et la priorité dashboard.

---

## Partie 3 — Modèles incrémentaux

### 3.1 Convertir `fct_transactions` en incrémental

Le fichier `models/marts/fct_transactions.sql` contient des commentaires `TODO` indiquant ce qu'il faut faire. Convertissez-le en modèle incrémental en décidant :

- La colonne de marqueur incrémental
- La gestion du `full_refresh`
- Le traitement des transactions dont le statut change après insertion (ex : `en_attente` → `validee`)

### 3.2 Créer `fct_virements` en incrémental

Nouveau modèle de faits. Chaque virement doit générer deux lignes : une `sortant` pour le compte source, une `entrant` pour le compte destination. Enrichir avec les noms des clients. Ne retenir que les virements exécutés. Incrémental sur la date de virement.

### 3.3 Adapter `mart_solde_mensuel`

Le fichier `models/marts/mart_solde_mensuel.sql` contient des commentaires `TODO`. Adaptez-le pour intégrer les virements internes en plus des transactions. Réfléchissez à la matérialisation optimale.

---

## Partie 4 — Snapshots (SCD Type 2)

### 4.1 Snapshot des comptes

Créez un fichier dans `snapshots/` qui capture les changements de statut, d'email ou de type de compte sur `raw_comptes`. Choisissez la stratégie de détection et les colonnes à surveiller.

Pour tester, suivez le protocole du script `scripts/04_snapshot_updates.sql` :

1. `dbt snapshot` (état initial)
2. Exécuter les UPDATE de l'Étape B → `dbt snapshot`
3. Exécuter les UPDATE de l'Étape C → `dbt snapshot`

Vérifiez que la table snapshot contient l'historique complet avec `dbt_valid_from` et `dbt_valid_to`.

### 4.2 Modèle `dim_comptes_historique`

Créez un modèle mart exposant l'historique des comptes à partir du snapshot, avec un indicateur `est_version_courante` et la durée en jours de chaque version.

---

## Partie 5 — Macros Jinja

Créez les macros suivantes dans `macros/` :

### 5.1 `convertir_centimes(colonne)`

Convertit un montant en euros vers des centimes. Intégrez-la dans au moins un modèle mart.

### 5.2 `generer_periode(colonne_date)`

Génère une colonne `periode` au format `YYYY-MM` à partir d'une date ou d'un timestamp. Remplacez les `DATE_TRUNC` manuels par cette macro dans vos agrégations mensuelles.

### 5.3 `test_taux_null(model, column_name, seuil_pct)`

Test générique custom (custom generic test) qui échoue si le pourcentage de valeurs nulles d'une colonne dépasse un seuil paramétrable. Appliquez-le sur la colonne `motif` de `stg_virements` avec un seuil de 10%.

---

## Partie 6 — Tests avancés et qualité de données

### 6.1 Installer dbt-expectations

Décommentez la ligne dans `packages.yml`, choisissez la version compatible, et lancez `dbt deps`.

### 6.2 Tests à implémenter

**Sur `fct_transactions` :**
- Montants strictement positifs
- Date de transaction pas dans le futur
- `montant_signe` négatif pour les débits, positif pour les crédits

**Sur `fct_virements` :**
- Compte source ≠ compte destination
- Montant > 0

**Sur `mart_budget_vs_reel` :**
- Cohérence entre `depassement` et `ecart`
- `montant_prevu` jamais négatif

**Sur `mart_solde_mensuel` :**
- Comptes épargne sans solde cumulé négatif (convertir le test singulier existant en test générique ou dbt-expectations)

### 6.3 Test de fraîcheur des sources

Configurez un test `freshness` sur les sources dans `_stg_sources.yml`. Les transactions et virements doivent avoir été mis à jour dans les 48 dernières heures en production.

---

## Partie 7 — Hooks et opérations

### 7.1 Hook post-run

Configurez un hook `on-run-end` qui insère une ligne dans `marts.dbt_run_log` (table déjà créée par le script `03`) à chaque exécution. La ligne doit contenir : `run_id`, `started_at`, `completed_at`, `status`, `nb_models`.

### 7.2 Hook pre-run sur fct_transactions

Ajoutez un `pre-hook` sur `fct_transactions` qui journalise le dernier `max(date_transaction)` traité avant chaque run incrémental.

---

## Partie 8 — Exposures et multi-environnement

### 8.1 Déclarer les exposures

Créez `models/exposures.yml` déclarant :
- Un dashboard Metabase « Suivi budgétaire client » (dépend de `mart_budget_vs_reel` et `dim_comptes`)
- Un rapport automatisé « Synthèse mensuelle » (dépend de `mart_solde_mensuel`, `fct_transactions`, `dim_categories`)

### 8.2 Configurer dev / prod

Complétez la target `prod` dans `profiles.yml.example`. Implémentez une macro `generate_schema_name` pour que les modèles atterrissent dans le bon schéma selon la target.

---

## Partie 9 — Aller plus loin (bonus)

### 9.1 Analyse de rétention

Créez dans `analyses/` une requête SQL calculant le taux de rétention mensuel des utilisateurs actifs.

### 9.2 Tags et sélecteurs

Ajoutez des tags (`daily`, `weekly`, `critical`) à vos modèles et testez l'exécution sélective.

### 9.3 Documentation avancée

Créez dans `docs/` un fichier utilisant les doc blocks dbt (`{% docs %}`) pour produire une page d'accueil du projet.

---

## Livrables attendus

1. **Le projet dbt complet et fonctionnel** avec toutes les pièces créées ou modifiées
2. **Une capture d'écran** du lineage dbt docs montrant la chaîne complète incluant les nouveaux modèles
3. **Une preuve d'historisation** : résultat de requête montrant les versions dans la table snapshot
4. **Un court rapport** (20-25 lignes) répondant à :
   - Dans quel cas un modèle incrémental est-il plus pertinent qu'une table ? Quels sont les pièges ?
   - Expliquez le SCD Type 2 et son utilité métier dans le contexte FinTrack.
   - Quel est l'intérêt d'écrire des macros plutôt que de copier-coller du SQL ?
   - Comment la configuration multi-environnement protège-t-elle les données de production ?

---

## Ressources utiles

- [dbt — Modèles incrémentaux](https://docs.getdbt.com/docs/build/incremental-models)
- [dbt — Snapshots](https://docs.getdbt.com/docs/build/snapshots)
- [dbt — Jinja et macros](https://docs.getdbt.com/docs/build/jinja-macros)
- [dbt — Hooks et opérations](https://docs.getdbt.com/docs/build/hooks-operations)
- [dbt — Exposures](https://docs.getdbt.com/docs/build/exposures)
- [dbt-expectations](https://hub.getdbt.com/calogica/dbt_expectations/latest/)
- [dbt — Gestion des environnements](https://docs.getdbt.com/docs/core/dbt-core-environments)
