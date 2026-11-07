-- =====================================================================
-- Syllabus: 1 CTEs & recursive CTEs | 2 Window functions (ranking, offset, aggregate, frames, NTILE, distribution)
-- 3 RFM / cohort / retention / CLV analytics | 4 Views | 5 Indexes | 6 EXPLAIN & query tuning
-- 7 Stored procedures (IN/OUT, control flow, loops, cursors, handlers, SIGNAL) | 8 Stored functions | 9 Triggers
-- 10 Events | 11 Transactions, ACID, isolation levels, locking, deadlocks | 12 Prepared statements / dynamic SQL
-- 13 Generated columns | 14 Partitioning | 15 Full-text search | 16 Users, roles & privileges
-- 17 Backup/restore & import/export | 18 Monitoring & maintenance | 19 Security | 20 Replication/HA overview
-- =====================================================================
USE clv_db;

-- ================= 1. CTEs =================
WITH orders AS (SELECT order_id, customer_id, order_date, SUM(line_revenue) AS order_value
                FROM fact_transactions GROUP BY order_id, customer_id, order_date),
     cust   AS (SELECT customer_id, COUNT(*) n_orders, AVG(order_value) aov FROM orders GROUP BY customer_id)
SELECT * FROM cust ORDER BY n_orders DESC LIMIT 10;
-- Recursive CTE 1: generate a calendar (fills gaps in time series)
WITH RECURSIVE cal AS (SELECT DATE('2024-01-01') d UNION ALL SELECT d + INTERVAL 1 DAY FROM cal WHERE d < '2025-12-31')
SELECT DATE_FORMAT(c.d,'%Y-%m') ym, COALESCE(SUM(t.line_revenue),0) revenue
FROM cal c LEFT JOIN fact_transactions t ON t.order_date = c.d GROUP BY ym;
-- Recursive CTE 2: hierarchy (category tree / org chart) - demo table
CREATE TABLE IF NOT EXISTS category_tree (id INT PRIMARY KEY, name VARCHAR(40), parent_id INT);
INSERT IGNORE INTO category_tree VALUES (1,'All',NULL),(2,'Electronics',1),(3,'Phones',2),(4,'Laptops',2),(5,'Home',1);
WITH RECURSIVE t AS (SELECT id, name, parent_id, 0 lvl, CAST(name AS CHAR(200)) path FROM category_tree WHERE parent_id IS NULL
                     UNION ALL SELECT c.id, c.name, c.parent_id, t.lvl+1, CONCAT(t.path,' > ',c.name) FROM category_tree c JOIN t ON c.parent_id = t.id)
SELECT * FROM t ORDER BY path;

-- ================= 2. WINDOW FUNCTIONS =================
-- syntax: func() OVER (PARTITION BY ... ORDER BY ... [ROWS|RANGE BETWEEN ...])
WITH o AS (SELECT order_id, customer_id, order_date, SUM(line_revenue) order_value
           FROM fact_transactions GROUP BY order_id, customer_id, order_date)
