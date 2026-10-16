-- ============================================================
-- SCRIPT 5 : Droits complémentaires de FINTRACK_ROLE (Partie 2)
-- ============================================================
-- Contexte : sur ce compte, FINTRACK_ROLE (le rôle utilisé par dbt)
-- n'a que USAGE + SELECT sur le schéma RAW, et aucun droit
-- CREATE SCHEMA sur la base. Le script 01 prévoyait pourtant
-- « GRANT ALL ON SCHEMA FINTRACK_DB.RAW », et les scripts 02 à 04
-- s'exécutent avec FINTRACK_ROLE.
--
-- Sans ce script, impossible :
--   - d'exécuter le script 03 (CREATE TABLE / INSERT dans RAW) ;
--   - d'exécuter les UPDATE du script 04 (protocole snapshot) ;
--   - de créer les schémas dev (DEV_<NOM>), CI (CI_*) et SNAPSHOTS ;
--   - de charger les seeds dans RAW avec la target prod.
--
-- À exécuter UNE FOIS dans Snowsight avec SYSADMIN (propriétaire de
-- la base et des schémas créés par le script 01), ou ACCOUNTADMIN si
-- les tables RAW ont été créées avec ce rôle.
--
-- Ordre : APRÈS le script 02 (les GRANT de la section 3 portent sur des
-- tables qu'il crée), AVANT le script 03 et AVANT le premier
-- dbt seed / snapshot / build (création du schéma DEV_<NOM>).
-- Séquence complète : 01 → 02 → 05 → 03 ; 04 uniquement pendant le
-- protocole snapshot ; 06 uniquement si le script 02 a été rejoué.
-- ============================================================

USE ROLE SYSADMIN;

-- 1. Création de schémas par dbt : dev personnel, CI éphémère, SNAPSHOTS (prod)
GRANT CREATE SCHEMA ON DATABASE FINTRACK_DB TO ROLE FINTRACK_ROLE;

-- 2. Schéma RAW : création des nouvelles tables (script 03) et des seeds (prod)
GRANT CREATE TABLE ON SCHEMA FINTRACK_DB.RAW TO ROLE FINTRACK_ROLE;

-- 3. Tables RAW existantes : chargement Partie 2 (script 03) et protocole snapshot (script 04)
GRANT INSERT ON TABLE FINTRACK_DB.RAW.RAW_TRANSACTIONS TO ROLE FINTRACK_ROLE;
GRANT INSERT ON TABLE FINTRACK_DB.RAW.RAW_BUDGETS      TO ROLE FINTRACK_ROLE;
GRANT UPDATE ON TABLE FINTRACK_DB.RAW.RAW_COMPTES      TO ROLE FINTRACK_ROLE;

-- Vérification
SHOW GRANTS TO ROLE FINTRACK_ROLE;

-- ============================================================
-- (Optionnel) APRÈS le protocole snapshot : revenir à un RAW en
-- lecture seule pour dbt (principe du moindre privilège).
-- Garder CREATE TABLE sur RAW si les seeds y sont chargés en prod.
-- ============================================================
-- REVOKE INSERT ON TABLE FINTRACK_DB.RAW.RAW_TRANSACTIONS FROM ROLE FINTRACK_ROLE;
-- REVOKE INSERT ON TABLE FINTRACK_DB.RAW.RAW_BUDGETS      FROM ROLE FINTRACK_ROLE;
-- REVOKE UPDATE ON TABLE FINTRACK_DB.RAW.RAW_COMPTES      FROM ROLE FINTRACK_ROLE;
