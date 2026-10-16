{#
    ============================================================
    generer_periode(colonne_date) — Partie 5.2
    ============================================================
    Produit la clé mensuelle `periode` au format texte 'YYYY-MM' à partir
    d'une date ou d'un timestamp. Remplace les date_trunc('month', ...)
    manuels : tous les modèles mensuels partagent ainsi la même clé de
    jointure (transactions, virements, budgets, alertes).

    - `colonne_date` : nom de colonne ou expression SQL (chaîne) de type
      DATE ou TIMESTAMP, ex. 't.date_transaction'.
    - Renvoie une EXPRESSION SQL, sans alias.
    - cast(... as date) d'abord, l'heure est ignorée. DATE, TIMESTAMP_NTZ
      et TIMESTAMP_TZ : mois de la valeur telle que stockée.
      TIMESTAMP_LTZ (ex. current_timestamp()) : la date dépend du fuseau
      de la session (America/Los_Angeles par défaut) ; convertir avant
      l'appel, ex. generer_periode("convert_timezone('Europe/Paris', col)::timestamp_ntz").
    - 'YYYY-MM' se trie dans l'ordre chronologique (tri texte = tri
      temporel) ; pour retrouver une date (1er du mois), utiliser
      to_date(periode, 'YYYY-MM').
    - NULL en entrée -> NULL en sortie.

    Exemple :
        {{ generer_periode('t.date_transaction') }} as periode
    compile en :
        to_char(cast(t.date_transaction as date), 'YYYY-MM') as periode
    ============================================================
#}
{% macro generer_periode(colonne_date) -%}

    {%- if colonne_date is none or (colonne_date | string | trim) == '' -%}
        {{ exceptions.raise_compiler_error(
            "generer_periode : l'argument 'colonne_date' est obligatoire "
            ~ "(nom de colonne ou expression SQL, ex. 't.date_transaction')."
        ) }}
    {%- endif -%}

    to_char(cast({{ colonne_date }} as date), 'YYYY-MM')

{%- endmacro %}
