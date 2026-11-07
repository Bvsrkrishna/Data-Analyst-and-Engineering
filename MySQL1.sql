-- =====================================================================
-- Syllabus: 1 RDBMS concepts | 2 Server & database commands | 3 Data types | 4 CREATE TABLE & constraints
-- 5 ALTER / DROP / TRUNCATE | 6 INSERT / UPDATE / DELETE / REPLACE / UPSERT | 7 LOAD DATA
-- 8 SELECT, WHERE, operators | 9 ORDER BY, LIMIT, DISTINCT | 10 Aggregates, GROUP BY, HAVING
-- 11 Built-in functions (intro) | 12 Logical execution order | 13 Comments & good practice
-- Run: mysql -u root -p --local-infile=1 < 08_mysql_basics.sql    (or paste into MySQL Workbench)
-- =====================================================================

-- ---------- 1. CONCEPTS ----------
-- Database > Tables > Rows (records) x Columns (fields). PRIMARY KEY identifies a row; FOREIGN KEY links tables.
-- SQL families: DDL (CREATE/ALTER/DROP/TRUNCATE) | DML (INSERT/UPDATE/DELETE) | DQL (SELECT)
--               DCL (GRANT/REVOKE) | TCL (COMMIT/ROLLBACK/SAVEPOINT)
-- Our model (star schema):  dim_customer 1--* fact_transactions *--1 dim_product ;  clv_predictions 1--1 dim_customer

-- ---------- 2. SERVER & DATABASE COMMANDS ----------
SELECT VERSION(), CURRENT_USER(), DATABASE(), NOW();
SHOW DATABASES;
CREATE DATABASE IF NOT EXISTS clv_db CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE clv_db;
SHOW TABLES;
-- DROP DATABASE clv_db;      -- destructive!

-- ---------- 3. DATA TYPES ----------
-- Integer : TINYINT(1B) SMALLINT(2) MEDIUMINT(3) INT(4) BIGINT(8)   [UNSIGNED doubles the positive range]
-- Exact   : DECIMAL(p,s)  -> money.      Approx: FLOAT, DOUBLE  -> never for currency
-- String  : CHAR(n) fixed | VARCHAR(n) variable | TEXT/MEDIUMTEXT/LONGTEXT | ENUM('a','b') | SET(...)
-- Binary  : BLOB, VARBINARY
-- Date    : DATE | TIME | DATETIME (no TZ) | TIMESTAMP (UTC-converted) | YEAR
-- Other   : BOOLEAN (=TINYINT(1)) | JSON | GEOMETRY
CREATE TABLE IF NOT EXISTS demo_types (
    id        INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    flag      BOOLEAN DEFAULT TRUE,
    price     DECIMAL(10,2),
    ratio     DOUBLE,
    code      CHAR(3),
    title     VARCHAR(100),
    notes     TEXT,
    tier      ENUM('Bronze','Silver','Gold','Platinum') DEFAULT 'Bronze',
    created   DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated   TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    attrs     JSON
);

