-- ============================================================
-- 02_feature_mart.sql
-- Goal (Step A - Part 2):
--   Build analytical marts from raw tables in small, traceable chunks.
--
-- Learning-oriented design choices:
--   - Split transformations into multiple intermediate tables.
--   - Add comments for "why" each feature is created.
--   - Keep final marts compact and analysis-ready.
--
-- Output targets required by project:
--   - marts.fact_order_item_enriched
--   - marts.agg_monthly_kpi
--   - marts.agg_seller_monthly_kpi
-- ============================================================

-- -----------------------------------------------------------------
-- Chunk 0. Ensure target schema exists
-- -----------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS marts;

-- -----------------------------------------------------------------
-- Chunk 1. Geolocation normalization (zip -> centroid)
-- -----------------------------------------------------------------
-- Why this is needed:
--   - raw geolocation has many records per zip prefix.
--   - distance calculation needs one representative point per zip.
--   - centroid (AVG lat/lng) is a practical approximation for portfolio analysis.
DROP TABLE IF EXISTS marts.stg_zip_geo_centroid;
CREATE TABLE marts.stg_zip_geo_centroid AS
SELECT
    geolocation_zip_code_prefix AS zip_code_prefix,
    AVG(geolocation_lat) AS lat,
    AVG(geolocation_lng) AS lng
FROM raw.olist_geolocation
WHERE geolocation_zip_code_prefix IS NOT NULL
GROUP BY geolocation_zip_code_prefix;

ALTER TABLE marts.stg_zip_geo_centroid
ADD PRIMARY KEY (zip_code_prefix);

-- -----------------------------------------------------------------
-- Chunk 2. Base join (order item + order + customer/seller/product)
-- -----------------------------------------------------------------
-- Why this chunk exists:
--   - We first collect business entities in one table before feature math.
--   - This makes debugging easier (join quality can be checked separately).
DROP TABLE IF EXISTS marts.stg_order_item_base;
CREATE TABLE marts.stg_order_item_base AS
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

    c.customer_zip_code_prefix,
    c.customer_city,
    c.customer_state,

    s.seller_zip_code_prefix,
    s.seller_city,
    s.seller_state,

    oi.price,
    oi.freight_value,

    p.product_category_name,
    pct.product_category_name_english,
    p.product_weight_g,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm
FROM raw.olist_order_items oi
JOIN raw.olist_orders o
  ON oi.order_id = o.order_id
LEFT JOIN raw.olist_customers c
  ON o.customer_id = c.customer_id
LEFT JOIN raw.olist_sellers s
  ON oi.seller_id = s.seller_id
LEFT JOIN raw.olist_products p
  ON oi.product_id = p.product_id
LEFT JOIN raw.product_category_name_translation pct
  ON p.product_category_name = pct.product_category_name
WHERE o.order_purchase_timestamp IS NOT NULL;

ALTER TABLE marts.stg_order_item_base
ADD INDEX idx_stg_base_order_id (order_id),
ADD INDEX idx_stg_base_seller_id (seller_id),
ADD INDEX idx_stg_base_order_month (order_purchase_timestamp);

-- -----------------------------------------------------------------
-- Chunk 3. Attach geo coordinates (customer/seller)
-- -----------------------------------------------------------------
-- Why separated:
--   - Geo matching failure can be validated independently (NULL lat/lng rates).
--   - Useful for explaining real-world missing geo problems to interviewers.
DROP TABLE IF EXISTS marts.stg_order_item_geo;
CREATE TABLE marts.stg_order_item_geo AS
SELECT
    b.*,
    zg_c.lat AS customer_lat,
    zg_c.lng AS customer_lng,
    zg_s.lat AS seller_lat,
    zg_s.lng AS seller_lng
FROM marts.stg_order_item_base b
LEFT JOIN marts.stg_zip_geo_centroid zg_c
  ON b.customer_zip_code_prefix = zg_c.zip_code_prefix
LEFT JOIN marts.stg_zip_geo_centroid zg_s
  ON b.seller_zip_code_prefix = zg_s.zip_code_prefix;

ALTER TABLE marts.stg_order_item_geo
ADD INDEX idx_stg_geo_order_id (order_id);

