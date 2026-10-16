-- ============================================================
-- SCRIPT 3 : Nouvelles tables et données de la Partie 2
-- ============================================================
-- Ce script ajoute les tables et données nécessaires au projet
-- intermédiaire. Exécutez-le après le script 02 (ou après avoir
-- complété la Partie 1).
-- ============================================================

USE ROLE FINTRACK_ROLE;
USE WAREHOUSE FINTRACK_WH;
USE DATABASE FINTRACK_DB;
USE SCHEMA RAW;

-- ============================================
-- NOUVELLES TABLES
-- ============================================

CREATE TABLE IF NOT EXISTS raw_virements (
    id                INTEGER,
    compte_source_id  INTEGER,
    compte_dest_id    INTEGER,
    montant           DECIMAL(10,2),
    date_virement     TIMESTAMP,
    motif             VARCHAR(255),
    statut            VARCHAR(15)
);

CREATE TABLE IF NOT EXISTS raw_alertes (
    id               INTEGER,
    compte_id        INTEGER,
    categorie_id     INTEGER,
    mois             DATE,
    type_alerte      VARCHAR(20),
    montant_prevu    DECIMAL(10,2),
    montant_reel     DECIMAL(10,2),
    date_generation  TIMESTAMP,
    acquittee        BOOLEAN
);

-- Table d'audit pour les hooks (Partie 7)
CREATE TABLE IF NOT EXISTS FINTRACK_DB.MARTS.dbt_run_log (
    run_id       VARCHAR(50),
    started_at   TIMESTAMP,
    completed_at TIMESTAMP,
    status       VARCHAR(20),
    nb_models    INTEGER
);

-- ============================================
-- VIREMENTS INTERNES
-- ============================================

INSERT INTO raw_virements (id, compte_source_id, compte_dest_id, montant, date_virement, motif, statut) VALUES
(1,  1, 3, 300.00, '2024-01-15 10:00:00', 'Épargne mensuelle janvier',    'execute'),
(2,  1, 3, 300.00, '2024-02-15 10:00:00', 'Épargne mensuelle février',    'execute'),
(3,  1, 3, 300.00, '2024-03-15 10:00:00', 'Épargne mensuelle mars',       'execute'),
(4,  4, 3, 500.00, '2024-01-20 10:00:00', 'Épargne famille',              'execute'),
(5,  2, 1, 150.00, '2024-02-28 14:00:00', 'Remboursement restaurant',     'execute'),
(6,  1, 2, 75.00,  '2024-03-10 09:00:00', 'Partage abonnement',          'en_attente'),
(7,  4, 1, 200.00, '2024-03-20 11:30:00', 'Remboursement courses',        'annule'),
(8,  2, 3, 100.00, '2024-01-30 16:00:00', 'Épargne ponctuelle',           'execute'),
(9,  4, 3, 500.00, '2024-02-20 10:00:00', 'Épargne famille février',      'execute'),
(10, 1, 3, 150.00, '2024-03-25 10:00:00', 'Complément épargne mars',      'execute');

-- ============================================
-- ALERTES DE DÉPASSEMENT
-- ============================================

INSERT INTO raw_alertes (id, compte_id, categorie_id, mois, type_alerte, montant_prevu, montant_reel, date_generation, acquittee) VALUES
(1, 1, 7, '2024-02-01', 'depassement_100', 60.00,  89.00,  '2024-02-14 20:05:00', TRUE),
(2, 2, 3, '2024-02-01', 'depassement_80',  100.00, 82.30,  '2024-02-08 13:05:00', FALSE),
(3, 2, 12,'2024-01-01', 'depassement_100', 80.00,  120.00, '2024-01-25 08:05:00', TRUE),
(4, 1, 3, '2024-03-01', 'depassement_80',  160.00, 132.10, '2024-03-07 10:35:00', FALSE),
(5, 2, 7, '2024-01-01', 'depassement_80',  50.00,  43.00,  '2024-01-07 18:05:00', FALSE),
(6, 1, 7, '2024-01-01', 'depassement_80',  60.00,  52.00,  '2024-01-08 19:50:00', TRUE);

-- ============================================
-- TRANSACTIONS COMPLÉMENTAIRES (avril–juin 2024)
-- ============================================

