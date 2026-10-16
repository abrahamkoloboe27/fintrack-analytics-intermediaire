-- ============================================================
-- SCRIPT 4 : Changements de statut pour tester les snapshots
-- ============================================================
-- NE PAS exécuter tout d'un coup.
-- Suivez les étapes décrites dans le briefing (Partie 4).
-- ============================================================

USE ROLE FINTRACK_ROLE;
USE WAREHOUSE FINTRACK_WH;
USE DATABASE FINTRACK_DB;
USE SCHEMA RAW;

-- ============================================
-- ÉTAPE B — Exécuter APRÈS le premier dbt snapshot
-- ============================================
-- Décommenter et exécuter :
-- UPDATE raw_comptes SET statut = 'actif' WHERE id = 5;        -- Emma redevient active
-- UPDATE raw_comptes SET statut = 'cloture' WHERE id = 2;      -- Bob clôture son compte

-- Puis relancer : dbt snapshot

-- ============================================
-- ÉTAPE C — Exécuter APRÈS le deuxième dbt snapshot
-- ============================================
-- Décommenter et exécuter :
-- UPDATE raw_comptes SET statut = 'inactif' WHERE id = 4;      -- David passe en inactif

-- Puis relancer : dbt snapshot
