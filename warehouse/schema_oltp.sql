-- ============================================================
--  retail-etl-pipeline · OLTP Source Schema
--  Simulates the transactional MySQL database (UCI data)
-- ============================================================

CREATE DATABASE IF NOT EXISTS retail_oltp
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE retail_oltp;

CREATE TABLE IF NOT EXISTS transactions (
    id              BIGINT          NOT NULL AUTO_INCREMENT,
    invoice_no      VARCHAR(20)     NOT NULL,
    stock_code      VARCHAR(20)     NOT NULL,
    description     VARCHAR(255)    DEFAULT NULL,
    quantity        INT             NOT NULL,
    invoice_date    DATETIME        NOT NULL,
    unit_price      DECIMAL(10,2)   NOT NULL,
    customer_id     VARCHAR(20)     DEFAULT NULL,
    country         VARCHAR(100)    DEFAULT NULL,
    ingested_at     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    INDEX idx_invoice_no    (invoice_no),
    INDEX idx_stock_code    (stock_code),
    INDEX idx_invoice_date  (invoice_date),
    INDEX idx_customer_id   (customer_id)
) ENGINE=InnoDB COMMENT='Raw UCI Online Retail transactions';