INSERT INTO raw_transactions (id, compte_id, date_transaction, montant, type_operation, categorie_id, description, statut) VALUES
-- Alice — Avril 2024
(46, 1, '2024-04-01 09:00:00', 2850.00, 'credit', 1,  'Salaire avril (augmentation)',  'validee'),
(47, 1, '2024-04-03 14:00:00', 850.00,  'debit',  5,  'Loyer avril',                   'validee'),
(48, 1, '2024-04-05 11:00:00', 71.60,   'debit',  3,  'Courses Intermarché',           'validee'),
(49, 1, '2024-04-09 20:00:00', 38.00,   'debit',  7,  'Restaurant Chez Marcel',        'validee'),
(50, 1, '2024-04-10 08:00:00', 75.00,   'debit',  4,  'Abonnement Navigo',             'validee'),
(51, 1, '2024-04-15 10:00:00', 15.99,   'debit',  8,  'Netflix',                       'validee'),
(52, 1, '2024-04-18 14:00:00', 62.00,   'debit',  12, 'H&M printemps',                 'validee'),
(53, 1, '2024-04-20 16:00:00', 250.00,  'debit',  9,  'Virement épargne',              'validee'),
(54, 1, '2024-04-25 09:30:00', 22.50,   'debit',  11, 'Pharmacie',                     'validee'),
-- Alice — Mai 2024
(55, 1, '2024-05-02 09:00:00', 2850.00, 'credit', 1,  'Salaire mai',                   'validee'),
(56, 1, '2024-05-03 14:00:00', 850.00,  'debit',  5,  'Loyer mai',                     'validee'),
(57, 1, '2024-05-06 12:00:00', 88.40,   'debit',  3,  'Courses Carrefour',             'validee'),
(58, 1, '2024-05-10 08:00:00', 75.00,   'debit',  4,  'Abonnement Navigo',             'validee'),
(59, 1, '2024-05-15 10:00:00', 15.99,   'debit',  8,  'Netflix',                       'validee'),
(60, 1, '2024-05-17 20:00:00', 95.00,   'debit',  7,  'Restaurant anniversaire',       'validee'),
(61, 1, '2024-05-20 16:00:00', 250.00,  'debit',  9,  'Virement épargne',              'validee'),
-- Alice — Juin 2024
(62, 1, '2024-06-01 09:00:00', 2850.00, 'credit', 1,  'Salaire juin',                  'validee'),
(63, 1, '2024-06-03 14:00:00', 870.00,  'debit',  5,  'Loyer juin (régularisation)',    'validee'),
(64, 1, '2024-06-07 13:00:00', 103.20,  'debit',  3,  'Courses Monoprix',              'validee'),
(65, 1, '2024-06-12 19:30:00', 45.00,   'debit',  7,  'Restaurant Pho 14',             'validee'),
(66, 1, '2024-06-15 10:00:00', 15.99,   'debit',  8,  'Netflix',                       'validee'),
(67, 1, '2024-06-20 16:00:00', 250.00,  'debit',  9,  'Virement épargne',              'validee'),
(68, 1, '2024-06-22 10:00:00', 180.00,  'credit', 10, 'Remboursement Sécurité Sociale','validee'),
-- Bob — Avril à Juin 2024
(69,  2, '2024-04-02 09:00:00', 2200.00, 'credit', 1,  'Salaire avril',               'validee'),
(70,  2, '2024-04-04 15:00:00', 650.00,  'debit',  5,  'Loyer avril',                 'validee'),
(71,  2, '2024-04-08 18:30:00', 42.00,   'debit',  7,  'Restaurant Wok',              'validee'),
(72,  2, '2024-04-11 10:00:00', 58.90,   'debit',  3,  'Courses Lidl',                'validee'),
(73,  2, '2024-04-15 10:00:00', 9.99,    'debit',  8,  'Spotify',                     'validee'),
(74,  2, '2024-04-20 14:00:00', 600.00,  'credit', 2,  'Mission freelance UX',        'validee'),
(75,  2, '2024-05-02 09:00:00', 2300.00, 'credit', 1,  'Salaire mai (prime)',         'validee'),
(76,  2, '2024-05-04 15:00:00', 650.00,  'debit',  5,  'Loyer mai',                   'validee'),
(77,  2, '2024-05-09 12:00:00', 47.60,   'debit',  3,  'Courses Auchan',              'validee'),
(78,  2, '2024-05-14 20:00:00', 55.00,   'debit',  7,  'Restaurant italien',          'validee'),
(79,  2, '2024-05-15 10:00:00', 9.99,    'debit',  8,  'Spotify',                     'validee'),
(80,  2, '2024-06-02 09:00:00', 2200.00, 'credit', 1,  'Salaire juin',                'validee'),
(81,  2, '2024-06-04 15:00:00', 680.00,  'debit',  5,  'Loyer juin (charges)',         'validee'),
(82,  2, '2024-06-10 13:00:00', 63.10,   'debit',  3,  'Courses Franprix',            'validee'),
(83,  2, '2024-06-15 10:00:00', 9.99,    'debit',  8,  'Spotify',                     'validee'),
(84,  2, '2024-06-18 16:00:00', 450.00,  'credit', 2,  'Mission freelance mobile',    'validee'),
-- David (joint) — Avril à Juin 2024
(85,  4, '2024-04-02 09:00:00', 4500.00, 'credit', 1,  'Salaire David avril',         'validee'),
(86,  4, '2024-04-02 09:30:00', 2100.00, 'credit', 1,  'Salaire conjointe avril',     'validee'),
(87,  4, '2024-04-05 14:00:00', 1200.00, 'debit',  5,  'Loyer avril',                 'validee'),
(88,  4, '2024-04-07 17:00:00', 92.00,   'debit',  6,  'EDF facture avril',           'validee'),
(89,  4, '2024-04-12 12:00:00', 178.50,  'debit',  3,  'Courses familiales',          'validee'),
(90,  4, '2024-04-20 10:00:00', 500.00,  'debit',  9,  'Épargne mensuelle',           'validee'),
(91,  4, '2024-05-02 09:00:00', 4500.00, 'credit', 1,  'Salaire David mai',           'validee'),
(92,  4, '2024-05-02 09:30:00', 2200.00, 'credit', 1,  'Salaire conjointe mai (prime)','validee'),
(93,  4, '2024-05-05 14:00:00', 1200.00, 'debit',  5,  'Loyer mai',                   'validee'),
(94,  4, '2024-05-10 12:00:00', 195.00,  'debit',  3,  'Courses familiales',          'validee'),
(95,  4, '2024-05-15 20:00:00', 130.00,  'debit',  7,  'Restaurant famille',          'validee'),
(96,  4, '2024-05-20 10:00:00', 500.00,  'debit',  9,  'Épargne mensuelle',           'validee'),
(97,  4, '2024-06-02 09:00:00', 4500.00, 'credit', 1,  'Salaire David juin',          'validee'),
(98,  4, '2024-06-02 09:30:00', 2100.00, 'credit', 1,  'Salaire conjointe juin',      'validee'),
(99,  4, '2024-06-05 14:00:00', 1200.00, 'debit',  5,  'Loyer juin',                  'validee'),
(100, 4, '2024-06-08 17:00:00', 88.00,   'debit',  6,  'EDF facture juin',            'validee'),
(101, 4, '2024-06-14 12:00:00', 210.30,  'debit',  3,  'Courses familiales',          'validee'),
(102, 4, '2024-06-20 10:00:00', 600.00,  'debit',  9,  'Épargne mensuelle (augmentée)','validee');