-- ---------- 4. CREATE TABLE + CONSTRAINTS ----------
-- PRIMARY KEY, NOT NULL, UNIQUE, DEFAULT, CHECK, FOREIGN KEY, AUTO_INCREMENT
CREATE TABLE IF NOT EXISTS dim_customer (
    customer_id         INT          PRIMARY KEY,
    signup_date         DATE         NOT NULL,
    country             VARCHAR(40),
    acquisition_channel VARCHAR(40),
    age                 TINYINT UNSIGNED CHECK (age BETWEEN 16 AND 100),
    gender              CHAR(5)
);
CREATE TABLE IF NOT EXISTS dim_product (
    product_id   INT PRIMARY KEY,
    product_name VARCHAR(80) NOT NULL,
    category     VARCHAR(40),
    unit_price   DECIMAL(10,2) CHECK (unit_price > 0)
);
CREATE TABLE IF NOT EXISTS fact_transactions (
    line_id       BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_id      INT           NOT NULL,
    customer_id   INT           NOT NULL,
    product_id    INT           NOT NULL,
    order_date    DATE          NOT NULL,
    quantity      INT           NOT NULL CHECK (quantity > 0),
    unit_price    DECIMAL(10,2) NOT NULL,
    discount      DECIMAL(4,2)  DEFAULT 0,
    line_revenue  DECIMAL(12,2) NOT NULL,
    country       VARCHAR(40),
    order_channel VARCHAR(20),
    CONSTRAINT fk_tx_cust FOREIGN KEY (customer_id) REFERENCES dim_customer(customer_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_tx_prod FOREIGN KEY (product_id)  REFERENCES dim_product(product_id)
);
CREATE TABLE IF NOT EXISTS clv_predictions (
    customer_id      INT PRIMARY KEY,
    recency_days     INT, frequency INT, monetary DECIMAL(12,2),
    predicted_clv_6m DECIMAL(12,2), clv_segment VARCHAR(20),
    scored_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (customer_id) REFERENCES dim_customer(customer_id)
);
CREATE TABLE IF NOT EXISTS etl_audit (
    run_id INT AUTO_INCREMENT PRIMARY KEY, run_ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    step VARCHAR(50), rows_in INT, rows_out INT, status VARCHAR(20)
);
DESCRIBE fact_transactions;  SHOW CREATE TABLE dim_customer;  SHOW COLUMNS FROM dim_product;

-- ---------- 5. ALTER / RENAME / DROP / TRUNCATE ----------
ALTER TABLE demo_types ADD COLUMN extra VARCHAR(20) AFTER code;
ALTER TABLE demo_types MODIFY COLUMN extra VARCHAR(50) NOT NULL DEFAULT '';
ALTER TABLE demo_types CHANGE COLUMN extra extra_info VARCHAR(50);          -- rename + retype
ALTER TABLE demo_types RENAME COLUMN extra_info TO info;
ALTER TABLE demo_types ADD UNIQUE KEY uq_code (code);
ALTER TABLE demo_types DROP INDEX uq_code;
ALTER TABLE demo_types DROP COLUMN info;
RENAME TABLE demo_types TO demo_types_old;
TRUNCATE TABLE demo_types_old;            -- empties the table, resets AUTO_INCREMENT, cannot be rolled back
DROP TABLE IF EXISTS demo_types_old;

-- ---------- 6. DML ----------
INSERT INTO dim_product (product_id, product_name, category, unit_price) VALUES (9001, 'Demo Mug', 'Home', 7.50);
INSERT INTO dim_product VALUES (9002, 'Demo Pen', 'Books', 2.25), (9003, 'Demo Cap', 'Fashion', 12.00);   -- multi-row
INSERT INTO dim_product (product_id, product_name, category, unit_price)
       SELECT product_id + 10000, CONCAT(product_name, ' copy'), category, unit_price FROM dim_product WHERE product_id = 9001;
UPDATE dim_product SET unit_price = unit_price * 1.10 WHERE category = 'Home' AND product_id > 9000;
UPDATE dim_product SET category = 'Misc', unit_price = 1.00 WHERE product_id = 9002;
INSERT INTO dim_product VALUES (9001, 'Demo Mug v2', 'Home', 8.00)
       ON DUPLICATE KEY UPDATE product_name = VALUES(product_name), unit_price = VALUES(unit_price);       -- UPSERT
REPLACE INTO dim_product VALUES (9003, 'Demo Cap 2', 'Fashion', 13.00);                                     -- delete+insert
INSERT IGNORE INTO dim_product VALUES (9003, 'ignored', 'x', 1);                                            -- skip duplicates
DELETE FROM dim_product WHERE product_id >= 9000;
-- Safe-update habit: SELECT first with the same WHERE, then run UPDATE/DELETE.  SET SQL_SAFE_UPDATES = 1;

-- ---------- 7. LOAD DATA (bulk import of the CSVs created by file 11) ----------
-- SET GLOBAL local_infile = 1;
-- LOAD DATA LOCAL INFILE 'data/processed/customers_clean.csv' INTO TABLE dim_customer
--   FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 LINES
--   (customer_id, signup_date, country, acquisition_channel, age, gender);
-- (file 11_etl_pipeline.py performs the same load automatically through SQLAlchemy.)
-- Export: SELECT * FROM dim_customer INTO OUTFILE '/var/lib/mysql-files/cust.csv' FIELDS TERMINATED BY ',';

-- ---------- 8. SELECT, WHERE & OPERATORS ----------
SELECT * FROM dim_customer LIMIT 10;
SELECT customer_id AS id, country AS ctry, age + 1 AS next_age FROM dim_customer;                 -- aliases, expressions
SELECT * FROM dim_customer WHERE country = 'India' AND age >= 30;                                  -- AND
SELECT * FROM dim_customer WHERE country = 'India' OR country = 'UK';                              -- OR
SELECT * FROM dim_customer WHERE NOT country = 'India';                                            -- NOT
SELECT * FROM dim_customer WHERE country IN ('India', 'USA', 'UK');                                -- IN
SELECT * FROM dim_customer WHERE age BETWEEN 25 AND 40;                                            -- BETWEEN (inclusive)
SELECT * FROM dim_customer WHERE acquisition_channel LIKE 'P%';                                    -- % any chars
SELECT * FROM dim_customer WHERE country LIKE '_SA';                                               -- _ one char
SELECT * FROM dim_customer WHERE gender IS NULL;   SELECT * FROM dim_customer WHERE gender IS NOT NULL;
SELECT * FROM dim_customer WHERE country REGEXP '^(In|US)';                                        -- regex
SELECT 10 + 3, 10 - 3, 10 * 3, 10 / 3, 10 DIV 3, 10 % 3, MOD(10,3), POW(2,3), 5 <=> NULL, NULL = NULL;   -- operators; NULL needs IS NULL

-- ---------- 9. ORDER BY, LIMIT, OFFSET, DISTINCT ----------
SELECT DISTINCT country FROM dim_customer ORDER BY country;
SELECT DISTINCT country, acquisition_channel FROM dim_customer;
SELECT * FROM dim_customer ORDER BY country ASC, age DESC LIMIT 5;
SELECT * FROM dim_customer ORDER BY signup_date DESC LIMIT 5 OFFSET 10;       -- pagination: page 3 of size 5
SELECT * FROM dim_customer ORDER BY RAND() LIMIT 3;                            -- random sample
SELECT customer_id FROM dim_customer ORDER BY FIELD(country,'India','USA') DESC, 1 LIMIT 5;   -- custom order

-- ---------- 10. AGGREGATES, GROUP BY, HAVING ----------
SELECT COUNT(*) AS lines, COUNT(DISTINCT order_id) AS orders, COUNT(DISTINCT customer_id) AS customers,
       SUM(line_revenue) AS revenue, AVG(line_revenue) AS avg_line, MIN(order_date) AS first_dt,
       MAX(order_date) AS last_dt, STDDEV(line_revenue) AS sd, VARIANCE(line_revenue) AS var_
FROM fact_transactions;
SELECT country, COUNT(*) n, ROUND(SUM(line_revenue),0) revenue FROM fact_transactions GROUP BY country ORDER BY revenue DESC;
SELECT country, order_channel, SUM(line_revenue) rev FROM fact_transactions GROUP BY country, order_channel;
SELECT customer_id, SUM(line_revenue) AS spend FROM fact_transactions
GROUP BY customer_id HAVING spend > 2000 AND COUNT(*) >= 5 ORDER BY spend DESC LIMIT 10;   -- HAVING filters groups, WHERE filters rows
SELECT COUNT(*) AS all_rows, COUNT(gender) AS non_null_gender, COUNT(DISTINCT gender) AS distinct_gender FROM dim_customer;

-- ---------- 11. BUILT-IN FUNCTIONS (intro; more in file 09) ----------
SELECT UPPER('clv'), LOWER('CLV'), LENGTH('abc'), CONCAT('a','-','b'), SUBSTRING('Lifetime',1,4), TRIM('  x  '), REPLACE('a-b','-','_');
SELECT ROUND(3.14159,2), CEIL(2.1), FLOOR(2.9), ABS(-5), TRUNCATE(9.999,1), RAND();
SELECT CURDATE(), NOW(), YEAR(NOW()), MONTH(NOW()), DAYNAME(NOW()), DATE_ADD(CURDATE(), INTERVAL 30 DAY), DATEDIFF('2025-12-31','2025-06-30');
SELECT IF(1 > 0, 'yes', 'no'), IFNULL(NULL, 'default'), COALESCE(NULL, NULL, 3);

-- ---------- 12. LOGICAL ORDER OF EXECUTION ----------
-- FROM/JOIN -> WHERE -> GROUP BY -> HAVING -> SELECT (aliases born here) -> DISTINCT -> ORDER BY -> LIMIT
-- So you cannot use a SELECT alias in WHERE (MySQL allows it in GROUP BY/HAVING/ORDER BY as an extension).

-- ---------- 13. GOOD PRACTICE ----------
-- * Name things consistently (snake_case); avoid SELECT * in production; always have a PRIMARY KEY.
-- * DECIMAL for money; DATE for dates (not strings); use utf8mb4.
-- * Comment styles:   -- line     # line     /* block */
