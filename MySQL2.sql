-- =====================================================================
-- Syllabus: 1 JOINs (INNER, LEFT, RIGHT, CROSS, SELF, FULL emulation, anti/semi) | 2 Subqueries (scalar, IN, EXISTS,
-- correlated, derived) | 3 Set operations | 4 CASE & conditional aggregation (pivot) | 5 String functions
-- 6 Numeric functions | 7 Date & time functions | 8 NULL handling & casting | 9 GROUP BY ... WITH ROLLUP, GROUP_CONCAT
-- 10 Database design: ER, normalisation 1NF-3NF, keys, referential actions | 11 JSON basics | 12 Temporary tables
-- 13 Business queries on CLV data
-- =====================================================================
USE clv_db;

-- ---------- 1. JOINS ----------
-- INNER: rows that match in both tables
SELECT t.order_id, c.country AS cust_country, p.category, t.line_revenue
FROM fact_transactions t
INNER JOIN dim_customer c ON c.customer_id = t.customer_id
INNER JOIN dim_product  p ON p.product_id  = t.product_id LIMIT 20;
-- LEFT: all left rows (+ NULL when no match)  -> customers with/without purchases
SELECT c.customer_id, COUNT(t.line_id) AS lines FROM dim_customer c
LEFT JOIN fact_transactions t ON t.customer_id = c.customer_id GROUP BY c.customer_id ORDER BY lines LIMIT 10;
-- ANTI JOIN: left rows with NO match
SELECT c.customer_id FROM dim_customer c LEFT JOIN fact_transactions t USING (customer_id) WHERE t.customer_id IS NULL;
-- RIGHT JOIN (mirror of LEFT)
SELECT p.product_id, COUNT(t.line_id) FROM fact_transactions t RIGHT JOIN dim_product p USING (product_id) GROUP BY p.product_id;
-- CROSS JOIN: cartesian product (build a full calendar x segment grid)
SELECT s.seg, m.mth FROM (SELECT 'Gold' seg UNION SELECT 'Silver') s CROSS JOIN (SELECT 1 mth UNION SELECT 2 UNION SELECT 3) m;
-- SELF JOIN: compare rows of the same table (customers who signed up the same day)
SELECT a.customer_id AS c1, b.customer_id AS c2, a.signup_date
FROM dim_customer a JOIN dim_customer b ON a.signup_date = b.signup_date AND a.customer_id < b.customer_id LIMIT 10;
-- FULL OUTER JOIN does not exist in MySQL -> emulate
SELECT c.customer_id, t.order_id FROM dim_customer c LEFT JOIN fact_transactions t USING (customer_id)
UNION
SELECT c.customer_id, t.order_id FROM dim_customer c RIGHT JOIN fact_transactions t USING (customer_id);
-- NON-EQUI join: bucket revenue into bands
SELECT b.band, COUNT(*) FROM (SELECT customer_id, SUM(line_revenue) s FROM fact_transactions GROUP BY customer_id) x
JOIN (SELECT 'low' band, 0 lo, 500 hi UNION SELECT 'mid', 500, 2000 UNION SELECT 'high', 2000, 1e9) b ON x.s >= b.lo AND x.s < b.hi GROUP BY b.band;
-- NATURAL JOIN / USING / multi-table
SELECT * FROM clv_predictions NATURAL JOIN dim_customer LIMIT 5;

