-- ============================================================
-- 02_feature_mart.sql
-- Purpose: Build curated marts from raw layer tables
-- Compatible with initialization that creates raw/marts/analytics schemas
-- Idempotent: safe to re-run
-- ============================================================

CREATE DATABASE IF NOT EXISTS marts
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

-- Helper zip centroid table in marts layer
DROP TABLE IF EXISTS marts.zip_geo;
CREATE TABLE marts.zip_geo AS
SELECT
    geolocation_zip_code_prefix AS zip_code_prefix,
    AVG(geolocation_lat) AS lat,
    AVG(geolocation_lng) AS lng
FROM raw.olist_geolocation
GROUP BY geolocation_zip_code_prefix;

ALTER TABLE marts.zip_geo
ADD PRIMARY KEY (zip_code_prefix);

-- Main enriched item-level fact
DROP TABLE IF EXISTS marts.fact_order_item_enriched;
CREATE TABLE marts.fact_order_item_enriched AS
SELECT
    oi.order_id,
    oi.order_item_id,
    oi.product_id,
    oi.seller_id,
    o.customer_id,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,

    c.customer_state,
    c.customer_city,
    s.seller_state,
    s.seller_city,

    oi.price,
    oi.freight_value,
    CASE WHEN oi.freight_value = 0 THEN 1 ELSE 0 END AS is_free_shipping_item,

    p.product_category_name,
    pct.product_category_name_english,
    p.product_weight_g,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm,

    zg_c.lat AS customer_lat,
    zg_c.lng AS customer_lng,
    zg_s.lat AS seller_lat,
    zg_s.lng AS seller_lng,

    CASE
        WHEN zg_c.lat IS NULL OR zg_c.lng IS NULL OR zg_s.lat IS NULL OR zg_s.lng IS NULL THEN NULL
        ELSE 6371 * 2 * ASIN(
            SQRT(
                POWER(SIN(RADIANS((zg_c.lat - zg_s.lat) / 2)), 2)
                + COS(RADIANS(zg_s.lat)) * COS(RADIANS(zg_c.lat))
                * POWER(SIN(RADIANS((zg_c.lng - zg_s.lng) / 2)), 2)
            )
        )
    END AS distance_km,

    CASE
        WHEN o.order_delivered_customer_date IS NULL OR o.order_purchase_timestamp IS NULL THEN NULL
        ELSE DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp)
    END AS delivery_days,

    CASE
        WHEN o.order_estimated_delivery_date IS NULL OR o.order_delivered_customer_date IS NULL THEN NULL
        ELSE DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date)
    END AS delivery_delay_days,

    CASE
        WHEN oi.price > 0 THEN oi.freight_value / oi.price
        ELSE NULL
    END AS freight_price_ratio,

    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month
FROM raw.olist_order_items oi
JOIN raw.olist_orders o ON oi.order_id = o.order_id
LEFT JOIN raw.olist_customers c ON o.customer_id = c.customer_id
LEFT JOIN raw.olist_sellers s ON oi.seller_id = s.seller_id
LEFT JOIN raw.olist_products p ON oi.product_id = p.product_id
LEFT JOIN raw.product_category_name_translation pct
    ON p.product_category_name = pct.product_category_name
LEFT JOIN marts.zip_geo zg_c ON c.customer_zip_code_prefix = zg_c.zip_code_prefix
LEFT JOIN marts.zip_geo zg_s ON s.seller_zip_code_prefix = zg_s.zip_code_prefix
WHERE o.order_purchase_timestamp IS NOT NULL;

ALTER TABLE marts.fact_order_item_enriched
ADD INDEX idx_fact_month (order_month),
ADD INDEX idx_fact_order_id (order_id),
ADD INDEX idx_fact_seller_id (seller_id),
ADD INDEX idx_fact_free_ship (is_free_shipping_item),
ADD INDEX idx_fact_order_status (order_status);

-- Order-level marts
DROP TABLE IF EXISTS marts.order_level_metrics;
CREATE TABLE marts.order_level_metrics AS
SELECT
    f.order_id,
    MIN(f.order_month) AS order_month,
    MIN(f.order_purchase_timestamp) AS order_purchase_timestamp,
    MIN(f.order_status) AS order_status,
    MIN(f.customer_id) AS customer_id,

    SUM(f.price) AS order_gmv,
    SUM(f.freight_value) AS order_freight,
    AVG(f.delivery_days) AS avg_delivery_days,
    AVG(f.distance_km) AS avg_distance_km,
    AVG(f.freight_price_ratio) AS avg_freight_ratio,
    CASE WHEN SUM(f.freight_value) = 0 THEN 1 ELSE 0 END AS is_free_shipping_order
FROM marts.fact_order_item_enriched f
GROUP BY f.order_id;

ALTER TABLE marts.order_level_metrics
ADD PRIMARY KEY (order_id),
ADD INDEX idx_order_metrics_month (order_month),
ADD INDEX idx_order_metrics_freeship (is_free_shipping_order),
ADD INDEX idx_order_metrics_status (order_status);

DROP TABLE IF EXISTS marts.order_review_metrics;
CREATE TABLE marts.order_review_metrics AS
SELECT
    olm.*,
    rv.review_score
FROM marts.order_level_metrics olm
LEFT JOIN (
    SELECT order_id, AVG(review_score) AS review_score
    FROM raw.olist_order_reviews
    GROUP BY order_id
) rv ON olm.order_id = rv.order_id;

ALTER TABLE marts.order_review_metrics
ADD INDEX idx_order_review_month (order_month);

DROP TABLE IF EXISTS marts.agg_monthly_kpi;
CREATE TABLE marts.agg_monthly_kpi AS
SELECT
    order_month,
    COUNT(*) AS orders,
    SUM(order_gmv) AS gmv,
    SUM(order_freight) AS freight_total,
    AVG(order_freight) AS avg_freight_per_order,
    AVG(avg_delivery_days) AS avg_delivery_days,
    AVG(avg_distance_km) AS avg_distance_km,
    AVG(avg_freight_ratio) AS avg_freight_ratio,
    AVG(review_score) AS avg_review_score,
    AVG(is_free_shipping_order) AS free_shipping_order_rate
FROM marts.order_review_metrics
GROUP BY order_month;

DROP TABLE IF EXISTS marts.agg_seller_monthly_kpi;
CREATE TABLE marts.agg_seller_monthly_kpi AS
SELECT
    seller_id,
    order_month,
    COUNT(DISTINCT order_id) AS orders,
    SUM(price) AS gmv,
    SUM(freight_value) AS freight_total,
    AVG(freight_value) AS avg_freight_item,
    AVG(delivery_days) AS avg_delivery_days,
    AVG(distance_km) AS avg_distance_km,
    AVG(CASE WHEN freight_value = 0 THEN 1 ELSE 0 END) AS free_shipping_item_rate
FROM marts.fact_order_item_enriched
GROUP BY seller_id, order_month;
