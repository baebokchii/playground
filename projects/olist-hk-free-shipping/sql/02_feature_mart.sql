-- ==================================================================================================
-- 02_feature_mart.sql
-- Project : Olist HK Free Shipping Strategy (Portfolio)
-- Goal    : Build reusable feature marts for policy validation and business storytelling.
-- DB      : olist_portfolio (schemas: raw, marts, analytics)
-- --------------------------------------------------------------------------------------------------
-- Design notes:
-- - We calculate features at order-item grain first because shipping fees happen per item line.
-- - We then aggregate to order and month levels for KPI views and modeling inputs.
-- - Every step is broken into small chunks so learning/debugging is easier.
-- ==================================================================================================

USE olist_portfolio;

/*
[Chunk A] Prepare ZIP-level geolocation lookup
Why this exists:
- Customer/seller ZIP prefixes can have many latitude/longitude rows in raw geolocation.
- Haversine needs one coordinate per party; averaging by ZIP gives a stable approximation.
Trade-off:
- This is an approximation, but good enough for strategy-level analysis.
*/
DROP TABLE IF EXISTS marts.dim_zip_geo;
CREATE TABLE marts.dim_zip_geo AS
SELECT
  geolocation_zip_code_prefix AS zip_code_prefix,
  AVG(geolocation_lat) AS lat,
  AVG(geolocation_lng) AS lng,
  COUNT(*) AS point_count
FROM raw.olist_geolocation
WHERE geolocation_zip_code_prefix IS NOT NULL
GROUP BY geolocation_zip_code_prefix;

ALTER TABLE marts.dim_zip_geo
  ADD PRIMARY KEY (zip_code_prefix),
  ADD KEY idx_dim_zip_geo_point_count (point_count);

/*
[Chunk B] Build base join table before feature engineering
Why split this from final mart:
- Easier to validate joins and null patterns before adding complex formulas.
- Avoids debugging huge SQL blocks when one dimension table has data quality issues.
*/
DROP TABLE IF EXISTS marts.stg_order_item_joined;
CREATE TABLE marts.stg_order_item_joined AS
SELECT
  oi.order_id,
  oi.order_item_id,
  oi.product_id,
  oi.seller_id,
  o.customer_id,

  o.order_status,
  o.order_purchase_timestamp,
  o.order_approved_at,
  o.order_delivered_carrier_date,
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

ALTER TABLE marts.stg_order_item_joined
  ADD KEY idx_stg_order_id (order_id),
  ADD KEY idx_stg_month_ts (order_purchase_timestamp),
  ADD KEY idx_stg_seller_id (seller_id),
  ADD KEY idx_stg_customer_id (customer_id);

