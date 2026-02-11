-- ============================================================
-- 01_schema_and_load.sql
-- Purpose: Create schema + raw tables + CSV load commands
-- DB: MySQL 8+
-- ============================================================

DROP DATABASE IF EXISTS olist_hk;
CREATE DATABASE olist_hk CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE olist_hk;

-- -----------------------------
-- Raw Tables
-- -----------------------------
CREATE TABLE customers (
    customer_id VARCHAR(64) PRIMARY KEY,
    customer_unique_id VARCHAR(64),
    customer_zip_code_prefix VARCHAR(16),
    customer_city VARCHAR(100),
    customer_state VARCHAR(8)
);

CREATE TABLE geolocation (
    geolocation_zip_code_prefix VARCHAR(16),
    geolocation_lat DECIMAL(10,7),
    geolocation_lng DECIMAL(10,7),
    geolocation_city VARCHAR(100),
    geolocation_state VARCHAR(8)
);

CREATE TABLE orders (
    order_id VARCHAR(64) PRIMARY KEY,
    customer_id VARCHAR(64),
    order_status VARCHAR(32),
    order_purchase_timestamp DATETIME,
    order_approved_at DATETIME,
    order_delivered_carrier_date DATETIME,
    order_delivered_customer_date DATETIME,
    order_estimated_delivery_date DATETIME,
    INDEX idx_orders_customer_id (customer_id),
    INDEX idx_orders_purchase_ts (order_purchase_timestamp)
);

CREATE TABLE order_items (
    order_id VARCHAR(64),
    order_item_id INT,
    product_id VARCHAR(64),
    seller_id VARCHAR(64),
    shipping_limit_date DATETIME,
    price DECIMAL(12,2),
    freight_value DECIMAL(12,2),
    PRIMARY KEY (order_id, order_item_id),
    INDEX idx_items_product_id (product_id),
    INDEX idx_items_seller_id (seller_id)
);

CREATE TABLE order_payments (
    order_id VARCHAR(64),
    payment_sequential INT,
    payment_type VARCHAR(32),
    payment_installments INT,
    payment_value DECIMAL(12,2),
    PRIMARY KEY (order_id, payment_sequential),
    INDEX idx_pay_order_id (order_id)
);

CREATE TABLE products (
    product_id VARCHAR(64) PRIMARY KEY,
    product_category_name VARCHAR(100),
    product_name_lenght INT,
    product_description_lenght INT,
    product_photos_qty INT,
    product_weight_g DECIMAL(12,2),
    product_length_cm DECIMAL(12,2),
    product_height_cm DECIMAL(12,2),
    product_width_cm DECIMAL(12,2)
);

CREATE TABLE sellers (
    seller_id VARCHAR(64) PRIMARY KEY,
    seller_zip_code_prefix VARCHAR(16),
    seller_city VARCHAR(100),
    seller_state VARCHAR(8)
);

CREATE TABLE product_category_translation (
    product_category_name VARCHAR(100) PRIMARY KEY,
    product_category_name_english VARCHAR(100)
);

CREATE TABLE order_reviews (
    review_id VARCHAR(64),
    order_id VARCHAR(64),
    review_score INT,
    review_comment_title TEXT,
    review_comment_message TEXT,
    review_creation_date DATETIME,
    review_answer_timestamp DATETIME,
    INDEX idx_review_order_id (order_id)
);

-- -----------------------------
-- Optional CSV Load Section
-- Replace /path/to/ with your local paths
-- If secure_file_priv is enabled, use allowed directory.
-- -----------------------------

-- SET GLOBAL local_infile = 1;

-- LOAD DATA LOCAL INFILE '/path/to/olist_customers_dataset.csv'
-- INTO TABLE customers
-- FIELDS TERMINATED BY ',' ENCLOSED BY '"'
-- LINES TERMINATED BY '\n'
-- IGNORE 1 LINES;

-- LOAD DATA LOCAL INFILE '/path/to/olist_geolocation_dataset.csv'
-- INTO TABLE geolocation
-- FIELDS TERMINATED BY ',' ENCLOSED BY '"'
-- LINES TERMINATED BY '\n'
-- IGNORE 1 LINES;

-- LOAD DATA LOCAL INFILE '/path/to/olist_orders_dataset.csv'
-- INTO TABLE orders
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

-- Repeat similarly for remaining CSV files.

-- -----------------------------
-- Basic sanity checks
-- -----------------------------
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL
SELECT 'orders', COUNT(*) FROM orders
UNION ALL
SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL
SELECT 'products', COUNT(*) FROM products
UNION ALL
SELECT 'sellers', COUNT(*) FROM sellers
UNION ALL
SELECT 'order_reviews', COUNT(*) FROM order_reviews;
