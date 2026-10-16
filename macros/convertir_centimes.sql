{#
    ============================================================
    convertir_centimes(colonne) — Partie 5.1
    ============================================================
    Convertit un montant en euros (ex. number(10, 2)) en centimes
    entiers, pour les échanges avec des systèmes qui n'acceptent pas les
    décimales et pour des agrégations sans erreur d'arrondi.

    - `colonne` : nom de colonne ou expression SQL (chaîne), ex. 't.montant'.
    - Renvoie une EXPRESSION SQL, sans alias : l'appelant nomme la colonne.
    - round(..., 0) avant le cast : un montant ayant plus de 2 décimales
      (résultat d'un calcul) est arrondi explicitement plutôt que
      tronqué ou arrondi implicitement.
    - number(38, 0) : entier Snowflake de précision maximale, aucun risque
      de dépassement.
    - NULL en entrée -> NULL en sortie.

    Exemple :
        {{ convertir_centimes('t.montant') }} as montant_centimes
    compile en :
        cast(round(t.montant * 100, 0) as number(38, 0)) as montant_centimes
    ============================================================
#}
{% macro convertir_centimes(colonne) -%}

    {%- if colonne is none or (colonne | string | trim) == '' -%}
        {{ exceptions.raise_compiler_error(
            "convertir_centimes : l'argument 'colonne' est obligatoire "
            ~ "(nom de colonne ou expression SQL, ex. 't.montant')."
        ) }}
    {%- endif -%}

    cast(round({{ colonne }} * 100, 0) as number(38, 0))

{%- endmacro %}
