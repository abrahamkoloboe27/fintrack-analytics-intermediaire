-- ============================================================
-- SCRIPT 1 : Configuration de l'environnement Snowflake
-- ============================================================
-- Ce script crée la base, les schémas, l'entrepôt et le rôle.
-- À exécuter avec un rôle SYSADMIN ou ACCOUNTADMIN.
-- Si vous avez déjà fait la Partie 1, passez directement au script 02.
-- ============================================================

USE ROLE SYSADMIN;

CREATE DATABASE IF NOT EXISTS FINTRACK_DB;

CREATE SCHEMA IF NOT EXISTS FINTRACK_DB.RAW;
CREATE SCHEMA IF NOT EXISTS FINTRACK_DB.STAGING;
CREATE SCHEMA IF NOT EXISTS FINTRACK_DB.MARTS;

CREATE WAREHOUSE IF NOT EXISTS FINTRACK_WH
    WITH WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;

-- Rôle dédié
USE ROLE SECURITYADMIN;
CREATE ROLE IF NOT EXISTS FINTRACK_ROLE;
GRANT USAGE ON DATABASE FINTRACK_DB TO ROLE FINTRACK_ROLE;
GRANT USAGE ON WAREHOUSE FINTRACK_WH TO ROLE FINTRACK_ROLE;
GRANT ALL ON SCHEMA FINTRACK_DB.RAW TO ROLE FINTRACK_ROLE;
GRANT ALL ON SCHEMA FINTRACK_DB.STAGING TO ROLE FINTRACK_ROLE;
GRANT ALL ON SCHEMA FINTRACK_DB.MARTS TO ROLE FINTRACK_ROLE;

-- Attribuer le rôle à votre utilisateur
-- GRANT ROLE FINTRACK_ROLE TO USER <votre_utilisateur>;