/*
[Chunk C] Build final item-grain fact table with engineered features
Feature rationale:
- is_free_shipping_item       : direct signal of policy activation.
- freight_price_ratio         : normalizes shipping burden by item price.
- delivery_days / delay_days  : customer experience and SLA adherence.
- distance_km                 : explanatory variable for freight and delivery time.
- hk_* flags                  : simulation-ready tags aligned with HK policy storytelling.
*/
DROP TABLE IF EXISTS marts.fact_order_item_enriched;
CREATE TABLE marts.fact_order_item_enriched AS
SELECT
  b.*,

  -- Join averaged geo coordinates for distance approximation.
  cz.lat AS customer_lat,
  cz.lng AS customer_lng,
  sz.lat AS seller_lat,
  sz.lng AS seller_lng,

  -- Haversine distance in KM: valid when both endpoints are available.
  CASE
    WHEN cz.lat IS NULL OR cz.lng IS NULL OR sz.lat IS NULL OR sz.lng IS NULL THEN NULL
    ELSE 6371 * 2 * ASIN(
      SQRT(
        POWER(SIN(RADIANS((cz.lat - sz.lat) / 2)), 2)
        + COS(RADIANS(sz.lat)) * COS(RADIANS(cz.lat))
        * POWER(SIN(RADIANS((cz.lng - sz.lng) / 2)), 2)
      )
    )
  END AS distance_km,

  -- Delivery duration from purchase to customer delivery.
  CASE
    WHEN b.order_delivered_customer_date IS NULL OR b.order_purchase_timestamp IS NULL THEN NULL
    ELSE TIMESTAMPDIFF(DAY, b.order_purchase_timestamp, b.order_delivered_customer_date)
  END AS delivery_days,

  -- Delay vs estimated date: positive = late, negative = early.
  CASE
    WHEN b.order_delivered_customer_date IS NULL OR b.order_estimated_delivery_date IS NULL THEN NULL
    ELSE DATEDIFF(b.order_delivered_customer_date, b.order_estimated_delivery_date)
  END AS delivery_delay_days,

  -- Freight burden relative to item value.
  CASE
    WHEN b.price IS NULL OR b.price <= 0 OR b.freight_value IS NULL THEN NULL
    ELSE b.freight_value / b.price
  END AS freight_price_ratio,

  CASE
    WHEN IFNULL(b.freight_value, 0) = 0 THEN 1 ELSE 0
  END AS is_free_shipping_item,

  -- Month key for trend and cohort analysis.
  DATE_FORMAT(b.order_purchase_timestamp, '%Y-%m') AS order_month,

  -- HK localization helper buckets for policy segmentation.
  CASE
    WHEN b.product_weight_g IS NULL THEN 'unknown'
    WHEN b.product_weight_g < 500 THEN 'light'
    WHEN b.product_weight_g < 2000 THEN 'medium'
    ELSE 'heavy'
  END AS hk_weight_band,

  CASE
    WHEN b.price IS NULL THEN 'unknown'
    WHEN b.price < 50 THEN 'A_0_49'
    WHEN b.price < 120 THEN 'B_50_119'
    WHEN b.price < 200 THEN 'C_120_199'
    ELSE 'D_200_plus'
  END AS hk_price_band
FROM marts.stg_order_item_joined b
LEFT JOIN marts.dim_zip_geo cz
  ON b.customer_zip_code_prefix = cz.zip_code_prefix
LEFT JOIN marts.dim_zip_geo sz
  ON b.seller_zip_code_prefix = sz.zip_code_prefix;

ALTER TABLE marts.fact_order_item_enriched
  ADD KEY idx_fact_order_id (order_id),
  ADD KEY idx_fact_month (order_month),
  ADD KEY idx_fact_seller_month (seller_id, order_month),
  ADD KEY idx_fact_free_item (is_free_shipping_item),
  ADD KEY idx_fact_distance (distance_km),
  ADD KEY idx_fact_weight_band (hk_weight_band),
  ADD KEY idx_fact_price_band (hk_price_band);

/*
[Chunk D] Order-grain metrics table
Why aggregate from item -> order:
- Policy and profitability decisions are usually taken at order basket level.
- Freight subsidy is funded at order level (customer sees one shipping experience).
*/
DROP TABLE IF EXISTS marts.order_level_metrics;
CREATE TABLE marts.order_level_metrics AS
SELECT
  order_id,
  MIN(order_month) AS order_month,
  MIN(order_purchase_timestamp) AS order_purchase_timestamp,
  MIN(order_status) AS order_status,
  MIN(customer_id) AS customer_id,

  SUM(IFNULL(price, 0)) AS order_gmv,
  SUM(IFNULL(freight_value, 0)) AS order_freight,
  AVG(delivery_days) AS avg_delivery_days,
  AVG(delivery_delay_days) AS avg_delivery_delay_days,
  AVG(distance_km) AS avg_distance_km,
  AVG(freight_price_ratio) AS avg_freight_ratio,
  SUM(IFNULL(product_weight_g, 0)) AS total_weight_g,

  CASE WHEN SUM(IFNULL(freight_value, 0)) = 0 THEN 1 ELSE 0 END AS is_free_shipping_order,

  -- Example HK strategy switch: threshold + distance cap.
  CASE
    WHEN SUM(IFNULL(price, 0)) >= 120
         AND IFNULL(AVG(distance_km), 999) <= 15
    THEN 1 ELSE 0
  END AS hk_sim_free_ship_flag
