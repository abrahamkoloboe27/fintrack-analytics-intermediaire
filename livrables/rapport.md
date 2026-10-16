# Rapport — FinTrack Analytics, Partie 2

## 1. Incrémental ou table ?
- L'incrémental convient à une grosse table alimentée en continu, dont l'historique ne bouge plus.
- `fct_transactions` (50 000 lignes/mois) : au 2e run, le `merge` n'a retraité que 3 transactions sur 100.
- Une table convient à un petit agrégat qui dépend de tout l'historique (solde cumulé de `mart_solde_mensuel`).
- Piège : une transaction validée tard garde sa date d'origine ; l'anti-jointure sur la clé la rattrape.
- Autres pièges : annulations non propagées (`--full-refresh` hebdo), clés en double, changement de schéma.

## 2. Le SCD Type 2 et son utilité pour FinTrack
- On ne remplace pas une valeur : on ferme la version courante (`dbt_valid_to`) et on en ouvre une nouvelle.
- `snap_comptes` suit statut, email et type de compte (stratégie `check`, faute de date de mise à jour fiable).
- Après le protocole : 9 versions, dont deux pour Bob (clôturé), Emma (réactivée) et David (inactif).
- Le support peut dire le statut d'un compte à une date donnée, expliquer un refus, tracer un changement d'email.

## 3. Pourquoi des macros plutôt que du copier-coller ?
- Une règle écrite une fois : `convertir_centimes` et `generer_periode` donnent partout le même arrondi et le même mois.
- Une correction se propage à tous les modèles, et chaque modèle reste court et lisible.
- Le test générique `taux_null` se réutilise sur n'importe quelle colonne, avec un seuil paramétrable.
- Le copier-coller fait diverger les variantes (formats, fuseaux horaires) et multiplie les relectures.

## 4. Comment le multi-environnement protège-t-il la production ?
- `generate_schema_name` : seule la target `prod` écrit dans `STAGING`, `MARTS`, `RAW` (seeds) et `SNAPSHOTS`.
- Le dev (`DEV_ABRAHAM`) et la CI (`CI_PR_<n>`, supprimé après le build) ont chacun leur schéma isolé.
- Un modèle inachevé ou un `--full-refresh` d'essai n'atteint donc jamais les tables lues par Metabase.
- En pratique, la prod est déployée par la CD au merge sur `main`, après une PR dont la CI a tout construit et testé.
- Limite : rien n'impose encore la PR (protéger `main`), et tous les environnements partagent `FINTRACK_ROLE`.
