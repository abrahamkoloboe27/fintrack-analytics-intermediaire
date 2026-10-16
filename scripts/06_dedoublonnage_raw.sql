-- ============================================================
-- SCRIPT 6 : Dédoublonnage des tables RAW de la Partie 1
-- ============================================================
-- Incident : le script 02 (non idempotent : CREATE TABLE IF NOT EXISTS
-- + INSERT) a été ré-exécuté alors que les données de la Partie 1
-- étaient déjà chargées. Chaque ligne de raw_comptes, raw_categories,
-- raw_transactions (ids 1-45) et raw_budgets (ids 1-25) est en double.
-- Les doublons sont strictement identiques (SELECT DISTINCT * redonne
-- 6 / 12 / 102 / 50 lignes).
--
-- INSERT OVERWRITE ... SELECT DISTINCT * réécrit la table en une seule
-- instruction atomique, en conservant le propriétaire et les GRANT
-- (contrairement à CREATE OR REPLACE TABLE). Il exige le privilège DELETE :
-- à exécuter avec SYSADMIN, propriétaire de ces 4 tables.
-- Le script est idempotent : le relancer ne change plus rien.
-- ============================================================

USE ROLE SYSADMIN;
USE WAREHOUSE FINTRACK_WH;
USE DATABASE FINTRACK_DB;
USE SCHEMA RAW;

INSERT OVERWRITE INTO raw_comptes      SELECT DISTINCT * FROM raw_comptes;
INSERT OVERWRITE INTO raw_categories   SELECT DISTINCT * FROM raw_categories;
INSERT OVERWRITE INTO raw_transactions SELECT DISTINCT * FROM raw_transactions;
INSERT OVERWRITE INTO raw_budgets      SELECT DISTINCT * FROM raw_budgets;

-- Vérification attendue : n = n_ids pour chaque table (6, 12, 102, 50)
SELECT 'raw_comptes' AS table_raw, COUNT(*) AS n, COUNT(DISTINCT id) AS n_ids FROM raw_comptes
UNION ALL SELECT 'raw_categories',   COUNT(*), COUNT(DISTINCT id) FROM raw_categories
UNION ALL SELECT 'raw_transactions', COUNT(*), COUNT(DISTINCT id) FROM raw_transactions
UNION ALL SELECT 'raw_budgets',      COUNT(*), COUNT(DISTINCT id) FROM raw_budgets;