FROM marts.fact_order_item_enriched
GROUP BY order_id;

ALTER TABLE marts.order_level_metrics
  ADD PRIMARY KEY (order_id),
  ADD KEY idx_olm_month (order_month),
  ADD KEY idx_olm_free_order (is_free_shipping_order),
  ADD KEY idx_olm_sim_flag (hk_sim_free_ship_flag);

/*
[Chunk E] Join review signals to order metrics
Why average review at order_id:
- Some orders can have multiple review records in noisy datasets.
- Averaging is a robust, interview-friendly simplification.
*/
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
  ADD KEY idx_orm_month (order_month),
  ADD KEY idx_orm_review (review_score);

/*
[Chunk F] Monthly KPI mart (required deliverable)
- This table is compact and BI/dashboard friendly.
*/
DROP TABLE IF EXISTS marts.agg_monthly_kpi;
CREATE TABLE marts.agg_monthly_kpi AS
SELECT
  order_month,
  COUNT(*) AS orders,
  SUM(order_gmv) AS gmv,
  SUM(order_freight) AS freight_total,
  AVG(order_freight) AS avg_freight_per_order,
  AVG(avg_delivery_days) AS avg_delivery_days,
  AVG(avg_delivery_delay_days) AS avg_delivery_delay_days,
  AVG(avg_distance_km) AS avg_distance_km,
  AVG(avg_freight_ratio) AS avg_freight_ratio,
  AVG(review_score) AS avg_review_score,
  AVG(is_free_shipping_order) AS free_shipping_order_rate,
  AVG(hk_sim_free_ship_flag) AS hk_sim_apply_rate
FROM marts.order_review_metrics
GROUP BY order_month;

ALTER TABLE marts.agg_monthly_kpi
  ADD PRIMARY KEY (order_month);

/*
[Chunk G] Seller-month KPI mart (required deliverable)
- Helps identify campaign-like seller behavior and compare uplift.
*/
DROP TABLE IF EXISTS marts.agg_seller_monthly_kpi;
CREATE TABLE marts.agg_seller_monthly_kpi AS
SELECT
  seller_id,
  order_month,
  COUNT(DISTINCT order_id) AS orders,
  SUM(IFNULL(price, 0)) AS gmv,
  SUM(IFNULL(freight_value, 0)) AS freight_total,
  AVG(freight_value) AS avg_freight_item,
  AVG(delivery_days) AS avg_delivery_days,
  AVG(distance_km) AS avg_distance_km,
  AVG(CASE WHEN IFNULL(freight_value, 0) = 0 THEN 1 ELSE 0 END) AS free_shipping_item_rate,
  AVG(CASE WHEN hk_weight_band = 'heavy' THEN 1 ELSE 0 END) AS heavy_item_mix_rate
FROM marts.fact_order_item_enriched
GROUP BY seller_id, order_month;

ALTER TABLE marts.agg_seller_monthly_kpi
  ADD PRIMARY KEY (seller_id, order_month),
  ADD KEY idx_asmk_month (order_month),
  ADD KEY idx_asmk_free_ship_rate (free_shipping_item_rate);

/*
[Chunk H] Lightweight QA checks for mart build
- These checks help you confirm mart freshness and cardinality quality.
*/
SELECT 'marts.fact_order_item_enriched' AS table_name, COUNT(*) AS row_count FROM marts.fact_order_item_enriched
UNION ALL SELECT 'marts.order_level_metrics', COUNT(*) FROM marts.order_level_metrics
UNION ALL SELECT 'marts.order_review_metrics', COUNT(*) FROM marts.order_review_metrics
UNION ALL SELECT 'marts.agg_monthly_kpi', COUNT(*) FROM marts.agg_monthly_kpi
UNION ALL SELECT 'marts.agg_seller_monthly_kpi', COUNT(*) FROM marts.agg_seller_monthly_kpi;