-- ============================================
-- BUDGETS COMPLÉMENTAIRES (avril–juin 2024)
-- ============================================

INSERT INTO raw_budgets (id, compte_id, categorie_id, mois, montant_prevu) VALUES
(26, 1, 3,  '2024-04-01', 160.00),
(27, 1, 4,  '2024-04-01', 80.00),
(28, 1, 5,  '2024-04-01', 850.00),
(29, 1, 7,  '2024-04-01', 50.00),
(30, 1, 8,  '2024-04-01', 20.00),
(31, 1, 9,  '2024-04-01', 250.00),
(32, 1, 12, '2024-04-01', 70.00),
(33, 1, 3,  '2024-05-01', 160.00),
(34, 1, 5,  '2024-05-01', 850.00),
(35, 1, 7,  '2024-05-01', 60.00),
(36, 1, 8,  '2024-05-01', 20.00),
(37, 1, 9,  '2024-05-01', 250.00),
(38, 1, 3,  '2024-06-01', 170.00),
(39, 1, 5,  '2024-06-01', 870.00),
(40, 1, 7,  '2024-06-01', 60.00),
(41, 1, 8,  '2024-06-01', 20.00),
(42, 1, 9,  '2024-06-01', 250.00),
(43, 2, 3,  '2024-04-01', 100.00),
(44, 2, 5,  '2024-04-01', 650.00),
(45, 2, 7,  '2024-04-01', 50.00),
(46, 2, 8,  '2024-04-01', 15.00),
(47, 2, 3,  '2024-05-01', 100.00),
(48, 2, 5,  '2024-05-01', 650.00),
(49, 2, 7,  '2024-05-01', 60.00),
(50, 2, 8,  '2024-05-01', 15.00);
