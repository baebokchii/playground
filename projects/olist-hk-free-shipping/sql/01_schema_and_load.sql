-- ============================================================
-- 01_schema_and_load.sql
-- Goal (Step A - Part 1):
--   1) Initialize database containers (raw / marts / analytics)
--   2) Create raw ingestion tables (1:1 with source CSV structure)
--   3) Provide practical LOAD DATA LOCAL INFILE templates
--   4) Provide data-quality sanity checks for demo reproducibility
--
-- Why this design?
--   - We keep raw tables as close to source as possible to preserve lineage.
--   - We avoid heavy transformations in raw so reruns/debugging stay simple.
--   - We make script idempotent (DROP + CREATE) so live demo failures are recoverable.
-- ============================================================

-- -----------------------------------------------------------------
-- Chunk 0. Platform bootstrap
-- -----------------------------------------------------------------
-- Why: Demo environments differ. We create required schemas up front to avoid
-- "object not found" issues later in marts/analytics steps.
CREATE DATABASE IF NOT EXISTS olist_portfolio
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

-- In MySQL, SCHEMA == DATABASE. We keep logical layer names as separate schemas.
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS marts;
CREATE SCHEMA IF NOT EXISTS analytics;

USE olist_portfolio;

-- -----------------------------------------------------------------
-- Chunk 1. Reset raw layer objects (idempotency)
-- -----------------------------------------------------------------
-- Why: During learning/demo, you will rerun this script many times.
-- Dropping in reverse dependency order reduces collision risk.
DROP TABLE IF EXISTS raw.product_category_name_translation;
DROP TABLE IF EXISTS raw.olist_geolocation;
DROP TABLE IF EXISTS raw.olist_products;
DROP TABLE IF EXISTS raw.olist_sellers;
DROP TABLE IF EXISTS raw.olist_customers;
DROP TABLE IF EXISTS raw.olist_order_reviews;
DROP TABLE IF EXISTS raw.olist_order_payments;
DROP TABLE IF EXISTS raw.olist_order_items;
DROP TABLE IF EXISTS raw.olist_orders;

-- -----------------------------------------------------------------
-- Chunk 2. Transactional core tables (orders/items/payments/reviews)
-- -----------------------------------------------------------------
-- Why: These tables represent the event backbone for conversion, shipping, and CX.

CREATE TABLE raw.olist_orders (
  order_id VARCHAR(64) NOT NULL,
  customer_id VARCHAR(64) NOT NULL,
  order_status VARCHAR(32) NOT NULL,
  order_purchase_timestamp DATETIME NULL,
  order_approved_at DATETIME NULL,
  order_delivered_carrier_date DATETIME NULL,
  order_delivered_customer_date DATETIME NULL,
  order_estimated_delivery_date DATETIME NULL,
  PRIMARY KEY (order_id),
  KEY idx_orders_customer_id (customer_id),
  KEY idx_orders_status (order_status),
  KEY idx_orders_purchase_ts (order_purchase_timestamp),
  KEY idx_orders_delivered_customer (order_delivered_customer_date),
  KEY idx_orders_estimated_delivery (order_estimated_delivery_date)
) ENGINE=InnoDB;

CREATE TABLE raw.olist_order_items (
  order_id VARCHAR(64) NOT NULL,
  order_item_id INT NOT NULL,
  product_id VARCHAR(64) NOT NULL,
  seller_id VARCHAR(64) NOT NULL,
  shipping_limit_date DATETIME NULL,
  price DECIMAL(12,2) NULL,
  freight_value DECIMAL(12,2) NULL,
  PRIMARY KEY (order_id, order_item_id),
  KEY idx_items_product_id (product_id),
  KEY idx_items_seller_id (seller_id)
) ENGINE=InnoDB;

CREATE TABLE raw.olist_order_payments (
  order_id VARCHAR(64) NOT NULL,
  payment_sequential INT NOT NULL,
  payment_type VARCHAR(32) NULL,
  payment_installments INT NULL,
  payment_value DECIMAL(12,2) NULL,
  PRIMARY KEY (order_id, payment_sequential),
  KEY idx_payments_type (payment_type)
) ENGINE=InnoDB;

CREATE TABLE raw.olist_order_reviews (
  review_id VARCHAR(64) NOT NULL,
  order_id VARCHAR(64) NOT NULL,
  review_score INT NULL,
  review_comment_title VARCHAR(255) NULL,
  review_comment_message TEXT NULL,
  review_creation_date DATETIME NULL,
  review_answer_timestamp DATETIME NULL,
  PRIMARY KEY (review_id),
  KEY idx_reviews_order_id (order_id),
  KEY idx_reviews_score (review_score)
) ENGINE=InnoDB;

