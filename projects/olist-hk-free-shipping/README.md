# Olist HK Market Strategy Project: Free Shipping Policy Validation

## 1) Project Goal
Build an **end-to-end portfolio project** to validate whether a **Free Shipping Policy** can improve the business model for an Olist-like e-commerce marketplace in the **Hong Kong market**.

- **Business theme**: Improve current shipping policy to upgrade business performance.
- **Core strategy to test**: Introduce free shipping (`freight_value = 0`) under selected conditions.
- **Tech stack**: **MySQL + Python**.
- **Deliverables**: SQL data mart, analytical Python workflow, KPI dashboard-ready outputs, recommendation memo.

---

## 2) Business Questions (English version of your slide flow)

### Part 1 — Free Shipping Policy Introduction
1. Is there a negative relationship between shipping cost and order volume?
2. How many orders have zero freight value?
3. Are there sellers/months where free shipping was effectively run (pilot-like behavior)?
4. During those periods, did order count, sales amount, and review scores improve?
5. Is the improvement large enough to justify policy rollout in Hong Kong?

### Appendix / Diagnostic Questions
1. Is freight mostly explained by distance and product weight?
2. Are there hidden factors (state, seller behavior, product mix) causing freight differences?
3. Did “free-shipping sellers” always provide free shipping, or only in campaign periods?
4. What happened after campaign months (drop-off / retention risk)?

---

## 3) Data Scope and Hong Kong Localization

### Source tables
Use the 9 source datasets you listed:
- customers, geolocation, orders, order_items, order_payments, products, sellers, category_translation, reviews.

### HK localization assumptions
Because Olist is Brazil-based data, we define a **market localization layer** for portfolio storytelling:
- Currency label for presentation: **HKD equivalent** (for communication only; not FX-converted unless you add FX table).
- Shipping strategy logic for HK:
  - Dense urban deliveries: lower distance sensitivity than regional Brazil.
  - Cross-district SLA expectations are strict (delivery speed heavily affects review score).
- Policy candidate (example):
  - Free shipping above basket threshold.
  - Partial subsidy for heavy/long-distance orders.
  - Seller co-funding for campaign windows.

---

## 4) End-to-End Workflow

### Step A. Data Engineering in MySQL
1. Create raw tables.
2. Load CSVs with `LOAD DATA LOCAL INFILE`.
3. Build analytical marts:
   - `fact_order_item_enriched`
   - `agg_monthly_kpi`
   - `agg_seller_monthly_kpi`
4. Add distance (Haversine), delivery duration, freight ratio, free-shipping flags.

### Step B. Exploratory + Causal-leaning Analysis in Python
1. Pull marts using SQLAlchemy.
2. Validate nulls/outliers.
3. Reproduce slide logic:
   - Correlation matrix (shipping vs order count, delivery days, distance).
   - Monthly trend for free-shipping vs non-free-shipping segments.
   - Sales uplift and review score lift.
4. Run statistical checks:
   - Welch t-test for mean differences.
   - Simple OLS or fixed-effect style controls (optional extension).

### Step C. Business Recommendation
1. Identify policy uplift and cost burden.
2. Define target segments (category, seller tier, distance band).
3. Recommend rollout plan for HK:
   - Pilot → expand → full-scale governance.
4. Include risk controls (post-promo drop, subsidy cap, margin guardrail).

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

### 6.1 MySQL setup
```bash
mysql -u <user> -p
```

```sql
SOURCE projects/olist-hk-free-shipping/sql/01_schema_and_load.sql;
SOURCE projects/olist-hk-free-shipping/sql/02_feature_mart.sql;
SOURCE projects/olist-hk-free-shipping/sql/03_analysis_queries.sql;
```

### 6.2 Python analysis
```bash
cd projects/olist-hk-free-shipping/python
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python analysis_free_shipping_hk.py --host localhost --port 3306 --user root --password '<pw>' --database olist_hk
```

Outputs are written to:
- `projects/olist-hk-free-shipping/outputs/`

---

## 7) KPI Definitions

- **Order Count**: distinct `order_id`
- **GMV**: sum of `price`
- **Freight Cost**: sum of `freight_value`
- **Free Shipping Order Rate**: share of orders where total freight = 0
- **Average Delivery Days**: `DATEDIFF(delivered_customer_date, purchase_timestamp)`
- **Review Score**: average `review_score`
- **Freight-to-Price Ratio**: `freight_value / price`
- **Uplift (%)**: `(policy_period_avg - baseline_avg) / baseline_avg`

---

## 8) Suggested Portfolio Narrative (Hong Kong)

1. **Problem**: High delivery fee sensitivity suppresses conversion in a dense, convenience-driven market.
2. **Evidence**: Lower freight aligns with higher orders and better customer sentiment.
3. **Policy simulation**: Free shipping windows show meaningful order/sales/review lift.
4. **Decision**: Roll out targeted free shipping with margin-safe constraints.
5. **Impact target** (example):
   - +8~15% order growth,
   - +5~10% GMV growth,
   - +0.1~0.3 review score gain,
   - controlled subsidy ratio under 3~5% of GMV.

---

## 9) Interview-Ready Talking Points

- Why this is not “just correlation”:
  - controlled comparisons by month/seller/category,
  - hypothesis testing,
  - robustness checks around seasonality.
- Why it is viable in HK:
  - short-distance logistics network,
  - high customer expectation for fast + low-friction delivery,
  - strategy can be constrained by threshold and seller co-funding.

