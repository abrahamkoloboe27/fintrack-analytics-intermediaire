{#
    ============================================================
    Test générique taux_null(model, column_name, seuil_pct) — Partie 5.3
    ============================================================
    Échoue si le pourcentage de valeurs NULL de la colonne testée dépasse
    `seuil_pct` (pourcentage entre 0 et 100, bornes incluses).

    - Table vide : le test passe (aucun taux calculable).
    - En cas d'échec, renvoie une ligne : nb_lignes, nb_nulls,
      taux_null_pct, seuil_pct (lisible avec --store-failures).
    - Le seuil est contrôlé dès la compilation : une valeur absente, non
      numérique ou hors [0, 100] arrête dbt avec un message explicite.
    - Compatible avec les configs standard des tests (where, severity,
      warn_if, error_if...).

    Utilisation (syntaxe dbt >= 1.10.5, arguments sous `arguments:`) :

        columns:
          - name: motif
            data_tests:
              - taux_null:
                  arguments:
                    seuil_pct: 10
    ============================================================
#}
{% test taux_null(model, column_name, seuil_pct) %}

    {%- if seuil_pct is not defined
          or seuil_pct is none
          or seuil_pct is boolean
          or seuil_pct is not number
          or seuil_pct < 0
          or seuil_pct > 100 -%}
        {%- if seuil_pct is not defined -%}
            {%- set valeur_recue = 'aucune valeur' -%}
        {%- elif seuil_pct is string -%}
            {%- set valeur_recue = "'" ~ seuil_pct ~ "' (texte)" -%}
        {%- else -%}
            {%- set valeur_recue = seuil_pct -%}
        {%- endif -%}
        {{ exceptions.raise_compiler_error(
            "Test taux_null sur la colonne '" ~ column_name ~ "' : seuil_pct doit être "
            ~ "un nombre compris entre 0 et 100 (reçu : " ~ valeur_recue ~ ")."
        ) }}
    {%- endif %}

with statistiques as (

    select
        count(*)                            as nb_lignes,
        count(*) - count({{ column_name }}) as nb_nulls
    from {{ model }}

)

select
    nb_lignes,
    nb_nulls,
    round(100 * nb_nulls / nb_lignes, 2) as taux_null_pct,
    {{ seuil_pct }}                      as seuil_pct
from statistiques
where nb_lignes > 0
  and 100 * nb_nulls / nb_lignes > {{ seuil_pct }}

{% endtest %}