-- ---------- 2. SUBQUERIES ----------
-- scalar subquery
SELECT customer_id, SUM(line_revenue) spend FROM fact_transactions GROUP BY customer_id
HAVING spend > (SELECT AVG(s) FROM (SELECT SUM(line_revenue) s FROM fact_transactions GROUP BY customer_id) a) ORDER BY spend DESC LIMIT 10;
-- IN / NOT IN (beware NULLs in NOT IN -> prefer NOT EXISTS)
SELECT * FROM dim_customer WHERE customer_id IN (SELECT customer_id FROM fact_transactions WHERE line_revenue > 500);
-- EXISTS (semi-join, usually fastest)
SELECT * FROM dim_customer c WHERE EXISTS (SELECT 1 FROM fact_transactions t WHERE t.customer_id = c.customer_id AND t.order_channel = 'App');
SELECT * FROM dim_customer c WHERE NOT EXISTS (SELECT 1 FROM fact_transactions t WHERE t.customer_id = c.customer_id);
-- correlated subquery: each customer's largest line vs country average
SELECT t.customer_id, t.line_revenue FROM fact_transactions t
WHERE t.line_revenue = (SELECT MAX(x.line_revenue) FROM fact_transactions x WHERE x.customer_id = t.customer_id) LIMIT 10;
-- derived table (subquery in FROM)
SELECT country, ROUND(AVG(spend),2) avg_cust_spend FROM
   (SELECT c.country, t.customer_id, SUM(t.line_revenue) spend FROM fact_transactions t JOIN dim_customer c USING (customer_id) GROUP BY 1,2) d
GROUP BY country;
-- ANY / ALL
SELECT * FROM dim_product WHERE unit_price > ALL (SELECT unit_price FROM dim_product WHERE category = 'Books');

-- ---------- 3. SET OPERATIONS ----------
SELECT customer_id FROM fact_transactions WHERE order_channel = 'App'
UNION SELECT customer_id FROM fact_transactions WHERE order_channel = 'Store';                -- distinct union
SELECT country FROM dim_customer UNION ALL SELECT country FROM fact_transactions;             -- keep duplicates (faster)
SELECT customer_id FROM fact_transactions WHERE order_channel = 'App'
INTERSECT SELECT customer_id FROM fact_transactions WHERE order_channel = 'Web';              -- MySQL 8.0.31+
SELECT customer_id FROM dim_customer EXCEPT SELECT customer_id FROM fact_transactions;        -- MySQL 8.0.31+

-- ---------- 4. CASE & CONDITIONAL AGGREGATION ----------
SELECT customer_id, SUM(line_revenue) spend,
  CASE WHEN SUM(line_revenue) >= 2000 THEN 'Platinum' WHEN SUM(line_revenue) >= 1000 THEN 'Gold'
       WHEN SUM(line_revenue) >= 300 THEN 'Silver' ELSE 'Bronze' END AS tier
FROM fact_transactions GROUP BY customer_id LIMIT 20;
-- pivot: channels as columns
SELECT YEAR(order_date) yr,
       SUM(CASE WHEN order_channel = 'Web'   THEN line_revenue ELSE 0 END) web,
       SUM(CASE WHEN order_channel = 'App'   THEN line_revenue ELSE 0 END) app,
       SUM(CASE WHEN order_channel = 'Store' THEN line_revenue ELSE 0 END) store,
       SUM(line_revenue = line_revenue) AS lines_all, SUM(quantity > 2) AS big_qty_lines
FROM fact_transactions GROUP BY yr;
SELECT country, COUNT(DISTINCT CASE WHEN order_channel='App' THEN customer_id END) AS app_customers FROM fact_transactions GROUP BY country;

-- ---------- 5. STRING FUNCTIONS ----------
SELECT CONCAT_WS('|', country, acquisition_channel), CHAR_LENGTH(country), LEFT(country,2), RIGHT(country,2), LPAD(customer_id,6,'0'),
       REVERSE(country), LOCATE('d', country), INSTR(country,'a'), SUBSTRING_INDEX('a@b.com','@',-1), REPEAT('*',3),
       FORMAT(1234567.891,2), UPPER(LEFT(country,1)), TRIM(BOTH 'x' FROM 'xxabcxx'), SPACE(2), STRCMP('a','b')
FROM dim_customer LIMIT 3;
SELECT product_name, REGEXP_SUBSTR(product_name,'[0-9]+') num, REGEXP_REPLACE(product_name,'[0-9]','#') masked FROM dim_product LIMIT 3;

