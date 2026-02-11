-- ==================================================================================================
-- 03_analysis_queries.sql
-- Project : Olist HK Free Shipping Strategy (Portfolio)
-- Goal    : Produce interview-ready analysis outputs validating free-shipping feasibility.
-- DB      : olist_portfolio (source: marts, output helpers: analytics)
-- ==================================================================================================

USE olist_portfolio;

/*
[Chunk A] Monthly baseline trend (core storyline)
Why this is first:
- Any policy discussion should begin with the baseline trajectory of orders/freight/delivery.
*/
SELECT
  order_month,
  orders,
  gmv,
  freight_total,
  avg_freight_per_order,
  avg_delivery_days,
  avg_delivery_delay_days,
  avg_distance_km,
  avg_review_score,
  free_shipping_order_rate
FROM marts.agg_monthly_kpi
ORDER BY order_month;

/*
[Chunk B] Free shipping occurrence trend
- Shows whether "natural experiments" already exist in historical data.
*/
SELECT
  order_month,
  COUNT(*) AS free_shipping_orders,
  SUM(order_gmv) AS free_shipping_gmv,
  AVG(review_score) AS free_shipping_avg_review
FROM marts.order_review_metrics
WHERE is_free_shipping_order = 1
GROUP BY order_month
ORDER BY order_month;

/*
[Chunk C] Campaign-like seller month detection
Rule logic (editable):
- free_shipping_item_rate >= 0.8  (mostly free shipping in that month)
- orders >= 30                    (enough volume to avoid tiny-sample noise)
*/
DROP VIEW IF EXISTS analytics.v_campaign_like_seller_month;
CREATE VIEW analytics.v_campaign_like_seller_month AS
SELECT
  seller_id,
  order_month,
  orders,
  gmv,
  freight_total,
  free_shipping_item_rate,
  heavy_item_mix_rate
FROM marts.agg_seller_monthly_kpi
WHERE free_shipping_item_rate >= 0.8
  AND orders >= 30;

SELECT *
FROM analytics.v_campaign_like_seller_month
ORDER BY order_month, orders DESC;

/*
[Chunk D] Segment comparison: campaign-like vs non-campaign
- Helps answer "did those campaign-like periods perform better?"
*/
SELECT
  CASE
    WHEN c.seller_id IS NOT NULL THEN 'CampaignLike'
    ELSE 'NonCampaign'
  END AS segment,
  COUNT(DISTINCT f.order_id) AS orders,
  SUM(f.price) AS gmv,
  AVG(f.freight_value) AS avg_item_freight,
  AVG(f.delivery_days) AS avg_delivery_days,
  AVG(f.delivery_delay_days) AS avg_delay_days
FROM marts.fact_order_item_enriched f
LEFT JOIN analytics.v_campaign_like_seller_month c
  ON f.seller_id = c.seller_id
 AND f.order_month = c.order_month
GROUP BY 1;

/*
[Chunk E] Customer sentiment check (review score)
- Free shipping can be justified not only by volume but also by better CX signals.
*/
SELECT
  CASE WHEN is_free_shipping_order = 1 THEN 'FreeShipping' ELSE 'PaidShipping' END AS shipping_type,
  COUNT(*) AS orders,
  AVG(order_gmv) AS avg_order_gmv,
  AVG(order_freight) AS avg_order_freight,
  AVG(avg_delivery_days) AS avg_delivery_days,
  AVG(review_score) AS avg_review_score
FROM marts.order_review_metrics
WHERE review_score IS NOT NULL
GROUP BY 1;

/*
[Chunk F] Correlation input view for Python
- Keep modeling input in a stable view so notebook/script queries stay simple.
*/
DROP VIEW IF EXISTS analytics.v_monthly_corr_input;
CREATE VIEW analytics.v_monthly_corr_input AS
SELECT
  order_month,
  orders AS order_count,
  avg_freight_per_order,
  avg_delivery_days,
  avg_distance_km,
  avg_review_score,
  free_shipping_order_rate,
  hk_sim_apply_rate
FROM marts.agg_monthly_kpi;

SELECT *
FROM analytics.v_monthly_corr_input
ORDER BY order_month;

/*
[Chunk G] HK policy simulation (threshold + distance cap)
- This is the main policy what-if analysis.
- Subsidy cost estimate = freight we would waive when policy applies.
*/
SET @threshold_hkd = 120;
SET @distance_cap_km = 15;

DROP TABLE IF EXISTS analytics.sim_hk_policy_monthly;
CREATE TABLE analytics.sim_hk_policy_monthly AS
WITH simulated AS (
  SELECT
    order_id,
    order_month,
    order_gmv,
    order_freight,
    avg_distance_km,
    total_weight_g,
    CASE
      WHEN order_gmv >= @threshold_hkd
       AND IFNULL(avg_distance_km, 999) <= @distance_cap_km
      THEN 1 ELSE 0
    END AS simulate_free_ship
  FROM marts.order_level_metrics
)
SELECT
  order_month,
  COUNT(*) AS orders,
  SUM(order_gmv) AS gmv,
  SUM(CASE WHEN simulate_free_ship = 1 THEN order_freight ELSE 0 END) AS subsidy_cost_estimate,
  AVG(CASE WHEN simulate_free_ship = 1 THEN order_freight END) AS avg_subsidy_if_applied,
  AVG(CASE WHEN simulate_free_ship = 1 THEN total_weight_g END) AS avg_weight_if_applied,
  AVG(simulate_free_ship) AS apply_rate
FROM simulated
GROUP BY order_month;

SELECT *
FROM analytics.sim_hk_policy_monthly
ORDER BY order_month;

/*
[Chunk H] Seller before/after diagnostic table
- Useful to discuss retention risk after free-shipping campaign windows.
*/
DROP TABLE IF EXISTS analytics.seller_campaign_timeline;
CREATE TABLE analytics.seller_campaign_timeline AS
SELECT
  sm.seller_id,
  sm.order_month,
  sm.orders,
  sm.gmv,
  sm.freight_total,
  sm.free_shipping_item_rate,
  CASE WHEN c.seller_id IS NULL THEN 0 ELSE 1 END AS is_campaign_month
FROM marts.agg_seller_monthly_kpi sm
LEFT JOIN analytics.v_campaign_like_seller_month c
  ON sm.seller_id = c.seller_id
 AND sm.order_month = c.order_month
WHERE sm.seller_id IN (
  SELECT DISTINCT seller_id
  FROM analytics.v_campaign_like_seller_month
);

SELECT *
FROM analytics.seller_campaign_timeline
ORDER BY seller_id, order_month;
