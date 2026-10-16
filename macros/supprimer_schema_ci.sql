{#
    ============================================================
    supprimer_schema_ci() — nettoyage du schéma CI éphémère (CI/CD)
    ============================================================
    Opération appelée par la CI GitHub Actions (.github/workflows/ci.yml,
    job build-ci), avant le build (nettoyage préventif, au cas où un run
    précédent aurait été interrompu) et après le build (étape
    `if: always()`, exécutée même en cas d'échec ou d'annulation) :

        dbt run-operation supprimer_schema_ci --target ci

    Supprime le schéma <target.database>.<target.schema>
    (ex. FINTRACK_DB.CI_PR_12) et TOUT son contenu :
        drop schema if exists ... cascade
    Le nom du schéma vient de la variable d'environnement DBT_CI_SCHEMA
    (ci/profiles.yml). Aucune erreur si le schéma n'existe pas.

    Garde-fous : impossible de supprimer un schéma de dev ou de prod
    (MARTS, STAGING, RAW, SNAPSHOTS, DEV_...) avec cette macro.
      1. La target active doit s'appeler `ci`.
      2. Le schéma doit respecter la convention des workflows :
         CI_ suivi de lettres, chiffres ou « _ » (CI_PR_12, CI_RUN_<id>...).
    Sinon : erreur de compilation, aucune requête n'est envoyée.

    adapter.drop_schema() (dbt-adapters) exécute la macro native
    drop_schema, puis met à jour le cache de relations de dbt.
    ============================================================
#}
{% macro supprimer_schema_ci() %}

    {%- if target.name != 'ci' -%}
        {%- do exceptions.raise_compiler_error(
                "supprimer_schema_ci : refusé pour la target '" ~ target.name
                ~ "'. Cette macro ne s'exécute qu'avec --target ci."
            ) -%}
    {%- endif -%}

    {%- set nom_schema = target.schema | trim -%}

    {%- if not modules.re.match('^CI_[A-Z0-9_]+$', nom_schema | upper) -%}
        {%- do exceptions.raise_compiler_error(
                "supprimer_schema_ci : refusé pour le schéma '" ~ nom_schema
                ~ "'. Seuls les schémas éphémères de la CI (CI_PR_12, CI_RUN_<id>...)"
                ~ " peuvent être supprimés."
            ) -%}
    {%- endif -%}

    {%- set schema_ci = api.Relation.create(database=target.database, schema=nom_schema) -%}

    {%- do log("supprimer_schema_ci : suppression de " ~ schema_ci ~ " (s'il existe)...", info=True) -%}
    {%- do adapter.drop_schema(schema_ci) -%}
    {%- do log("supprimer_schema_ci : schéma " ~ schema_ci ~ " supprimé.", info=True) -%}

{% endmacro %}