-- ---------- 6. NUMERIC FUNCTIONS ----------
SELECT ROUND(123.456,-1), ROUND(2.5), CEILING(-1.5), FLOOR(-1.5), SQRT(16), POWER(2,10), LOG(100), LOG10(100), EXP(1), SIGN(-3),
       GREATEST(1,5,3), LEAST(4,2,8), CONV(255,10,16), PI(), FORMAT(0.123456,3), CAST(10/3 AS DECIMAL(5,2));

-- ---------- 7. DATE & TIME FUNCTIONS ----------
SELECT NOW(), CURDATE(), CURTIME(), UTC_TIMESTAMP(), DATE('2025-06-30 14:00:00'), TIME('2025-06-30 14:00:00');
SELECT YEAR(d), MONTH(d), DAY(d), QUARTER(d), WEEK(d), DAYOFWEEK(d), DAYNAME(d), MONTHNAME(d), LAST_DAY(d), DAYOFYEAR(d)
FROM (SELECT DATE('2025-06-30') d) x;
SELECT DATE_ADD('2025-06-30', INTERVAL 1 MONTH), DATE_SUB('2025-06-30', INTERVAL 7 DAY), ADDDATE('2025-06-30', 5),
       DATEDIFF('2025-12-31','2025-06-30'), TIMESTAMPDIFF(MONTH,'2024-01-15','2025-06-30'), PERIOD_DIFF(202512,202506),
       DATE_FORMAT('2025-06-30','%Y-%m-%d %W %b'), STR_TO_DATE('30/06/2025','%d/%m/%Y'), EXTRACT(YEAR_MONTH FROM '2025-06-30'),
       DATE_FORMAT('2025-06-30','%Y-%m-01') AS month_start, UNIX_TIMESTAMP('2025-06-30'), FROM_UNIXTIME(1751241600);
-- monthly revenue + first day of month grouping (index-friendly range filters instead of YEAR(col)=2025)
SELECT DATE_FORMAT(order_date,'%Y-%m') ym, SUM(line_revenue) rev FROM fact_transactions
WHERE order_date >= '2025-01-01' AND order_date < '2026-01-01' GROUP BY ym ORDER BY ym;

-- ---------- 8. NULL HANDLING & CASTING ----------
SELECT COALESCE(gender,'Unknown'), IFNULL(country,'n/a'), NULLIF(0,0), ISNULL(NULL), NULL IS NULL, NULL <=> NULL FROM dim_customer LIMIT 2;
SELECT CAST('123' AS UNSIGNED), CAST(123.456 AS CHAR), CONVERT('2025-06-30', DATE), CAST('abc' AS SIGNED) AS bad_cast, '5'+'5', CONCAT(5,5);
-- aggregates ignore NULL; COUNT(*) counts rows; AVG(col) divides by non-null count only.

-- ---------- 9. ROLLUP, GROUP_CONCAT, DISTINCT aggregates ----------
SELECT IFNULL(country,'ALL COUNTRIES') country, IFNULL(order_channel,'ALL CHANNELS') channel, ROUND(SUM(line_revenue)) rev
FROM fact_transactions GROUP BY country, order_channel WITH ROLLUP;                  -- sub-totals & grand total
SELECT country, GROUP_CONCAT(DISTINCT acquisition_channel ORDER BY acquisition_channel SEPARATOR ', ') channels, COUNT(*) n
FROM dim_customer GROUP BY country;
SELECT COUNT(DISTINCT customer_id) cust, SUM(DISTINCT quantity) FROM fact_transactions;

