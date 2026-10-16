{#
    ============================================================
    generate_schema_name — schéma de chaque objet selon la target
    (Partie 8.2 — multi-environnement)
    ============================================================
    Surcharge la macro native de dbt, appelée pour chaque modèle, seed,
    snapshot et test avec la valeur de `+schema` (custom_schema_name).

    Comportement natif de dbt : <schéma de la target>_<schéma personnalisé>
    (ex. DEV_ABRAHAM_marts). Ici :

      - target `prod`  : schéma personnalisé utilisé TEL QUEL
                         staging -> STAGING, marts -> MARTS,
                         raw (seeds) -> RAW, snapshots -> SNAPSHOTS ;
                         sans schéma personnalisé -> schéma de la target (MARTS).
      - autres targets : TOUT dans le schéma de la target
        (dev, ci...)     (DEV_ABRAHAM, CI_PR_12...), quel que soit `+schema`.

    Conséquence : seul un run lancé avec `--target prod` peut écrire
    dans les schémas lus par les dashboards ; le dev et la CI travaillent
    dans des schémas isolés, jetables.

    Snowflake : les identifiants sans guillemets sont insensibles à la casse,
    `marts` et `MARTS` désignent donc le même schéma.

    `node` n'est pas utilisé ; la macro accepte node = none, ce qui
    permet de l'appeler depuis un hook pour retrouver le schéma « marts »
    de la target courante (cf. journaliser_fin_run).
    ============================================================
#}
{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- set schema_target = target.schema | trim -%}

    {%- if target.name == 'prod'
          and custom_schema_name is not none
          and (custom_schema_name | trim) != '' -%}

        {{ custom_schema_name | trim }}

    {%- else -%}

        {{ schema_target }}

    {%- endif -%}

{%- endmacro %}
