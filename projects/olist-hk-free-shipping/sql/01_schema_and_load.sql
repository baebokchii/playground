-- ==================================================================================================
-- 01_schema_and_load.sql
-- Project : Olist HK Free Shipping Strategy (Portfolio)
-- Goal    : Create an idempotent 3-layer warehouse structure and load raw CSV files safely.
-- DB      : MySQL 8+
-- --------------------------------------------------------------------------------------------------
-- Why this script is intentionally verbose:
-- 1) Portfolio/demo scripts are often re-run many times; idempotency avoids "it works only once" issues.
-- 2) Separating RAW / MARTS / ANALYTICS keeps data lineage clear for interviews and maintenance.
-- 3) Loading CSV explicitly with column variables helps avoid silent type-casting mistakes.
-- ==================================================================================================

/*
[Chunk A] Environment pre-checks
- We verify/enable LOCAL INFILE because many local MySQL clients disable it by default.
- If your org policy disallows GLOBAL change, set local_infile on client connection instead.
*/
SET @old_local_infile := @@GLOBAL.local_infile;
SET GLOBAL local_infile = 1;

/*
[Chunk B] Create database and schemas
- Keep the same database name you already used: olist_portfolio.
- raw      : exact imported records (minimal transformation).
- marts    : reusable business-ready tables.
- analytics: ad-hoc experiment tables/views.
*/
CREATE DATABASE IF NOT EXISTS olist_portfolio
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS marts;
CREATE SCHEMA IF NOT EXISTS analytics;

USE olist_portfolio;

/*
[Chunk C] Raw table lifecycle strategy
- For education and reproducibility we explicitly DROP+CREATE raw tables.
- In production, you may prefer TRUNCATE + metadata-driven ingestion.
*/
DROP TABLE IF EXISTS raw.product_category_name_translation;
DROP TABLE IF EXISTS raw.olist_geolocation;
DROP TABLE IF EXISTS raw.olist_products;
DROP TABLE IF EXISTS raw.olist_sellers;
DROP TABLE IF EXISTS raw.olist_customers;
DROP TABLE IF EXISTS raw.olist_order_reviews;
DROP TABLE IF EXISTS raw.olist_order_payments;
DROP TABLE IF EXISTS raw.olist_order_items;
DROP TABLE IF EXISTS raw.olist_orders;

/*
[Chunk D] Create RAW tables (1:1 with source CSV structure)
- Keep data types permissive enough for ingestion stability.
- Add practical indexes used by downstream joins and filters.
*/
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

/*
[Chunk E] CSV loading templates
- Replace /absolute/path/... with your machine path.
- NULLIF(@col,'') converts blank strings into SQL NULL (important for date arithmetic later).
- STR_TO_DATE can be used if your CSV date format differs from MySQL DATETIME default.
*/
LOAD DATA LOCAL INFILE '/absolute/path/olist_orders_dataset.csv'
INTO TABLE raw.olist_orders
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(@order_id, @customer_id, @order_status, @purchase_ts, @approved_at, @carrier_dt, @customer_dt, @estimated_dt)
SET
  order_id = @order_id,
  customer_id = @customer_id,
  order_status = @order_status,
  order_purchase_timestamp = NULLIF(@purchase_ts, ''),
  order_approved_at = NULLIF(@approved_at, ''),
  order_delivered_carrier_date = NULLIF(@carrier_dt, ''),
  order_delivered_customer_date = NULLIF(@customer_dt, ''),
  order_estimated_delivery_date = NULLIF(@estimated_dt, '');

LOAD DATA LOCAL INFILE '/absolute/path/olist_order_items_dataset.csv'
INTO TABLE raw.olist_order_items
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(@order_id, @order_item_id, @product_id, @seller_id, @shipping_limit_date, @price, @freight_value)
SET
  order_id = @order_id,
  order_item_id = NULLIF(@order_item_id, ''),
  product_id = @product_id,
  seller_id = @seller_id,
  shipping_limit_date = NULLIF(@shipping_limit_date, ''),
  price = NULLIF(@price, ''),
  freight_value = NULLIF(@freight_value, '');

LOAD DATA LOCAL INFILE '/absolute/path/olist_order_payments_dataset.csv'
INTO TABLE raw.olist_order_payments
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

LOAD DATA LOCAL INFILE '/absolute/path/olist_order_reviews_dataset.csv'
INTO TABLE raw.olist_order_reviews
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(@review_id, @order_id, @review_score, @review_comment_title, @review_comment_message, @review_creation_date, @review_answer_timestamp)
SET
  review_id = @review_id,
  order_id = @order_id,
  review_score = NULLIF(@review_score, ''),
  review_comment_title = NULLIF(@review_comment_title, ''),
  review_comment_message = NULLIF(@review_comment_message, ''),
  review_creation_date = NULLIF(@review_creation_date, ''),
  review_answer_timestamp = NULLIF(@review_answer_timestamp, '');

LOAD DATA LOCAL INFILE '/absolute/path/olist_customers_dataset.csv'
INTO TABLE raw.olist_customers
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

LOAD DATA LOCAL INFILE '/absolute/path/olist_sellers_dataset.csv'
INTO TABLE raw.olist_sellers
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

LOAD DATA LOCAL INFILE '/absolute/path/olist_products_dataset.csv'
INTO TABLE raw.olist_products
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

LOAD DATA LOCAL INFILE '/absolute/path/olist_geolocation_dataset.csv'
INTO TABLE raw.olist_geolocation
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(@zip,@lat,@lng,@city,@state)
SET
  geolocation_zip_code_prefix = NULLIF(@zip, ''),
  geolocation_lat = NULLIF(@lat, ''),
  geolocation_lng = NULLIF(@lng, ''),
  geolocation_city = NULLIF(@city, ''),
  geolocation_state = NULLIF(@state, '');

LOAD DATA LOCAL INFILE '/absolute/path/product_category_name_translation.csv'
INTO TABLE raw.product_category_name_translation
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

/*
[Chunk F] Post-load integrity checks
- Row counts ensure all files loaded.
- Distinct key checks quickly catch accidental duplicate IDs.
*/
SELECT 'raw.olist_orders' AS table_name, COUNT(*) AS row_count FROM raw.olist_orders
UNION ALL SELECT 'raw.olist_order_items', COUNT(*) FROM raw.olist_order_items
UNION ALL SELECT 'raw.olist_order_payments', COUNT(*) FROM raw.olist_order_payments
UNION ALL SELECT 'raw.olist_order_reviews', COUNT(*) FROM raw.olist_order_reviews
UNION ALL SELECT 'raw.olist_customers', COUNT(*) FROM raw.olist_customers
UNION ALL SELECT 'raw.olist_sellers', COUNT(*) FROM raw.olist_sellers
UNION ALL SELECT 'raw.olist_products', COUNT(*) FROM raw.olist_products
UNION ALL SELECT 'raw.olist_geolocation', COUNT(*) FROM raw.olist_geolocation
UNION ALL SELECT 'raw.product_category_name_translation', COUNT(*) FROM raw.product_category_name_translation;

SELECT
  COUNT(*) AS orders_total,
  COUNT(DISTINCT order_id) AS orders_distinct,
  COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_order_ids
FROM raw.olist_orders;

-- Optional: restore prior GLOBAL setting (comment out if you prefer to keep enabled).
-- SET GLOBAL local_infile = @old_local_infile;
