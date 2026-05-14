-- ============================================================
-- SUPERSTORE DATABASE - SQL CLEANING + RFM ANALYSIS
-- Day 13 | 30-Day Data Analytics Coding Challenge
-- Dataset: Sample Superstore | 9,994 rows | 2014-2017
-- Author: Upendrachary | Date: 2026-05-07
-- ============================================================

-- ============================================================
-- STEP 1: CREATE TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS superstore (
    row_id       INT PRIMARY KEY,
    order_id     VARCHAR(20),
    order_date   DATE,
    ship_date    DATE,
    ship_mode    VARCHAR(30),
    customer_id  VARCHAR(15),
    customer_name VARCHAR(100),
    segment      VARCHAR(30),
    country      VARCHAR(50),
    city         VARCHAR(50),
    state        VARCHAR(50),
    postal_code  VARCHAR(10),
    region       VARCHAR(20),
    product_id   VARCHAR(20),
    category     VARCHAR(30),
    sub_category VARCHAR(30),
    product_name VARCHAR(255),
    sales        DECIMAL(12,4),
    quantity     INT,
    discount     DECIMAL(5,4),
    profit       DECIMAL(12,4)
);

-- ============================================================
-- STEP 2: NULL VALUE CHECK (Data Quality Audit)
-- ============================================================
SELECT
    'row_id'        AS column_name, COUNT(*) - COUNT(row_id)       AS null_count FROM superstore UNION ALL
SELECT 'order_id',        COUNT(*) - COUNT(order_id)       FROM superstore UNION ALL
SELECT 'order_date',      COUNT(*) - COUNT(order_date)     FROM superstore UNION ALL
SELECT 'ship_date',       COUNT(*) - COUNT(ship_date)      FROM superstore UNION ALL
SELECT 'customer_id',     COUNT(*) - COUNT(customer_id)    FROM superstore UNION ALL
SELECT 'customer_name',   COUNT(*) - COUNT(customer_name)  FROM superstore UNION ALL
SELECT 'segment',         COUNT(*) - COUNT(segment)        FROM superstore UNION ALL
SELECT 'sales',           COUNT(*) - COUNT(sales)          FROM superstore UNION ALL
SELECT 'quantity',        COUNT(*) - COUNT(quantity)        FROM superstore UNION ALL
SELECT 'discount',        COUNT(*) - COUNT(discount)        FROM superstore UNION ALL
SELECT 'profit',          COUNT(*) - COUNT(profit)          FROM superstore;

-- ============================================================
-- STEP 3: DUPLICATE CHECK
-- ============================================================
-- Check duplicate Order IDs per product
SELECT order_id, product_id, COUNT(*) AS occurrences
FROM superstore
GROUP BY order_id, product_id
HAVING COUNT(*) > 1;

-- Total unique customers
SELECT COUNT(DISTINCT customer_id) AS unique_customers FROM superstore;

-- Total unique orders
SELECT COUNT(DISTINCT order_id) AS unique_orders FROM superstore;

-- ============================================================
-- STEP 4: DATA CLEANING
-- ============================================================

-- 4a: Remove rows where Sales or Quantity is NULL or zero
DELETE FROM superstore
WHERE sales IS NULL OR sales <= 0
   OR quantity IS NULL OR quantity <= 0;

-- 4b: Fill NULL discount with 0
UPDATE superstore SET discount = 0 WHERE discount IS NULL;

-- 4c: Standardize segment values (trim whitespace)
UPDATE superstore SET segment = TRIM(segment);
UPDATE superstore SET category = TRIM(category);
UPDATE superstore SET region = TRIM(region);

-- 4d: Fix negative sales (should not exist)
UPDATE superstore SET sales = ABS(sales) WHERE sales < 0;

-- 4e: Validate ship_date >= order_date
SELECT COUNT(*) AS invalid_shipping_dates
FROM superstore
WHERE ship_date < order_date;

-- ============================================================
-- STEP 5: EXPLORATORY SQL ANALYSIS
-- ============================================================

-- 5a: Sales & Profit by Category
SELECT
    category,
    ROUND(SUM(sales), 2)          AS total_sales,
    ROUND(SUM(profit), 2)         AS total_profit,
    ROUND(SUM(profit)/SUM(sales)*100, 2) AS profit_margin_pct,
    COUNT(DISTINCT order_id)      AS order_count
FROM superstore
GROUP BY category
ORDER BY total_sales DESC;

-- 5b: Sales by Region
SELECT
    region,
    ROUND(SUM(sales), 2)    AS total_sales,
    ROUND(SUM(profit), 2)   AS total_profit,
    ROUND(AVG(discount), 4) AS avg_discount,
    COUNT(DISTINCT customer_id) AS unique_customers
FROM superstore
GROUP BY region
ORDER BY total_sales DESC;

-- 5c: Top 10 Sub-Categories by Profit
SELECT
    sub_category,
    category,
    ROUND(SUM(sales), 2)   AS total_sales,
    ROUND(SUM(profit), 2)  AS total_profit,
    ROUND(AVG(discount)*100, 1) AS avg_discount_pct
FROM superstore
GROUP BY sub_category, category
ORDER BY total_profit DESC
LIMIT 10;

