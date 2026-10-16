{#
  ============================================================
  DOC BLOCKS RÉUTILISABLES (Partie 9.3 — bonus)
  ============================================================
  Descriptions des colonnes communes à plusieurs modèles, écrites UNE
  seule fois ici puis insérées dans les fichiers YAML de propriétés :

      columns:
        - name: periode
          description: "{{ doc('col_periode') }}"

  Modifier un bloc met à jour toutes les colonnes qui y font référence
  au prochain `dbt docs generate`.

  Blocs disponibles : col_periode, col_montant_signe, col_montant_centimes,
  col_date_chargement, col_compte_id, col_statut_compte
  (la page d'accueil __overview__ est dans docs/overview.md).

  Le dossier docs/ est déclaré dans dbt_project.yml (docs-paths: ["docs"]).
  Le contenu d'un bloc est rendu par Jinja : ne pas y écrire de balises
  Jinja (accolades doubles, accolade + pourcent) sans les protéger par
  un bloc raw.
  ============================================================
#}

{% docs col_periode %}
Période mensuelle au format texte `YYYY-MM` (ex. `2024-03`), produite par la macro `generer_periode` à partir de la date métier (date de transaction, date de virement, mois du budget ou de l'alerte).

C'est la **clé de grain mensuel commune** à tout le projet : agrégats et jointures mensuelles se font sur `periode`, et l'ordre alphabétique est aussi l'ordre chronologique. Quand un type date est utile à la BI, la colonne `mois` (`to_date(periode, 'YYYY-MM')`, premier jour du mois) l'accompagne.
{% enddocs %}

{% docs col_montant_signe %}
Montant en euros **signé selon le sens du flux pour le compte concerné** : positif quand l'argent entre sur le compte (crédit, virement entrant), négatif quand il en sort (débit, virement sortant).

La somme des montants signés d'un compte sur une période donne directement la variation de son solde : c'est la base des soldes de `mart_solde_mensuel`.
{% enddocs %}

{% docs col_montant_centimes %}
Montant converti en **centimes d'euro**, en entier (`number(38, 0)`), par la macro `convertir_centimes` : `round(montant * 100, 0)`.

Les entiers évitent les erreurs d'arrondi des décimaux pour les systèmes aval (API de paiement, exports comptables). La variante signée `montant_signe_centimes` suit la même convention de signe que `montant_signe`.
{% enddocs %}

{% docs col_date_chargement %}
Horodatage technique (UTC, `timestamp_ntz`) du **dernier traitement de la ligne par dbt** (`sysdate()` au moment du run). Ce n'est pas une date métier.

Dans un modèle incrémental, il est renouvelé chaque fois que le `merge` insère ou met à jour la ligne (fenêtre de recouvrement, validation tardive, `--full-refresh`) ; une ligne qui n'est pas retraitée conserve sa valeur. Utile pour auditer et diagnostiquer les chargements incrémentaux.
{% enddocs %}

{% docs col_compte_id %}
Identifiant du compte client FinTrack (clé naturelle `id` de la table source `raw_comptes`).

Clé de jointure vers `dim_comptes` (une ligne par compte). Le compte est l'unité d'analyse « client » du projet : un compte joint est partagé par plusieurs personnes.
{% enddocs %}

{% docs col_statut_compte %}
Statut du compte, normalisé en minuscules : `actif` (compte ouvert et utilisé), `inactif` (compte ouvert mais dormant) ou `cloture` (compte fermé).

Le statut évolue dans le temps (ex. `inactif` → `actif`) : chaque changement est historisé en SCD Type 2 par le snapshot `snap_comptes` et consultable dans `dim_comptes_historique`.
{% enddocs %}