-- -----------------------------------------------------------------
-- Chunk 3. Master dimension-like tables (customers/sellers/products/geo)
-- -----------------------------------------------------------------
-- Why: These provide context needed for shipping policy analysis:
-- customer region, seller region, product physical attributes, geolocation.

CREATE TABLE raw.olist_customers (
  customer_id VARCHAR(64) NOT NULL,
  customer_unique_id VARCHAR(64) NOT NULL,
  customer_zip_code_prefix INT NULL,
  customer_city VARCHAR(255) NULL,
  customer_state VARCHAR(8) NULL,
  PRIMARY KEY (customer_id),
  KEY idx_customers_unique (customer_unique_id),
  KEY idx_customers_state (customer_state)
) ENGINE=InnoDB;

CREATE TABLE raw.olist_sellers (
  seller_id VARCHAR(64) NOT NULL,
  seller_zip_code_prefix INT NULL,
  seller_city VARCHAR(255) NULL,
  seller_state VARCHAR(8) NULL,
  PRIMARY KEY (seller_id),
  KEY idx_sellers_state (seller_state)
) ENGINE=InnoDB;

CREATE TABLE raw.olist_products (
  product_id VARCHAR(64) NOT NULL,
  product_category_name VARCHAR(255) NULL,
  product_name_lenght INT NULL,
  product_description_lenght INT NULL,
  product_photos_qty INT NULL,
  product_weight_g INT NULL,
  product_length_cm INT NULL,
  product_height_cm INT NULL,
  product_width_cm INT NULL,
  PRIMARY KEY (product_id),
  KEY idx_products_category (product_category_name)
) ENGINE=InnoDB;

CREATE TABLE raw.olist_geolocation (
  geolocation_id BIGINT NOT NULL AUTO_INCREMENT,
  geolocation_zip_code_prefix INT NULL,
  geolocation_lat DECIMAL(10,7) NULL,
  geolocation_lng DECIMAL(10,7) NULL,
  geolocation_city VARCHAR(255) NULL,
  geolocation_state VARCHAR(8) NULL,
  PRIMARY KEY (geolocation_id),
  KEY idx_geo_zip (geolocation_zip_code_prefix),
  KEY idx_geo_state (geolocation_state)
) ENGINE=InnoDB;

CREATE TABLE raw.product_category_name_translation (
  product_category_name VARCHAR(255) NOT NULL,
  product_category_name_english VARCHAR(255) NULL,
  PRIMARY KEY (product_category_name)
) ENGINE=InnoDB;

-- -----------------------------------------------------------------
-- Chunk 4. Bulk load templates
-- -----------------------------------------------------------------
-- Why LOAD DATA LOCAL INFILE?
--   - Fastest practical way to load large CSV files into MySQL.
--   - Better for demos than row-by-row inserts.
--
-- Important:
--   - Uncomment and set real file paths.
--   - If secure_file_priv is enabled, place files in allowed directory.
--   - Keep IGNORE 1 LINES for CSV header.
--   - Convert empty strings in datetime fields to NULL via NULLIF.

-- SET GLOBAL local_infile = 1;

-- 4-1) orders
-- LOAD DATA LOCAL INFILE '/path/to/olist_orders_dataset.csv'
-- INTO TABLE raw.olist_orders
-- FIELDS TERMINATED BY ',' ENCLOSED BY '"'
-- LINES TERMINATED BY '\n'
-- IGNORE 1 LINES
-- (@order_id, @customer_id, @order_status, @purchase_ts, @approved_at, @carrier_dt, @customer_dt, @est_dt)
-- SET
--   order_id = @order_id,
--   customer_id = @customer_id,
--   order_status = @order_status,
--   order_purchase_timestamp = NULLIF(@purchase_ts, ''),
--   order_approved_at = NULLIF(@approved_at, ''),
--   order_delivered_carrier_date = NULLIF(@carrier_dt, ''),
--   order_delivered_customer_date = NULLIF(@customer_dt, ''),
--   order_estimated_delivery_date = NULLIF(@est_dt, '');

-- 4-2) order_items
-- LOAD DATA LOCAL INFILE '/path/to/olist_order_items_dataset.csv'
-- INTO TABLE raw.olist_order_items
-- FIELDS TERMINATED BY ',' ENCLOSED BY '"'
-- LINES TERMINATED BY '\n'
-- IGNORE 1 LINES;

-- 4-3) order_payments
-- LOAD DATA LOCAL INFILE '/path/to/olist_order_payments_dataset.csv'
-- INTO TABLE raw.olist_order_payments
-- FIELDS TERMINATED BY ',' ENCLOSED BY '"'
-- LINES TERMINATED BY '\n'
-- IGNORE 1 LINES;