-- 5d: Monthly Sales Trend
SELECT
    DATE_FORMAT(order_date, '%Y-%m') AS month,
    ROUND(SUM(sales), 2)   AS monthly_sales,
    ROUND(SUM(profit), 2)  AS monthly_profit,
    COUNT(DISTINCT order_id) AS orders
FROM superstore
GROUP BY DATE_FORMAT(order_date, '%Y-%m')
ORDER BY month;

-- ============================================================
-- STEP 6: RFM ANALYSIS - CALCULATE R, F, M
-- ============================================================

-- Reference date (day after last order)
-- snapshot_date = '2017-12-31'

-- 6a: Base RFM Table
CREATE OR REPLACE VIEW rfm_base AS
SELECT
    customer_id,
    customer_name,
    segment                                           AS business_segment,
    region,
    DATEDIFF('2017-12-31', MAX(order_date))           AS recency_days,
    COUNT(DISTINCT order_id)                          AS frequency,
    ROUND(SUM(sales), 2)                              AS monetary
FROM superstore
GROUP BY customer_id, customer_name, segment, region;

-- ============================================================
-- STEP 7: RFM SCORING (1-5 Scale using NTILE)
-- ============================================================
CREATE OR REPLACE VIEW rfm_scores AS
SELECT
    customer_id,
    customer_name,
    business_segment,
    region,
    recency_days,
    frequency,
    monetary,
    -- Recency: Lower days = Higher score (NTILE reversed)
    NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
    -- Frequency: Higher = Better
    NTILE(5) OVER (ORDER BY frequency ASC)    AS f_score,
    -- Monetary: Higher = Better
    NTILE(5) OVER (ORDER BY monetary ASC)     AS m_score
FROM rfm_base;

-- ============================================================
-- STEP 8: RFM SEGMENTATION LABELS
-- ============================================================
CREATE OR REPLACE VIEW rfm_segments AS
SELECT
    customer_id,
    customer_name,
    business_segment,
    region,
    recency_days,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    CONCAT(r_score, f_score, m_score) AS rfm_code,
    (r_score + f_score + m_score)     AS rfm_total,
    CASE
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
        WHEN r_score >= 3 AND f_score >= 3                  THEN 'Loyal Customers'
        WHEN r_score >= 4 AND f_score <= 2                  THEN 'New Customers'
        WHEN r_score >= 3 AND m_score >= 3                  THEN 'Potential Loyalists'
        WHEN r_score <= 2 AND f_score >= 3 AND m_score >= 3 THEN 'At Risk'
        WHEN r_score <= 2 AND f_score >= 4                  THEN 'Cant Lose Them'
        WHEN r_score <= 2 AND f_score <= 2                  THEN 'Lost'
        ELSE 'Need Attention'
    END AS customer_segment
FROM rfm_scores;

-- ============================================================
-- STEP 9: RFM SUMMARY INSIGHTS
-- ============================================================

-- 9a: Customer count per segment
SELECT
    customer_segment,
    COUNT(customer_id)       AS customer_count,
    ROUND(AVG(recency_days)) AS avg_recency,
    ROUND(AVG(frequency), 1) AS avg_frequency,
    ROUND(AVG(monetary), 2)  AS avg_monetary,
    ROUND(SUM(monetary), 2)  AS total_revenue
FROM rfm_segments
GROUP BY customer_segment
ORDER BY total_revenue DESC;

-- 9b: Segment cross with Business Segment
SELECT
    business_segment,
    customer_segment,
    COUNT(customer_id) AS count,
    ROUND(SUM(monetary), 2) AS revenue
FROM rfm_segments
GROUP BY business_segment, customer_segment
ORDER BY business_segment, revenue DESC;

-- 9c: Top 10 Champions by Revenue
SELECT
    customer_name,
    customer_segment,
    region,
    recency_days,
    frequency,
    monetary,
    rfm_code
FROM rfm_segments
WHERE customer_segment = 'Champions'
ORDER BY monetary DESC
LIMIT 10;

-- 9d: At-Risk customers who need attention
SELECT
    customer_name,
    business_segment,
    region,
    recency_days AS days_since_last_purchase,
    frequency,
    monetary
FROM rfm_segments
WHERE customer_segment IN ('At Risk', 'Cant Lose Them')
ORDER BY monetary DESC
LIMIT 20;

-- ============================================================
-- STEP 10: DISCOUNT vs PROFIT IMPACT
-- ============================================================
SELECT
    CASE
        WHEN discount = 0           THEN '0% (No Discount)'
        WHEN discount <= 0.10       THEN '1-10%'
        WHEN discount <= 0.20       THEN '11-20%'
        WHEN discount <= 0.30       THEN '21-30%'
        WHEN discount <= 0.50       THEN '31-50%'
        ELSE '51%+'
    END AS discount_band,
    COUNT(*)                        AS order_lines,
    ROUND(SUM(sales), 2)           AS total_sales,
    ROUND(SUM(profit), 2)          AS total_profit,
    ROUND(AVG(profit), 2)          AS avg_profit_per_line
FROM superstore
GROUP BY discount_band
ORDER BY
    CASE discount_band
        WHEN '0% (No Discount)' THEN 1
        WHEN '1-10%' THEN 2
        WHEN '11-20%' THEN 3
        WHEN '21-30%' THEN 4
        WHEN '31-50%' THEN 5
        ELSE 6
    END;

-- ============================================================
-- END OF SCRIPT
-- ============================================================