-- -----------------------------------------------------------------
-- Chunk 4. Feature engineering at item granularity
-- -----------------------------------------------------------------
-- Why each feature matters for free-shipping policy:
--   - is_free_shipping_item: direct treatment flag (freight=0)
--   - distance_km: proxy for logistics burden
--   - delivery_days / delay_days: customer experience and SLA lens
--   - freight_price_ratio: normalized shipping burden vs item price
--   - order_month: monthly trend & campaign period analysis
DROP TABLE IF EXISTS marts.fact_order_item_enriched;
CREATE TABLE marts.fact_order_item_enriched AS
SELECT
    g.order_id,
    g.order_item_id,
    g.product_id,
    g.seller_id,
    g.customer_id,
    g.order_status,
    g.order_purchase_timestamp,
    g.order_delivered_customer_date,
    g.order_estimated_delivery_date,

    g.customer_state,
    g.customer_city,
    g.seller_state,
    g.seller_city,

    g.price,
    g.freight_value,
    CASE WHEN g.freight_value = 0 THEN 1 ELSE 0 END AS is_free_shipping_item,

    g.product_category_name,
    g.product_category_name_english,
    g.product_weight_g,
    g.product_length_cm,
    g.product_height_cm,
    g.product_width_cm,

    g.customer_lat,
    g.customer_lng,
    g.seller_lat,
    g.seller_lng,

    CASE
        WHEN g.customer_lat IS NULL OR g.customer_lng IS NULL OR g.seller_lat IS NULL OR g.seller_lng IS NULL
            THEN NULL
        ELSE 6371 * 2 * ASIN(
            SQRT(
                POWER(SIN(RADIANS((g.customer_lat - g.seller_lat) / 2)), 2)
                + COS(RADIANS(g.seller_lat)) * COS(RADIANS(g.customer_lat))
                * POWER(SIN(RADIANS((g.customer_lng - g.seller_lng) / 2)), 2)
            )
        )
    END AS distance_km,

    CASE
        WHEN g.order_delivered_customer_date IS NULL OR g.order_purchase_timestamp IS NULL
            THEN NULL
        ELSE DATEDIFF(g.order_delivered_customer_date, g.order_purchase_timestamp)
    END AS delivery_days,

    CASE
        WHEN g.order_estimated_delivery_date IS NULL OR g.order_delivered_customer_date IS NULL
            THEN NULL
        ELSE DATEDIFF(g.order_delivered_customer_date, g.order_estimated_delivery_date)
    END AS delivery_delay_days,

    CASE
        WHEN g.price > 0 THEN g.freight_value / g.price
        ELSE NULL
    END AS freight_price_ratio,

    DATE_FORMAT(g.order_purchase_timestamp, '%Y-%m') AS order_month
FROM marts.stg_order_item_geo g;

ALTER TABLE marts.fact_order_item_enriched
ADD INDEX idx_fact_month (order_month),
ADD INDEX idx_fact_order_id (order_id),
ADD INDEX idx_fact_seller_id (seller_id),
ADD INDEX idx_fact_free_ship (is_free_shipping_item),
ADD INDEX idx_fact_order_status (order_status);

-- -----------------------------------------------------------------
-- Chunk 5. Order-level rollup
-- -----------------------------------------------------------------
-- Why roll up to order level:
--   - Policy decisions are often order/basket based, not item based.
--   - Prevent double counting when comparing order count and review score.
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

-- -----------------------------------------------------------------
-- Chunk 6. Attach review score to order-level facts
-- -----------------------------------------------------------------
-- Why AVG(review_score):
--   - Some orders may have multiple review records.
--   - We need a single stable order-level score for segmentation comparison.
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
) rv
  ON olm.order_id = rv.order_id;

ALTER TABLE marts.order_review_metrics
ADD INDEX idx_order_review_month (order_month);

-- -----------------------------------------------------------------
-- Chunk 7. Monthly KPI mart (executive layer)
-- -----------------------------------------------------------------
-- Why monthly aggregation:
--   - Matches campaign windows and business reporting cadence.
--   - Enables trend plots (before/after free shipping policy periods).
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

-- -----------------------------------------------------------------
-- Chunk 8. Seller-month KPI mart (campaign diagnostics)
-- -----------------------------------------------------------------
-- Why seller-level view:
--   - Free-shipping behavior is often seller-driven (campaign by seller).
--   - Required for identifying "campaign-like" months and uplift checks.
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

-- -----------------------------------------------------------------
-- Chunk 9. Post-build validation checks
-- -----------------------------------------------------------------
-- Why: Fast confidence checks before moving to analysis SQL / Python notebook.
SELECT 'marts.fact_order_item_enriched' AS mart_name, COUNT(*) AS row_count
FROM marts.fact_order_item_enriched
UNION ALL
SELECT 'marts.order_level_metrics', COUNT(*) FROM marts.order_level_metrics
UNION ALL
SELECT 'marts.order_review_metrics', COUNT(*) FROM marts.order_review_metrics
UNION ALL
SELECT 'marts.agg_monthly_kpi', COUNT(*) FROM marts.agg_monthly_kpi
UNION ALL
SELECT 'marts.agg_seller_monthly_kpi', COUNT(*) FROM marts.agg_seller_monthly_kpi;
