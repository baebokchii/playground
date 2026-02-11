# Olist HK Market Strategy Project: Free Shipping Policy Validation

## 1) Project Goal
Build an **end-to-end portfolio project** to validate whether a **Free Shipping Policy** can improve the business model for an Olist-like e-commerce marketplace in the **Hong Kong market**.

- **Business theme**: Improve current shipping policy to upgrade business performance.
- **Core strategy to test**: Introduce free shipping (`freight_value = 0`) under selected conditions.
- **Tech stack**: **MySQL + Python**.
- **Deliverables**: SQL data mart, analytical Python workflow, KPI outputs, recommendation memo.

---

## 2) Business Questions (English flow)

1. Is there a negative relationship between shipping cost and order volume?
2. How many orders naturally had zero freight (proxy for free shipping)?
3. Are there seller-months with campaign-like free-shipping behavior?
4. Did those periods show stronger order/GMV/review performance?
5. Under a Hong Kong policy rule (threshold + distance cap), is subsidy burden acceptable?

---

## 3) Database Layering (important for interview clarity)

This project uses `olist_portfolio` and 3 schemas:

- `raw`: CSV-ingested source tables (no heavy transformation)
- `marts`: reusable feature and KPI marts
- `analytics`: simulation tables/views and analysis helpers

Why this matters:
- Clear lineage (where each metric came from)
- Re-runnable demos (idempotent SQL)
- Easier maintenance and debugging

---

## 4) End-to-End Workflow

### Step A. Data Engineering in MySQL
1. Create database/schemas and raw tables (`sql/01_schema_and_load.sql`).
2. Load CSV files with `LOAD DATA LOCAL INFILE` (with `NULLIF` handling).
3. Build marts (`sql/02_feature_mart.sql`):
   - `marts.fact_order_item_enriched`
   - `marts.agg_monthly_kpi`
   - `marts.agg_seller_monthly_kpi`
4. Engineer core features:
   - Haversine distance (`distance_km`)
   - Delivery duration and delay
   - Freight ratio (`freight/price`)
   - Free-shipping flags (item/order)
   - HK simulation flag (`hk_sim_free_ship_flag`)

### Step B. Analysis SQL + Python
1. Run `sql/03_analysis_queries.sql` to generate analytical helpers in `analytics` schema.
2. Run Python script (`python/analysis_free_shipping_hk.py`) to:
   - pull marts/views,
   - run correlation and uplift analysis,
   - run Welch t-test,
   - export portfolio-ready CSV outputs.

### Step C. Business Recommendation
1. Compare free vs paid shipping performance.
2. Estimate subsidy cost under HK policy simulation.
3. Recommend pilot guardrails (distance cap, threshold, weight control).

---

## 5) Folder Structure

```text
projects/olist-hk-free-shipping/
├─ README.md
├─ sql/
│  ├─ 01_schema_and_load.sql
│  ├─ 02_feature_mart.sql
│  └─ 03_analysis_queries.sql
└─ python/
   ├─ analysis_free_shipping_hk.py
   └─ requirements.txt
```

---

## 6) How to Run

### 6.1 MySQL
```bash
mysql -u <user> -p
```

```sql
SOURCE projects/olist-hk-free-shipping/sql/01_schema_and_load.sql;
SOURCE projects/olist-hk-free-shipping/sql/02_feature_mart.sql;
SOURCE projects/olist-hk-free-shipping/sql/03_analysis_queries.sql;
```

### 6.2 Python
```bash
cd projects/olist-hk-free-shipping/python
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python analysis_free_shipping_hk.py --host localhost --port 3306 --user root --password '<pw>' --database olist_portfolio
```

Output path:
- `projects/olist-hk-free-shipping/outputs/`

---

## 7) KPI Definitions

- **Order Count**: distinct `order_id`
- **GMV**: sum of `price`
- **Freight Cost**: sum of `freight_value`
- **Free Shipping Order Rate**: share of orders with total freight = 0
- **Average Delivery Days**: `TIMESTAMPDIFF(DAY, purchase_ts, delivered_customer_ts)`
- **Average Delivery Delay Days**: `DATEDIFF(delivered_customer_ts, estimated_delivery_ts)`
- **Freight-to-Price Ratio**: `freight_value / price`
- **Subsidy Burden Ratio**: `subsidy_cost_estimate / GMV`

---

## 8) Suggested Portfolio Narrative (Hong Kong)

1. **Problem**: shipping fee sensitivity can suppress conversion in a dense convenience-first market.
2. **Evidence**: free-shipping segments show better order economics and/or customer sentiment.
3. **Simulation**: threshold-based free shipping can be controlled via distance and weight guardrails.
4. **Decision**: launch targeted pilot before full rollout.
5. **Risk control**: monitor post-promotion drop-off and enforce subsidy budget caps.