-- 4-4) order_reviews
-- LOAD DATA LOCAL INFILE '/path/to/olist_order_reviews_dataset.csv'
-- INTO TABLE raw.olist_order_reviews
-- FIELDS TERMINATED BY ',' ENCLOSED BY '"'
-- LINES TERMINATED BY '\n'
-- IGNORE 1 LINES
-- (@review_id, @order_id, @review_score, @title, @message, @creation_dt, @answer_ts)
-- SET
--   review_id = @review_id,
--   order_id = @order_id,
--   review_score = NULLIF(@review_score, ''),
--   review_comment_title = NULLIF(@title, ''),
--   review_comment_message = NULLIF(@message, ''),
--   review_creation_date = NULLIF(@creation_dt, ''),
--   review_answer_timestamp = NULLIF(@answer_ts, '');

-- 4-5) customers
-- LOAD DATA LOCAL INFILE '/path/to/olist_customers_dataset.csv'
-- INTO TABLE raw.olist_customers
-- FIELDS TERMINATED BY ',' ENCLOSED BY '"'
-- LINES TERMINATED BY '\n'
-- IGNORE 1 LINES;

-- 4-6) sellers
-- LOAD DATA LOCAL INFILE '/path/to/olist_sellers_dataset.csv'
-- INTO TABLE raw.olist_sellers
-- FIELDS TERMINATED BY ',' ENCLOSED BY '"'
-- LINES TERMINATED BY '\n'
-- IGNORE 1 LINES;

-- 4-7) products
-- LOAD DATA LOCAL INFILE '/path/to/olist_products_dataset.csv'
-- INTO TABLE raw.olist_products
-- FIELDS TERMINATED BY ',' ENCLOSED BY '"'
-- LINES TERMINATED BY '\n'
-- IGNORE 1 LINES;

-- 4-8) geolocation
-- LOAD DATA LOCAL INFILE '/path/to/olist_geolocation_dataset.csv'
-- INTO TABLE raw.olist_geolocation
-- FIELDS TERMINATED BY ',' ENCLOSED BY '"'
-- LINES TERMINATED BY '\n'
-- IGNORE 1 LINES
-- (@zip, @lat, @lng, @city, @state)
-- SET
--   geolocation_zip_code_prefix = NULLIF(@zip, ''),
--   geolocation_lat = NULLIF(@lat, ''),
--   geolocation_lng = NULLIF(@lng, ''),
--   geolocation_city = NULLIF(@city, ''),
--   geolocation_state = NULLIF(@state, '');

-- 4-9) category translation
-- LOAD DATA LOCAL INFILE '/path/to/product_category_name_translation.csv'
-- INTO TABLE raw.product_category_name_translation
-- FIELDS TERMINATED BY ',' ENCLOSED BY '"'
-- LINES TERMINATED BY '\n'
-- IGNORE 1 LINES;

-- -----------------------------------------------------------------
-- Chunk 5. Quick health checks after load
-- -----------------------------------------------------------------
-- Why: Before building marts, we verify row presence and critical-key duplicates.

-- 5-1) Row count overview
SELECT 'raw.olist_orders' AS table_name, COUNT(*) AS row_count FROM raw.olist_orders
UNION ALL SELECT 'raw.olist_order_items', COUNT(*) FROM raw.olist_order_items
UNION ALL SELECT 'raw.olist_order_payments', COUNT(*) FROM raw.olist_order_payments
UNION ALL SELECT 'raw.olist_order_reviews', COUNT(*) FROM raw.olist_order_reviews
UNION ALL SELECT 'raw.olist_customers', COUNT(*) FROM raw.olist_customers
UNION ALL SELECT 'raw.olist_sellers', COUNT(*) FROM raw.olist_sellers
UNION ALL SELECT 'raw.olist_products', COUNT(*) FROM raw.olist_products
UNION ALL SELECT 'raw.olist_geolocation', COUNT(*) FROM raw.olist_geolocation
UNION ALL SELECT 'raw.product_category_name_translation', COUNT(*) FROM raw.product_category_name_translation;

-- 5-2) Duplicate key checks (should be zero rows)
SELECT order_id, COUNT(*) AS dup_cnt
FROM raw.olist_orders
GROUP BY order_id
HAVING COUNT(*) > 1;

SELECT customer_id, COUNT(*) AS dup_cnt
FROM raw.olist_customers
GROUP BY customer_id
HAVING COUNT(*) > 1;

SELECT seller_id, COUNT(*) AS dup_cnt
FROM raw.olist_sellers
GROUP BY seller_id
HAVING COUNT(*) > 1;
