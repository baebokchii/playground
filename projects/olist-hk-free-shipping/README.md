# Olist Portfolio Project: Shipping Policy Optimization
## 1) Project Goal
Build an **end-to-end portfolio project** to validate whether **shipping policy improvement** can upgrade an e-commerce business model.
- **Business theme**: Business model enhancement through policy optimization.
- **Strategy hypothesis**: Reducing shipping burden (e.g., free-shipping conditions) can improve conversion, GMV, and customer satisfaction.
- **Tech stack**: **MySQL + Python**.
- **Deliverables**: Raw-to-mart SQL pipeline, analysis SQL, Python validation workflow, recommendation memo.
## 2) Core Business Questions
1. Is higher shipping cost associated with lower order activity?
2. Do low-freight/free-shipping orders show better GMV or review outcomes?
3. Which seller-month patterns resemble policy/campaign behavior?
4. What subsidy burden appears under a threshold-based shipping policy?
5. Can the strategy be rolled out with guardrails (distance/weight/cost caps)?
## 3) Data Architecture
Database: `olist_portfolio`
- `raw`: source-ingested tables
- `marts`: reusable analysis marts
- `analytics`: simulation outputs and helper views
## 4) End-to-End Workflow
### Step A. Data Engineering (MySQL)
1. Run `sql/01_schema_and_load.sql` to create schemas/tables and load CSVs.
2. Run `sql/02_feature_mart.sql` to build marts:
   - `marts.fact_order_item_enriched`
   - `marts.order_level_metrics`
   - `marts.order_review_metrics`
   - `marts.agg_monthly_kpi`
   - `marts.agg_seller_monthly_kpi`
3. Engineered features include:
   - `distance_km` (Haversine)
   - `delivery_days`, `delivery_delay_days`
   - `freight_price_ratio`
   - free-shipping flags
   - policy simulation flag (`policy_sim_free_ship_flag`)
### Step B. Analysis Layer
1. Run `sql/03_analysis_queries.sql` to create:
   - `analytics.v_campaign_like_seller_month`
   - `analytics.v_monthly_corr_input`
   - `analytics.sim_policy_monthly`
2. Run Python:
   - correlation
   - segment uplift
   - Welch t-test
   - campaign-like seller uplift
   - policy simulation summary export
### Step C. Recommendation
1. Compare free-shipping vs paid-shipping outcomes.
2. Estimate subsidy burden against GMV.
3. Recommend rollout sequence and cost guardrails.
## 5) Run Commands
```sql
SOURCE projects/olist-hk-free-shipping/sql/01_schema_and_load.sql;
SOURCE projects/olist-hk-free-shipping/sql/02_feature_mart.sql;
SOURCE projects/olist-hk-free-shipping/sql/03_analysis_queries.sql;
```
```bash
cd projects/olist-hk-free-shipping/python
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python analysis_free_shipping_hk.py --host localhost --port 3306 --user root --password '<pw>' --database olist_portfolio
```
Outputs are saved under `projects/olist-hk-free-shipping/outputs/`.
## 6) KPI Definitions
- Order Count: distinct `order_id`
- GMV: sum of item `price`
- Freight Cost: sum of `freight_value`
- Free Shipping Order Rate: share of orders with freight total = 0
- Delivery Days: purchase to delivered
- Delivery Delay Days: delivered minus estimated delivery date
- Freight Ratio: `freight_value / price`
- Subsidy Burden Ratio: simulated subsidy / GMV
