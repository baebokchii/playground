-- ============================================================
-- 03_analysis_queries.sql
-- Purpose: KPI queries for free-shipping policy validation
-- ============================================================

USE olist_hk;

-- Q1. Monthly correlation-ready base metrics
SELECT
    order_month,
    AVG(avg_delivery_days) AS avg_delivery_days,
    AVG(avg_distance_km) AS avg_distance_km,
    COUNT(*) AS order_count,
    AVG(order_freight) AS avg_freight_per_order
FROM order_level_metrics
GROUP BY order_month
ORDER BY order_month;

-- Q2. Count orders with freight = 0 by month (free shipping occurrence)
SELECT
    order_month,
    COUNT(*) AS free_shipping_orders
FROM order_level_metrics
WHERE is_free_shipping_order = 1
GROUP BY order_month
ORDER BY order_month;

-- Q3. Identify sellers with campaign-like free-shipping behavior
-- Condition: seller-month free_shipping_item_rate >= 0.8 and at least 30 orders
SELECT
    seller_id,
    order_month,
    orders,
    gmv,
    freight_total,
    free_shipping_item_rate
FROM agg_seller_monthly_kpi
WHERE free_shipping_item_rate >= 0.8
  AND orders >= 30
ORDER BY order_month, orders DESC;

-- Q4. Did campaign-like seller months show higher order count / GMV?
WITH campaign_seller_month AS (
    SELECT seller_id, order_month
    FROM agg_seller_monthly_kpi
    WHERE free_shipping_item_rate >= 0.8
      AND orders >= 30
)
SELECT
    CASE WHEN csm.seller_id IS NOT NULL THEN 'CampaignLike' ELSE 'NonCampaign' END AS segment,
    COUNT(DISTINCT f.order_id) AS orders,
    SUM(f.price) AS gmv,
    AVG(f.freight_value) AS avg_item_freight,
    AVG(f.delivery_days) AS avg_delivery_days
FROM fact_order_item_enriched f
LEFT JOIN campaign_seller_month csm
  ON f.seller_id = csm.seller_id
 AND f.order_month = csm.order_month
GROUP BY segment;

-- Q5. Review score lift: free-shipping order vs non-free-shipping order
SELECT
    CASE WHEN is_free_shipping_order = 1 THEN 'FreeShipping' ELSE 'PaidShipping' END AS shipping_type,
    COUNT(*) AS orders,
    AVG(review_score) AS avg_review_score
FROM order_review_metrics
WHERE review_score IS NOT NULL
GROUP BY shipping_type;

-- Q6. Correlation helper table for Python (monthly level)
DROP VIEW IF EXISTS v_monthly_corr_input;
CREATE VIEW v_monthly_corr_input AS
SELECT
    order_month,
    AVG(avg_delivery_days) AS avg_delivery_days,
    AVG(avg_distance_km) AS avg_distance_km,
    COUNT(*) AS order_count,
    AVG(order_freight) AS avg_freight_per_order
FROM order_level_metrics
GROUP BY order_month;

SELECT * FROM v_monthly_corr_input ORDER BY order_month;

-- Q7. HK-ready policy simulation
-- Rule example: free shipping if order_gmv >= threshold and distance <= distance cap
SET @threshold_hkd = 120;
SET @distance_cap_km = 15;

WITH simulated AS (
    SELECT
        order_id,
        order_month,
        order_gmv,
        order_freight,
        avg_distance_km,
        CASE
            WHEN order_gmv >= @threshold_hkd
                 AND IFNULL(avg_distance_km, 999) <= @distance_cap_km
            THEN 1 ELSE 0
        END AS simulate_free_ship
    FROM order_level_metrics
)
SELECT
    order_month,
    COUNT(*) AS orders,
    SUM(order_gmv) AS gmv,
    SUM(CASE WHEN simulate_free_ship = 1 THEN order_freight ELSE 0 END) AS subsidy_cost_estimate,
    AVG(CASE WHEN simulate_free_ship = 1 THEN order_freight END) AS avg_subsidy_when_applied,
    SUM(CASE WHEN simulate_free_ship = 1 THEN 1 ELSE 0 END) / COUNT(*) AS apply_rate
FROM simulated
GROUP BY order_month
ORDER BY order_month;

-- Q8. Seller-level before/after for identified campaign months
WITH candidate AS (
    SELECT seller_id, order_month
    FROM agg_seller_monthly_kpi
    WHERE free_shipping_item_rate >= 0.8 AND orders >= 30
),
seller_month AS (
    SELECT seller_id, order_month, orders, gmv
    FROM agg_seller_monthly_kpi
)
SELECT
    sm.seller_id,
    sm.order_month,
    sm.orders,
    sm.gmv,
    CASE WHEN c.seller_id IS NULL THEN 0 ELSE 1 END AS is_campaign_month
FROM seller_month sm
LEFT JOIN candidate c
  ON sm.seller_id = c.seller_id AND sm.order_month = c.order_month
WHERE sm.seller_id IN (SELECT DISTINCT seller_id FROM candidate)
ORDER BY sm.seller_id, sm.order_month;