SELECT customer_id, order_id, order_date, order_value,
   ROW_NUMBER() OVER w AS rn,                                        -- unique sequence
   RANK()       OVER (PARTITION BY customer_id ORDER BY order_value DESC) AS rnk,        -- gaps after ties
   DENSE_RANK() OVER (PARTITION BY customer_id ORDER BY order_value DESC) AS drnk,       -- no gaps
   LAG(order_date)  OVER w AS prev_date,  LEAD(order_date) OVER w AS next_date,
   DATEDIFF(order_date, LAG(order_date) OVER w) AS gap_days,
   FIRST_VALUE(order_value) OVER w AS first_val,
   LAST_VALUE(order_value)  OVER (PARTITION BY customer_id ORDER BY order_date, order_id ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_val,
   NTH_VALUE(order_value,2) OVER w AS second_val,
   SUM(order_value) OVER (PARTITION BY customer_id ORDER BY order_date, order_id ROWS UNBOUNDED PRECEDING) AS running_total,
   AVG(order_value) OVER (PARTITION BY customer_id ORDER BY order_date, order_id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS moving_avg3,
   order_value / SUM(order_value) OVER (PARTITION BY customer_id) AS share_of_customer,
   NTILE(4) OVER (ORDER BY order_value) AS quartile,
   PERCENT_RANK() OVER (ORDER BY order_value) AS pct_rank, CUME_DIST() OVER (ORDER BY order_value) AS cume_dist
FROM o WINDOW w AS (PARTITION BY customer_id ORDER BY order_date, order_id) ORDER BY customer_id, rn LIMIT 30;
-- Top-N per group
SELECT * FROM (SELECT c.country, t.customer_id, ROUND(SUM(t.line_revenue)) spend,
          DENSE_RANK() OVER (PARTITION BY c.country ORDER BY SUM(t.line_revenue) DESC) rnk
          FROM fact_transactions t JOIN dim_customer c USING (customer_id) GROUP BY c.country, t.customer_id) r WHERE rnk <= 3;
-- De-duplication keeping the latest row
WITH d AS (SELECT line_id, ROW_NUMBER() OVER (PARTITION BY order_id, product_id ORDER BY line_id DESC) rn FROM fact_transactions)
SELECT COUNT(*) AS duplicate_lines FROM d WHERE rn > 1;
-- Month-over-month, YoY, rolling 3m
WITH m AS (SELECT DATE_FORMAT(order_date,'%Y-%m-01') ym, SUM(line_revenue) rev FROM fact_transactions GROUP BY ym)
SELECT ym, ROUND(rev) rev, ROUND(100*(rev-LAG(rev) OVER (ORDER BY ym))/LAG(rev) OVER (ORDER BY ym),1) mom_pct,
       ROUND(100*(rev-LAG(rev,12) OVER (ORDER BY ym))/LAG(rev,12) OVER (ORDER BY ym),1) yoy_pct,
       ROUND(AVG(rev) OVER (ORDER BY ym ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)) ma3 FROM m;
-- Gaps & islands: consecutive active months per customer
WITH am AS (SELECT DISTINCT customer_id, TIMESTAMPDIFF(MONTH,'2024-01-01',order_date) mi FROM fact_transactions),
     g AS (SELECT customer_id, mi, mi - ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY mi) grp FROM am)
SELECT customer_id, MIN(mi) start_m, MAX(mi) end_m, COUNT(*) streak FROM g GROUP BY customer_id, grp HAVING streak >= 3 ORDER BY streak DESC LIMIT 10;

-- ================= 3. ANALYTICS: RFM, COHORTS, CLV =================
WITH snap AS (SELECT MAX(order_date) d FROM fact_transactions),
rfm AS (SELECT t.customer_id, DATEDIFF((SELECT d FROM snap), MAX(t.order_date)) recency, COUNT(DISTINCT t.order_id) frequency, SUM(t.line_revenue) monetary
        FROM fact_transactions t GROUP BY t.customer_id),
sc AS (SELECT *, NTILE(5) OVER (ORDER BY recency DESC) r, NTILE(5) OVER (ORDER BY frequency) f, NTILE(5) OVER (ORDER BY monetary) m FROM rfm)
SELECT *, CASE WHEN r>=4 AND f>=4 THEN 'Champions' WHEN r>=3 AND f>=3 THEN 'Loyal' WHEN r>=4 AND f<=2 THEN 'New / Promising'
               WHEN r<=2 AND f>=3 THEN 'At Risk' WHEN r<=2 AND f<=2 THEN 'Lost' ELSE 'Needs Attention' END AS rfm_segment FROM sc;
-- Cohort retention
WITH first_o AS (SELECT customer_id, DATE_FORMAT(MIN(order_date),'%Y-%m-01') cohort FROM fact_transactions GROUP BY customer_id),
act AS (SELECT DISTINCT customer_id, DATE_FORMAT(order_date,'%Y-%m-01') am FROM fact_transactions),
j AS (SELECT f.cohort, TIMESTAMPDIFF(MONTH, f.cohort, a.am) idx, COUNT(DISTINCT a.customer_id) active FROM first_o f JOIN act a USING (customer_id) GROUP BY 1,2)
SELECT cohort, idx, active, ROUND(100*active/FIRST_VALUE(active) OVER (PARTITION BY cohort ORDER BY idx),1) retention_pct FROM j ORDER BY cohort, idx;
-- Historical CLV with margin & Pareto
WITH c AS (SELECT customer_id, SUM(line_revenue) rev FROM fact_transactions GROUP BY customer_id),
r AS (SELECT customer_id, rev, SUM(rev) OVER (ORDER BY rev DESC) run, SUM(rev) OVER () tot, ROW_NUMBER() OVER (ORDER BY rev DESC) rk, COUNT(*) OVER () n FROM c)
SELECT customer_id, ROUND(rev) rev, ROUND(100*run/tot,1) cum_rev_pct, ROUND(100*rk/n,1) cum_cust_pct, ROUND(rev*0.30) gross_margin_30pct FROM r ORDER BY rev DESC LIMIT 20;

-- ================= 4. VIEWS =================
CREATE OR REPLACE VIEW vw_order_summary AS
SELECT order_id, customer_id, order_date, order_channel, SUM(line_revenue) order_value, SUM(quantity) units
FROM fact_transactions GROUP BY order_id, customer_id, order_date, order_channel;
CREATE OR REPLACE VIEW vw_customer_rfm AS
SELECT customer_id, MAX(order_date) last_order, COUNT(DISTINCT order_id) frequency, ROUND(SUM(line_revenue),2) monetary,
       DATEDIFF((SELECT MAX(order_date) FROM fact_transactions), MAX(order_date)) recency_days
FROM fact_transactions GROUP BY customer_id;
CREATE OR REPLACE VIEW vw_clv_dashboard AS                 -- feeds Power BI / Tableau
SELECT p.customer_id, c.country, c.acquisition_channel, c.age, c.gender, p.recency_days, p.frequency, p.monetary, p.predicted_clv_6m, p.clv_segment
FROM clv_predictions p JOIN dim_customer c USING (customer_id);
CREATE OR REPLACE VIEW vw_india_customers AS SELECT * FROM dim_customer WHERE country = 'India' WITH CHECK OPTION;   -- updatable + guarded
SHOW FULL TABLES WHERE Table_type = 'VIEW';  -- ALTER VIEW / DROP VIEW IF EXISTS vw_x;
-- Materialised-view pattern (MySQL has none): summary table refreshed by an event/proc
CREATE TABLE IF NOT EXISTS mv_monthly_revenue (ym CHAR(7) PRIMARY KEY, revenue DECIMAL(14,2), orders INT, refreshed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);

-- ================= 5. INDEXES =================
CREATE INDEX idx_tx_cust_date ON fact_transactions (customer_id, order_date);          -- composite: leftmost-prefix rule
CREATE INDEX idx_tx_date      ON fact_transactions (order_date);
CREATE INDEX idx_tx_order     ON fact_transactions (order_id);
CREATE INDEX idx_cust_ctry    ON dim_customer (country(20));                            -- prefix index
CREATE UNIQUE INDEX uq_prod_name ON dim_product (product_name);
CREATE INDEX idx_tx_cov ON fact_transactions (customer_id, order_date, line_revenue);   -- covering index (index-only scan)
CREATE INDEX idx_func ON fact_transactions ((YEAR(order_date)));                        -- functional index (8.0.13+)
ALTER TABLE fact_transactions ALTER INDEX idx_func INVISIBLE;                           -- test dropping safely
SHOW INDEX FROM fact_transactions;   -- DROP INDEX idx_func ON fact_transactions;
-- Rules: index columns in WHERE/JOIN/ORDER BY; high-selectivity first; avoid functions on indexed columns; too many indexes slow writes.

-- ================= 6. EXPLAIN & TUNING =================
EXPLAIN SELECT SUM(line_revenue) FROM fact_transactions WHERE customer_id = 100 AND order_date >= '2025-01-01';
EXPLAIN FORMAT=TREE SELECT c.country, SUM(t.line_revenue) FROM fact_transactions t JOIN dim_customer c USING (customer_id) GROUP BY c.country;
EXPLAIN ANALYZE SELECT * FROM fact_transactions WHERE order_date BETWEEN '2025-01-01' AND '2025-01-31';
-- Read: type (ALL=full scan < index < range < ref < eq_ref < const), key, rows, Extra (Using filesort / temporary / index = good)
-- Bad:  WHERE YEAR(order_date)=2025 (no index)  | LIKE '%abc' | implicit type cast | SELECT * | OFFSET 100000
-- Good: WHERE order_date >= '2025-01-01' AND order_date < '2026-01-01' | keyset pagination: WHERE line_id > :last ORDER BY line_id LIMIT 50
ANALYZE TABLE fact_transactions;  OPTIMIZE TABLE etl_audit;  -- refresh statistics / defragment

-- ================= 7. STORED PROCEDURES =================
DROP PROCEDURE IF EXISTS sp_top_customers;
DELIMITER //
CREATE PROCEDURE sp_top_customers(IN p_country VARCHAR(40), IN p_limit INT, OUT p_total DECIMAL(14,2))
BEGIN
    SELECT SUM(line_revenue) INTO p_total FROM fact_transactions t JOIN dim_customer c USING (customer_id)
     WHERE p_country IS NULL OR c.country = p_country;
    SELECT t.customer_id, ROUND(SUM(t.line_revenue),2) spend FROM fact_transactions t JOIN dim_customer c USING (customer_id)
     WHERE p_country IS NULL OR c.country = p_country GROUP BY t.customer_id ORDER BY spend DESC LIMIT p_limit;
END //
DELIMITER ;
CALL sp_top_customers('India', 5, @tot);  SELECT @tot;

-- control flow, variables, loops, error handling, SIGNAL, transaction inside a proc
DROP PROCEDURE IF EXISTS sp_refresh_monthly_revenue;
DELIMITER //
CREATE PROCEDURE sp_refresh_monthly_revenue(IN p_from DATE)
BEGIN
    DECLARE v_rows INT DEFAULT 0;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        INSERT INTO etl_audit(step, rows_in, rows_out, status) VALUES ('refresh_monthly_revenue', 0, 0, 'FAILED');
        RESIGNAL;
    END;
    IF p_from IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'p_from is required'; END IF;
    START TRANSACTION;
        DELETE FROM mv_monthly_revenue WHERE ym >= DATE_FORMAT(p_from,'%Y-%m');
        INSERT INTO mv_monthly_revenue (ym, revenue, orders)
        SELECT DATE_FORMAT(order_date,'%Y-%m'), SUM(line_revenue), COUNT(DISTINCT order_id)
        FROM fact_transactions WHERE order_date >= p_from GROUP BY 1;
        SET v_rows = ROW_COUNT();
    COMMIT;
    INSERT INTO etl_audit(step, rows_in, rows_out, status) VALUES ('refresh_monthly_revenue', v_rows, v_rows, 'OK');
END //
DELIMITER ;
CALL sp_refresh_monthly_revenue('2024-01-01');

-- WHILE / LOOP / REPEAT and CASE in procedures
DROP PROCEDURE IF EXISTS sp_loop_demo;
DELIMITER //
CREATE PROCEDURE sp_loop_demo(IN n INT)
BEGIN
    DECLARE i INT DEFAULT 1; DECLARE s INT DEFAULT 0;
    WHILE i <= n DO SET s = s + i; SET i = i + 1; END WHILE;
    loop_lbl: LOOP SET s = s + 1; IF s > 100 THEN LEAVE loop_lbl; END IF; END LOOP;
    REPEAT SET s = s - 1; UNTIL s < 50 END REPEAT;
    SELECT s AS result, CASE WHEN s < 60 THEN 'small' ELSE 'big' END AS size_;
END //
DELIMITER ;
CALL sp_loop_demo(10);

-- CURSOR: row-by-row processing (use only when set-based SQL can't do it)
DROP PROCEDURE IF EXISTS sp_score_segments;
DELIMITER //
CREATE PROCEDURE sp_score_segments()
BEGIN
    DECLARE done INT DEFAULT 0; DECLARE v_id INT; DECLARE v_clv DECIMAL(12,2);
    DECLARE cur CURSOR FOR SELECT customer_id, predicted_clv_6m FROM clv_predictions;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;
    OPEN cur;
    read_loop: LOOP
        FETCH cur INTO v_id, v_clv;
        IF done THEN LEAVE read_loop; END IF;
        UPDATE clv_predictions SET clv_segment = CASE WHEN v_clv >= 800 THEN 'Platinum' WHEN v_clv >= 250 THEN 'Gold'
                                                      WHEN v_clv >= 50 THEN 'Silver' ELSE 'Bronze' END WHERE customer_id = v_id;
    END LOOP;
    CLOSE cur;
END //
DELIMITER ;

-- ================= 8. STORED FUNCTIONS =================
DROP FUNCTION IF EXISTS fn_tier;
DELIMITER //
CREATE FUNCTION fn_tier(p_spend DECIMAL(12,2)) RETURNS VARCHAR(10) DETERMINISTIC
BEGIN
    RETURN CASE WHEN p_spend >= 2000 THEN 'Platinum' WHEN p_spend >= 1000 THEN 'Gold' WHEN p_spend >= 300 THEN 'Silver' ELSE 'Bronze' END;
END //
DELIMITER ;
SELECT customer_id, fn_tier(SUM(line_revenue)) tier FROM fact_transactions GROUP BY customer_id LIMIT 5;

-- ================= 9. TRIGGERS =================
CREATE TABLE IF NOT EXISTS tx_change_log (log_id INT AUTO_INCREMENT PRIMARY KEY, line_id BIGINT, action VARCHAR(10), old_rev DECIMAL(12,2), new_rev DECIMAL(12,2), changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
DROP TRIGGER IF EXISTS trg_tx_bi;  DROP TRIGGER IF EXISTS trg_tx_au;  DROP TRIGGER IF EXISTS trg_tx_ad;
DELIMITER //
CREATE TRIGGER trg_tx_bi BEFORE INSERT ON fact_transactions FOR EACH ROW
BEGIN
    IF NEW.line_revenue IS NULL THEN SET NEW.line_revenue = ROUND(NEW.quantity * NEW.unit_price * (1 - IFNULL(NEW.discount,0)), 2); END IF;
END //
CREATE TRIGGER trg_tx_au AFTER UPDATE ON fact_transactions FOR EACH ROW
BEGIN
    IF OLD.line_revenue <> NEW.line_revenue THEN INSERT INTO tx_change_log(line_id, action, old_rev, new_rev) VALUES (NEW.line_id, 'UPDATE', OLD.line_revenue, NEW.line_revenue); END IF;
END //
CREATE TRIGGER trg_tx_ad AFTER DELETE ON fact_transactions FOR EACH ROW
BEGIN
    INSERT INTO tx_change_log(line_id, action, old_rev) VALUES (OLD.line_id, 'DELETE', OLD.line_revenue);
END //
DELIMITER ;
SHOW TRIGGERS;

-- ================= 10. EVENTS (scheduler) =================
-- SET GLOBAL event_scheduler = ON;
DROP EVENT IF EXISTS ev_nightly_refresh;
CREATE EVENT ev_nightly_refresh ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURRENT_DATE) + INTERVAL 1 DAY + INTERVAL 2 HOUR)
DO CALL sp_refresh_monthly_revenue(DATE_SUB(CURDATE(), INTERVAL 3 MONTH));
SHOW EVENTS;

-- ================= 11. TRANSACTIONS, ACID, ISOLATION, LOCKS =================
-- ACID: Atomicity, Consistency, Isolation, Durability (InnoDB). Autocommit is ON by default.
SET autocommit = 0;
START TRANSACTION;
    UPDATE dim_product SET unit_price = unit_price * 1.05 WHERE category = 'Books';
    SAVEPOINT after_books;
    UPDATE dim_product SET unit_price = unit_price * 1.05 WHERE category = 'Home';
    ROLLBACK TO SAVEPOINT after_books;       -- undo only the Home change
COMMIT;                                      -- or ROLLBACK
SET autocommit = 1;
-- Isolation levels: READ UNCOMMITTED (dirty reads) < READ COMMITTED < REPEATABLE READ (MySQL default, gap locks) < SERIALIZABLE
SELECT @@transaction_isolation;
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
-- Locking: shared / exclusive row locks
START TRANSACTION;
    SELECT * FROM clv_predictions WHERE customer_id = 1 FOR UPDATE;             -- exclusive lock until COMMIT
    SELECT * FROM clv_predictions WHERE customer_id = 2 FOR SHARE;              -- shared lock
    SELECT * FROM clv_predictions WHERE customer_id = 3 FOR UPDATE SKIP LOCKED; -- queue-style workers
COMMIT;
LOCK TABLES etl_audit WRITE; UNLOCK TABLES;                                    -- table-level lock (rare)
-- Deadlock: two sessions lock the same rows in opposite order -> InnoDB rolls one back (error 1213).
-- Fix: lock rows in a consistent order, keep transactions short, retry on 1213. Inspect: SHOW ENGINE INNODB STATUS;
-- MVCC: consistent non-locking reads use snapshots (undo log) so readers never block writers.

-- ================= 12. PREPARED STATEMENTS / DYNAMIC SQL =================
SET @sql = 'SELECT customer_id, SUM(line_revenue) s FROM fact_transactions WHERE country = ? GROUP BY customer_id ORDER BY s DESC LIMIT ?';
PREPARE stmt FROM @sql;  SET @c = 'India', @n = 5;  EXECUTE stmt USING @c, @n;  DEALLOCATE PREPARE stmt;
-- Dynamic pivot columns (build SQL text, then PREPARE)
SELECT GROUP_CONCAT(DISTINCT CONCAT('SUM(CASE WHEN order_channel=''', order_channel, ''' THEN line_revenue ELSE 0 END) AS `', order_channel, '`')) INTO @cols FROM fact_transactions;
SET @q = CONCAT('SELECT country, ', @cols, ' FROM fact_transactions GROUP BY country');  PREPARE p FROM @q; EXECUTE p; DEALLOCATE PREPARE p;

-- ================= 13. GENERATED COLUMNS =================
ALTER TABLE fact_transactions ADD COLUMN order_month DATE GENERATED ALWAYS AS (DATE_FORMAT(order_date,'%Y-%m-01')) STORED, ADD INDEX idx_tx_month (order_month);
ALTER TABLE fact_transactions ADD COLUMN gross_amount DECIMAL(12,2) GENERATED ALWAYS AS (quantity * unit_price) VIRTUAL;

-- ================= 14. PARTITIONING =================
-- Partitioned InnoDB tables can't have foreign keys, and the partition column must be in every unique key.
CREATE TABLE IF NOT EXISTS fact_tx_archive (
    line_id BIGINT NOT NULL, order_id INT, customer_id INT, order_date DATE NOT NULL, line_revenue DECIMAL(12,2),
    PRIMARY KEY (line_id, order_date))
PARTITION BY RANGE COLUMNS (order_date) (
    PARTITION p2024 VALUES LESS THAN ('2025-01-01'), PARTITION p2025 VALUES LESS THAN ('2026-01-01'), PARTITION pmax VALUES LESS THAN (MAXVALUE));
EXPLAIN SELECT * FROM fact_tx_archive WHERE order_date >= '2025-03-01' AND order_date < '2025-04-01';   -- partition pruning (see 'partitions')
ALTER TABLE fact_tx_archive DROP PARTITION p2024;      -- instant archival; also HASH / LIST / KEY partitioning exist

-- ================= 15. FULL-TEXT SEARCH =================
ALTER TABLE dim_product ADD FULLTEXT INDEX ft_name (product_name, category);
SELECT product_id, product_name, MATCH(product_name, category) AGAINST ('Product Electronics' IN NATURAL LANGUAGE MODE) score
FROM dim_product WHERE MATCH(product_name, category) AGAINST ('+Electronics -Books' IN BOOLEAN MODE);

-- ================= 16. USERS, ROLES, PRIVILEGES =================
CREATE ROLE IF NOT EXISTS 'analyst_ro', 'etl_rw';
GRANT SELECT ON clv_db.* TO 'analyst_ro';
GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE ON clv_db.* TO 'etl_rw';
CREATE USER IF NOT EXISTS 'bi_user'@'%' IDENTIFIED BY 'Change_Me_123!' PASSWORD EXPIRE INTERVAL 90 DAY;
GRANT 'analyst_ro' TO 'bi_user'@'%';  SET DEFAULT ROLE 'analyst_ro' TO 'bi_user'@'%';
SHOW GRANTS FOR 'bi_user'@'%';   -- REVOKE INSERT ON clv_db.* FROM ...;  DROP USER 'bi_user'@'%';
-- Column-level privilege: GRANT SELECT (customer_id, country) ON clv_db.dim_customer TO 'x'@'%';  Power BI user should be read-only (views only).

-- ================= 17. BACKUP / RESTORE / IMPORT / EXPORT (shell) =================
-- mysqldump -u root -p --single-transaction --routines --triggers --events clv_db > clv_db_backup.sql
-- mysql -u root -p clv_db < clv_db_backup.sql
-- mysqldump ... clv_db fact_transactions | gzip > fact.sql.gz        |  point-in-time recovery uses binary logs: mysqlbinlog
-- SELECT * INTO OUTFILE '/var/lib/mysql-files/clv.csv' FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n' FROM vw_clv_dashboard;

-- ================= 18. MONITORING & MAINTENANCE =================
SHOW PROCESSLIST;  SHOW STATUS LIKE 'Threads_connected';  SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
SELECT table_name, ROUND((data_length + index_length)/1024/1024,2) AS size_mb, table_rows FROM information_schema.tables WHERE table_schema='clv_db' ORDER BY size_mb DESC;
SELECT * FROM information_schema.statistics WHERE table_schema='clv_db' AND table_name='fact_transactions';
-- slow log: SET GLOBAL slow_query_log=1; SET GLOBAL long_query_time=1;   | performance_schema.events_statements_summary_by_digest
SELECT digest_text, count_star, ROUND(avg_timer_wait/1e9,2) AS avg_ms FROM performance_schema.events_statements_summary_by_digest ORDER BY sum_timer_wait DESC LIMIT 5;
-- sys schema: SELECT * FROM sys.statements_with_full_table_scans LIMIT 5;   SELECT * FROM sys.schema_unused_indexes;

-- ================= 19. SECURITY =================
-- * Parameterise queries in code (Python: cur.execute("... WHERE id=%s", (id,))) - never f-string user input (SQL injection).
-- * Least privilege; separate ETL and BI users; TLS (REQUIRE SSL); no root from apps; keep secrets in env vars / vault.
-- * Mask PII with views: CREATE VIEW v AS SELECT customer_id, country, CONCAT(LEFT(email,2),'***') FROM ...

-- ================= 20. REPLICATION / HA / SCALE (concepts) =================
-- Binary log -> replicas (async/semi-sync), read/write splitting, InnoDB Cluster / Group Replication, sharding by customer_id,
-- engines: InnoDB (ACID, row locks, FK) vs MyISAM (legacy); charset utf8mb4; sql_mode=STRICT_TRANS_TABLES,ONLY_FULL_GROUP_BY.

-- ================= 21. PIPELINE SQL USED BY THE PROJECT =================
-- Refresh predictions after file 12 loads them, then publish to BI:
INSERT INTO clv_predictions (customer_id, recency_days, frequency, monetary, predicted_clv_6m, clv_segment)
SELECT customer_id, recency_days, frequency, monetary, 0, NULL FROM vw_customer_rfm
ON DUPLICATE KEY UPDATE recency_days = VALUES(recency_days), frequency = VALUES(frequency), monetary = VALUES(monetary);
SELECT clv_segment, COUNT(*) customers, ROUND(SUM(predicted_clv_6m)) pred_clv FROM vw_clv_dashboard GROUP BY clv_segment;
