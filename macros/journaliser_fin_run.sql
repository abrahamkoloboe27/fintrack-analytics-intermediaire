{#
    ============================================================
    journaliser_fin_run(results) — hook on-run-end (Partie 7.1)
    ============================================================
    Déclaré dans dbt_project.yml :
        on-run-end:
          - "{{ journaliser_fin_run(results) }}"

    Insère UNE ligne par exécution dbt dans <schéma marts de la target>.dbt_run_log :
      - prod     : FINTRACK_DB.MARTS.dbt_run_log (table créée par scripts/03) ;
      - dev / ci : <schéma de la target>.dbt_run_log, créée au premier run.
    Le schéma est calculé par generate_schema_name('marts', none) : le
    journal suit donc exactement les mêmes règles d'isolation que les modèles.

    Colonnes :
      run_id       = invocation_id (identifiant unique de l'exécution dbt)
      started_at   = run_started_at, début de l'exécution (UTC, timestamp_ntz)
      completed_at = sysdate(), fin de l'exécution (UTC, timestamp_ntz)
      status       = 'error' si au moins un nœud est en error / fail / runtime error,
                     sinon 'warn' si au moins un warn (ou partial success d'un
                     modèle microbatch), sinon 'success'
      nb_models    = nombre de résultats dont le nœud est un modèle

    Comportement de dbt-core 1.12 / dbt-snowflake 1.12 (vérifié dans le code) :
      - Les hooks on-run-end sont exécutés par run, build, seed, snapshot,
        test, source freshness (behavior flag source_freshness_run_project_hooks,
        vrai par défaut) et retry (qui rejoue la commande précédente : flags.WHICH
        vaut alors 'run', 'build'...). compile, show, docs generate,
        run-operation, clone et ls ne les exécutent pas.
      - flags.WHICH contient le nom de la sous-commande ('run', 'build', 'seed',
        'snapshot', 'test', 'freshness'...) : seules les commandes qui
        construisent ou testent des nœuds sont journalisées.
      - Le hook est aussi rendu au parsing (execute = false, `results` indéfini) :
        dans ce cas, aucune requête, aucun log.
      - Un hook vide (espaces seulement) est ignoré par dbt, mais un hook qui ne
        contient que des commentaires SQL est envoyé à Snowflake et fait échouer
        la commande (aucune instruction à exécuter). Chaque branche renvoie donc
        du SQL valide : `select 1 as aucun_journal` quand on ne journalise pas.
      - `results` : liste de RunResult ; .status vaut success, error, skipped,
        pass, fail, warn, runtime error, partial success, no-op ou reused ;
        .node.resource_type vaut model, seed, snapshot, test, unit_test,
        operation (hook on-run-start en échec)...
      - Les instructions séparées par « ; » sont exécutées l'une après l'autre.
    ============================================================
#}
{% macro journaliser_fin_run(results) %}

    {%- set commandes_journalisees = ['run', 'build', 'seed', 'snapshot', 'test'] -%}

    {%- if execute and flags.WHICH in commandes_journalisees -%}

        {#- 1. Statut global de l'exécution et nombre de modèles traités -#}
        {%- set compteurs = namespace(erreurs=0, avertissements=0, modeles=0) -%}
        {%- for resultat in results -%}
            {%- set statut_noeud = resultat.status | string | lower -%}
            {%- if statut_noeud in ['error', 'fail', 'runtime error'] -%}
                {%- set compteurs.erreurs = compteurs.erreurs + 1 -%}
            {%- elif statut_noeud in ['warn', 'partial success'] -%}
                {%- set compteurs.avertissements = compteurs.avertissements + 1 -%}
            {%- endif -%}
            {%- if resultat.node.resource_type == 'model' -%}
                {%- set compteurs.modeles = compteurs.modeles + 1 -%}
            {%- endif -%}
        {%- endfor -%}

        {%- if compteurs.erreurs > 0 -%}
            {%- set statut_run = 'error' -%}
        {%- elif compteurs.avertissements > 0 -%}
            {%- set statut_run = 'warn' -%}
        {%- else -%}
            {%- set statut_run = 'success' -%}
        {%- endif -%}

        {#- 2. Table de journal : schéma « marts » de la target courante -#}
        {%- set schema_journal = generate_schema_name('marts', none) | trim -%}
        {%- set journal = api.Relation.create(
                database=target.database,
                schema=schema_journal,
                identifier='dbt_run_log'
            ) -%}

        {#- 3. Début de l'exécution : run_started_at est un datetime UTC ;
               le format sans fuseau donne un timestamp_ntz en UTC, comme sysdate(). -#}
        {%- if run_started_at is not none -%}
            {%- set debut_sql = "cast('" ~ run_started_at.strftime('%Y-%m-%d %H:%M:%S.%f') ~ "' as timestamp_ntz)" -%}
        {%- else -%}
            {%- set debut_sql = 'sysdate()' -%}
        {%- endif -%}

        {%- do log(
                "journaliser_fin_run : dbt " ~ flags.WHICH ~ " " ~ invocation_id
                ~ " -> status=" ~ statut_run ~ ", nb_models=" ~ compteurs.modeles
                ~ ", journal=" ~ journal,
                info=True
            ) -%}

        {#- 4. DDL uniquement si la table est absente (premier run en dev / ci) :
               en prod, la table existe et un simple INSERT suffit, sans
               solliciter de droit CREATE SCHEMA / CREATE TABLE. -#}
        {%- set table_existante = adapter.get_relation(
                database=journal.database,
                schema=journal.schema,
                identifier=journal.identifier
            ) -%}
        {%- if table_existante is none -%}
            {%- if not adapter.check_schema_exists(journal.database, journal.schema) %}
create schema if not exists {{ journal.without_identifier() }};
            {%- endif %}
create table if not exists {{ journal }} (
    run_id       varchar(50),
    started_at   timestamp_ntz,
    completed_at timestamp_ntz,
    status       varchar(20),
    nb_models    integer
);
        {%- endif %}
insert into {{ journal }} (run_id, started_at, completed_at, status, nb_models)
select
    '{{ invocation_id }}',
    {{ debut_sql }},
    sysdate(),
    '{{ statut_run }}',
    {{ compteurs.modeles }}

    {%- else -%}

        {#- Parsing, ou commande non journalisée (ex. source freshness) :
            requête neutre, jamais une chaîne vide ni un simple commentaire. -#}
        {%- if execute -%}
            {%- do log("journaliser_fin_run : commande '" ~ flags.WHICH ~ "' non journalisée.") -%}
        {%- endif -%}
select 1 as aucun_journal

    {%- endif -%}

{% endmacro %}
