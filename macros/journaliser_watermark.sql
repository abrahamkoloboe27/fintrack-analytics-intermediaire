{#
    ============================================================
    journaliser_watermark(colonne) — pre-hook de modèle (Partie 7.2)
    ============================================================
    Déclaré dans le config() de fct_transactions :
        pre_hook="{{ journaliser_watermark('date_transaction') }}"

    Avant chaque run INCRÉMENTAL, journalise le dernier watermark traité,
    c'est-à-dire max(<colonne>) de la table existante, AVANT le merge :
      - dans les logs dbt (log info) ;
      - dans <base>.<schéma du modèle>.dbt_watermark_log (créée au besoin) :
        run_id, modele, colonne_watermark, valeur_watermark, journalise_le.
    Utile pour diagnostiquer un run (« à partir de quelle date a-t-il
    retraité les données ? ») et suivre l'avancement du chargement.

    Premier run (table absente), --full-refresh ou modèle non incrémental :
    rien à journaliser (pas de table de référence) -> simple log et
    requête neutre.

    Comportement de dbt-core 1.12 (vérifié dans le code) :
      - la chaîne du pre_hook n'est PAS rendue au parsing : elle est rendue
        par la matérialisation (macro run_hooks -> render()), dans le contexte
        d'exécution du modèle, juste avant le merge. `this`, is_incremental()
        et run_query() y sont donc disponibles avec execute = true ;
      - dans la matérialisation incrémentale de dbt-snowflake, le pre-hook
        est exécuté après la détection de la table existante et avant la
        construction : is_incremental() y a la même valeur que dans le SQL
        du modèle ;
      - un hook rendu vide est ignoré, mais un hook ne contenant qu'un
        commentaire SQL échoue sur Snowflake : la branche « rien à
        journaliser » renvoie donc `select 1 as aucun_watermark` ;
      - les tests unitaires n'exécutent pas les hooks des modèles.
    ============================================================
#}
{% macro journaliser_watermark(colonne) %}

    {%- if colonne is none or (colonne | string | trim) == '' -%}
        {{ exceptions.raise_compiler_error(
            "journaliser_watermark : l'argument 'colonne' est obligatoire "
            ~ "(colonne marqueur du modèle incrémental, ex. 'date_transaction')."
        ) }}
    {%- endif -%}

    {%- if execute and is_incremental() -%}

        {%- set journal = api.Relation.create(
                database=this.database,
                schema=this.schema,
                identifier='dbt_watermark_log'
            ) -%}

        {#- Watermark actuel, lu AVANT que le run n'ajoute de nouvelles lignes -#}
        {%- set requete_watermark -%}
            select max({{ colonne }}) as valeur_watermark from {{ this }}
        {%- endset -%}
        {%- set valeur_watermark = run_query(requete_watermark).columns[0].values()[0] -%}

        {%- do log(
                "journaliser_watermark : " ~ this ~ " - max(" ~ colonne ~ ") avant ce run incrémental = "
                ~ (valeur_watermark if valeur_watermark is not none else 'NULL (table vide)'),
                info=True
            ) -%}

create table if not exists {{ journal }} (
    run_id            varchar(50),
    modele            varchar(255),
    colonne_watermark varchar(255),
    valeur_watermark  timestamp_ntz,
    journalise_le     timestamp_ntz
);
insert into {{ journal }} (run_id, modele, colonne_watermark, valeur_watermark, journalise_le)
select
    '{{ invocation_id }}',
    '{{ this.identifier }}',
    '{{ colonne }}',
    max({{ colonne }}),
    sysdate()
from {{ this }}

    {%- else -%}

        {%- if execute -%}
            {%- do log(
                    "journaliser_watermark : " ~ this ~ " - premier run, --full-refresh "
                    ~ "ou modèle non incrémental : aucun watermark à journaliser.",
                    info=True
                ) -%}
        {%- endif -%}
select 1 as aucun_watermark

    {%- endif -%}

{% endmacro %}