-- ---------- 10. DATABASE DESIGN ----------
-- ER: entity (table) / attribute (column) / relationship (1:1, 1:N, M:N via bridge table)
-- Keys: PRIMARY (unique, not null) | CANDIDATE | ALTERNATE (UNIQUE) | FOREIGN | COMPOSITE | SURROGATE (AUTO_INCREMENT) vs NATURAL
-- 1NF: atomic values, no repeating groups  -> no "tags = 'a,b,c'" columns; use a child table
-- 2NF: 1NF + no partial dependency on part of a composite key
-- 3NF: 2NF + no transitive dependency (non-key column depends only on the key)  -> customer country lives in dim_customer, not repeated per order
-- Star schema = denormalised facts+dimensions for analytics; OLTP = normalised; choose per workload.
CREATE TABLE IF NOT EXISTS customer_tag (                     -- M:N example with composite PK
    customer_id INT NOT NULL, tag VARCHAR(30) NOT NULL, PRIMARY KEY (customer_id, tag),
    FOREIGN KEY (customer_id) REFERENCES dim_customer(customer_id) ON DELETE CASCADE ON UPDATE CASCADE);
-- Referential actions: RESTRICT | NO ACTION | CASCADE | SET NULL | SET DEFAULT(unsupported in InnoDB)
ALTER TABLE customer_tag ADD INDEX idx_tag (tag);
SELECT table_name, constraint_name, constraint_type FROM information_schema.table_constraints WHERE table_schema = 'clv_db';

-- ---------- 11. JSON BASICS ----------
CREATE TABLE IF NOT EXISTS customer_profile (customer_id INT PRIMARY KEY, prefs JSON);
INSERT INTO customer_profile VALUES (1, '{"newsletter": true, "devices": ["ios","web"], "address": {"city": "Pune"}}')
ON DUPLICATE KEY UPDATE prefs = VALUES(prefs);
SELECT prefs->'$.address.city', prefs->>'$.address.city', JSON_EXTRACT(prefs,'$.devices[0]'), JSON_LENGTH(prefs->'$.devices'),
       JSON_CONTAINS(prefs->'$.devices','"ios"'), JSON_KEYS(prefs) FROM customer_profile;
UPDATE customer_profile SET prefs = JSON_SET(prefs, '$.newsletter', false, '$.tier', 'Gold');

-- ---------- 12. TEMPORARY TABLES & INSERT...SELECT ----------
CREATE TEMPORARY TABLE tmp_spend AS SELECT customer_id, SUM(line_revenue) spend FROM fact_transactions GROUP BY customer_id;
SELECT COUNT(*), AVG(spend) FROM tmp_spend;   DROP TEMPORARY TABLE tmp_spend;
CREATE TABLE IF NOT EXISTS customer_spend_snapshot AS SELECT customer_id, SUM(line_revenue) spend, CURDATE() snap_date FROM fact_transactions GROUP BY customer_id;

-- ---------- 13. BUSINESS QUESTIONS ----------
-- Q1 Monthly revenue, orders, AOV
SELECT DATE_FORMAT(order_date,'%Y-%m') ym, COUNT(DISTINCT order_id) orders, ROUND(SUM(line_revenue)) revenue,
       ROUND(SUM(line_revenue)/COUNT(DISTINCT order_id),2) aov FROM fact_transactions GROUP BY ym ORDER BY ym;
-- Q2 Repeat-customer rate
SELECT ROUND(100*SUM(n > 1)/COUNT(*),1) AS repeat_rate_pct FROM (SELECT customer_id, COUNT(DISTINCT order_id) n FROM fact_transactions GROUP BY customer_id) x;
-- Q3 Category x channel revenue matrix
SELECT p.category, SUM(CASE WHEN c.acquisition_channel='Organic' THEN t.line_revenue END) organic,
       SUM(CASE WHEN c.acquisition_channel='Paid Search' THEN t.line_revenue END) paid
FROM fact_transactions t JOIN dim_product p USING (product_id) JOIN dim_customer c USING (customer_id) GROUP BY p.category;
-- Q4 Customers whose last purchase is more than 180 days before the data end (churn candidates)
SELECT customer_id, MAX(order_date) last_dt, DATEDIFF((SELECT MAX(order_date) FROM fact_transactions), MAX(order_date)) idle_days
FROM fact_transactions GROUP BY customer_id HAVING idle_days > 180 ORDER BY idle_days DESC LIMIT 20;
