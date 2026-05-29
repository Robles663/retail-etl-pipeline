
-- ============================================================
--  retail-etl-pipeline · Data Warehouse Schema
--  Engine: MySQL 8.0
--  Model:  Star Schema
-- ============================================================

CREATE DATABASE IF NOT EXISTS retail_dwh
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE retail_dwh;

-- ────────────────────────────────────────────────────────────
--  DIMENSION: dim_date
--  Pre-populated calendar table for time-intelligence queries
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS dim_date (
    date_key        INT             NOT NULL,   -- Format: YYYYMMDD
    full_date       DATE            NOT NULL,
    year            SMALLINT        NOT NULL,
    quarter         TINYINT         NOT NULL,   -- 1–4
    month           TINYINT         NOT NULL,   -- 1–12
    month_name      VARCHAR(10)     NOT NULL,
    week            TINYINT         NOT NULL,   -- ISO week 1–53
    day_of_month    TINYINT         NOT NULL,
    day_of_week     TINYINT         NOT NULL,   -- 1=Mon … 7=Sun
    day_name        VARCHAR(10)     NOT NULL,
    is_weekend      TINYINT(1)      NOT NULL DEFAULT 0,
    is_holiday      TINYINT(1)      NOT NULL DEFAULT 0,

    PRIMARY KEY (date_key),
    INDEX idx_full_date (full_date),
    INDEX idx_year_month (year, month)
) ENGINE=InnoDB COMMENT='Calendar dimension — one row per day';


-- ────────────────────────────────────────────────────────────
--  DIMENSION: dim_geography
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS dim_geography (
    geography_key   INT             NOT NULL AUTO_INCREMENT,
    country         VARCHAR(100)    NOT NULL,
    region          VARCHAR(100)    DEFAULT NULL,   -- from marketplace feed
    iso_code        CHAR(2)         DEFAULT NULL,

    PRIMARY KEY (geography_key),
    UNIQUE INDEX uix_country_region (country, region),
    INDEX idx_country (country)
) ENGINE=InnoDB COMMENT='Geographic dimension';


-- ────────────────────────────────────────────────────────────
--  DIMENSION: dim_product
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS dim_product (
    product_key     INT             NOT NULL AUTO_INCREMENT,
    stock_code      VARCHAR(20)     NOT NULL,
    description     VARCHAR(255)    DEFAULT NULL,
    category        VARCHAR(100)    DEFAULT NULL,   -- from marketplace feed
    unit_price_ref  DECIMAL(10,2)   DEFAULT NULL,   -- reference / list price
    source          VARCHAR(20)     NOT NULL,       -- 'uci' | 'marketplace'
	is_internal		TINYINT(1)		NOT NULL DEFAULT 0, 
    
    PRIMARY KEY (product_key),
    UNIQUE INDEX uix_stock_code_source (stock_code, source),
    INDEX idx_category (category)
) ENGINE=InnoDB COMMENT='Product dimension';


-- ────────────────────────────────────────────────────────────
--  DIMENSION: dim_customer
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS dim_customer (
    customer_key    INT             NOT NULL AUTO_INCREMENT,
    customer_id     VARCHAR(20)     NOT NULL,       -- original ID or 'UNKNOWN'
    segment         VARCHAR(20)     NOT NULL DEFAULT 'unknown',
                                                    -- 'B2B' | 'B2C' | 'unknown'
    country         VARCHAR(100)    DEFAULT NULL,
    first_order_date DATE            DEFAULT NULL,

    PRIMARY KEY (customer_key),
    UNIQUE INDEX uix_customer_id (customer_id),
    INDEX idx_segment (segment)
) ENGINE=InnoDB COMMENT='Customer dimension';


-- ────────────────────────────────────────────────────────────
--  FACT TABLE: fact_sales
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS fact_sales (
    sale_id         BIGINT          NOT NULL AUTO_INCREMENT,

    -- Surrogate FKs
    date_key        INT             NOT NULL,
    product_key     INT             NOT NULL,
    customer_key    INT             NOT NULL,
    geography_key   INT             NOT NULL,

    -- Degenerate dimension (no dedicated table needed)
    invoice_no      VARCHAR(20)     NOT NULL,

    -- Measures
    quantity        INT             NOT NULL,
    unit_price      DECIMAL(10,2)   NOT NULL,
    total_revenue   DECIMAL(12,2)   NOT NULL COMMENT 'quantity * unit_price',
    is_return       TINYINT(1)      NOT NULL DEFAULT 0,

    -- Lineage
    source          VARCHAR(20)     NOT NULL,       -- 'uci' | 'marketplace'
    loaded_at       TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (sale_id),

    -- FK constraints
    CONSTRAINT fk_fs_date       FOREIGN KEY (date_key)       REFERENCES dim_date(date_key),
    CONSTRAINT fk_fs_product    FOREIGN KEY (product_key)    REFERENCES dim_product(product_key),
    CONSTRAINT fk_fs_customer   FOREIGN KEY (customer_key)   REFERENCES dim_customer(customer_key),
    CONSTRAINT fk_fs_geography  FOREIGN KEY (geography_key)  REFERENCES dim_geography(geography_key),

    -- Query performance indexes
    INDEX idx_date_key      (date_key),
    INDEX idx_product_key   (product_key),
    INDEX idx_customer_key  (customer_key),
    INDEX idx_geography_key (geography_key),
    INDEX idx_source        (source),
    INDEX idx_is_return     (is_return),
    INDEX idx_loaded_at     (loaded_at)

) ENGINE=InnoDB COMMENT='Central fact table — one row per invoice line';


-- ────────────────────────────────────────────────────────────
--  VIEWS — KPI layer
-- ────────────────────────────────────────────────────────────

-- KPI 1: Daily revenue across both sources
CREATE OR REPLACE VIEW vw_daily_revenue AS
SELECT
    d.full_date,
    d.year,
    d.month,
    f.source,
    COUNT(DISTINCT f.invoice_no)        AS total_orders,
    SUM(f.quantity)                     AS total_units_sold,
    ROUND(SUM(f.total_revenue), 2)      AS total_revenue
FROM fact_sales f
JOIN dim_date d ON f.date_key = d.date_key
WHERE f.is_return = 0
GROUP BY d.full_date, d.year, d.month, f.source;


-- KPI 2: Top products by revenue
CREATE OR REPLACE VIEW vw_top_products AS
SELECT
    p.stock_code,
    p.description,
    p.category,
    SUM(f.quantity)                     AS total_units_sold,
    ROUND(SUM(f.total_revenue), 2)      AS total_revenue,
    COUNT(DISTINCT f.invoice_no)        AS total_orders
FROM fact_sales f
JOIN dim_product p ON f.product_key = p.product_key
WHERE f.is_return = 0
GROUP BY p.product_key, p.stock_code, p.description, p.category
ORDER BY total_revenue DESC;


-- KPI 3: Revenue by country
CREATE OR REPLACE VIEW vw_revenue_by_country AS
SELECT
    g.country,
    g.region,
    d.year,
    ROUND(SUM(f.total_revenue), 2)      AS total_revenue,
    COUNT(DISTINCT f.customer_key)      AS unique_customers,
    COUNT(DISTINCT f.invoice_no)        AS total_orders
FROM fact_sales f
JOIN dim_geography g ON f.geography_key = g.geography_key
JOIN dim_date d ON f.date_key = d.date_key
WHERE f.is_return = 0
GROUP BY g.country, g.region, d.year;


-- KPI 4: Return rate per product
CREATE OR REPLACE VIEW vw_return_rate AS
SELECT
    p.stock_code,
    p.description,
    COUNT(CASE WHEN f.is_return = 0 THEN 1 END)     AS sales_count,
    COUNT(CASE WHEN f.is_return = 1 THEN 1 END)     AS return_count,
    ROUND(
        COUNT(CASE WHEN f.is_return = 1 THEN 1 END) * 100.0
        / NULLIF(COUNT(*), 0), 2
    )                                                AS return_rate_pct
FROM fact_sales f
JOIN dim_product p ON f.product_key = p.product_key
GROUP BY p.product_key, p.stock_code, p.description;


-- KPI 5: Monthly revenue trend (YoY comparison)
CREATE OR REPLACE VIEW vw_monthly_trend AS
SELECT
    d.year,
    d.month,
    d.month_name,
    ROUND(SUM(f.total_revenue), 2)      AS total_revenue,
    SUM(f.quantity)                     AS total_units
FROM fact_sales f
JOIN dim_date d ON f.date_key = d.date_key
WHERE f.is_return = 0
GROUP BY d.year, d.month, d.month_name
ORDER BY d.year, d.month;
