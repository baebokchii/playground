"""
End-to-end analysis runner for Olist HK free-shipping strategy.

This script assumes you already built marts/analytics objects via:
  1) sql/01_schema_and_load.sql
  2) sql/02_feature_mart.sql
  3) sql/03_analysis_queries.sql

Usage example:
python analysis_free_shipping_hk.py \
  --host localhost --port 3306 --user root --password 'pw' --database olist_portfolio
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import stats
from sqlalchemy import create_engine, text


# ------------------------------
# CLI + connection helpers
# ------------------------------
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Olist HK free-shipping analysis")
    parser.add_argument("--host", default="localhost")
    parser.add_argument("--port", default=3306, type=int)
    parser.add_argument("--user", required=True)
    parser.add_argument("--password", required=True)
    parser.add_argument("--database", default="olist_portfolio")
    parser.add_argument("--outdir", default="../outputs")
    return parser.parse_args()


def build_engine(args: argparse.Namespace):
    conn_str = (
        f"mysql+pymysql://{args.user}:{args.password}@{args.host}:{args.port}/{args.database}"
    )
    return create_engine(conn_str)


# ------------------------------
# Data extraction (SQL -> Pandas)
# ------------------------------
def fetch_dataframes(engine):
    monthly = pd.read_sql(
        text(
            """
            SELECT *
            FROM marts.agg_monthly_kpi
            ORDER BY order_month
            """
        ),
        engine,
    )

    corr_input = pd.read_sql(
        text(
            """
            SELECT *
            FROM analytics.v_monthly_corr_input
            ORDER BY order_month
            """
        ),
        engine,
    )

    order_review = pd.read_sql(
        text(
            """
            SELECT
                order_id,
                order_month,
                order_gmv,
                order_freight,
                is_free_shipping_order,
                hk_sim_free_ship_flag,
                avg_delivery_days,
                avg_distance_km,
                review_score
            FROM marts.order_review_metrics
            """
        ),
        engine,
    )

    seller_monthly = pd.read_sql(
        text(
            """
            SELECT *
            FROM marts.agg_seller_monthly_kpi
            """
        ),
        engine,
    )

    policy_sim = pd.read_sql(
        text(
            """
            SELECT *
            FROM analytics.sim_hk_policy_monthly
            ORDER BY order_month
            """
        ),
        engine,
    )

    return monthly, corr_input, order_review, seller_monthly, policy_sim


# ------------------------------
# Analysis blocks
# ------------------------------
def correlation_analysis(corr_input: pd.DataFrame) -> pd.DataFrame:
    cols = [
        "avg_delivery_days",
        "avg_distance_km",
        "order_count",
        "avg_freight_per_order",
        "free_shipping_order_rate",
    ]
    return corr_input[cols].corr(method="pearson")


def uplift_analysis(order_review: pd.DataFrame) -> pd.DataFrame:
    summary = (
        order_review.groupby("is_free_shipping_order", dropna=False)
        .agg(
            orders=("order_id", "nunique"),
            avg_gmv=("order_gmv", "mean"),
            avg_freight=("order_freight", "mean"),
            avg_delivery_days=("avg_delivery_days", "mean"),
            avg_review=("review_score", "mean"),
        )
        .reset_index()
    )
    summary["segment"] = np.where(
        summary["is_free_shipping_order"] == 1,
        "FreeShipping",
        "PaidShipping",
    )
    return summary


def simulation_uplift_analysis(order_review: pd.DataFrame) -> pd.DataFrame:
    summary = (
        order_review.groupby("hk_sim_free_ship_flag", dropna=False)
        .agg(
            orders=("order_id", "nunique"),
            avg_gmv=("order_gmv", "mean"),
            avg_freight=("order_freight", "mean"),
            avg_delivery_days=("avg_delivery_days", "mean"),
            avg_review=("review_score", "mean"),
        )
        .reset_index()
    )
    summary["segment"] = np.where(
        summary["hk_sim_free_ship_flag"] == 1,
        "HK_Policy_Eligible",
        "HK_Policy_NotEligible",
    )
    return summary


def ttest_analysis(order_review: pd.DataFrame) -> pd.DataFrame:
    free = order_review.loc[
        (order_review["is_free_shipping_order"] == 1)
        & (order_review["review_score"].notna()),
        "review_score",
    ]
    paid = order_review.loc[
        (order_review["is_free_shipping_order"] == 0)
        & (order_review["review_score"].notna()),
        "review_score",
    ]

    t_stat, p_val = stats.ttest_ind(free, paid, equal_var=False, nan_policy="omit")

    return pd.DataFrame(
        {
            "metric": ["review_score"],
            "group_a": ["FreeShipping"],
            "group_b": ["PaidShipping"],
            "mean_a": [free.mean()],
            "mean_b": [paid.mean()],
            "t_stat": [t_stat],
            "p_value": [p_val],
            "n_a": [free.shape[0]],
            "n_b": [paid.shape[0]],
        }
    )


def detect_campaign_sellers(seller_monthly: pd.DataFrame) -> pd.DataFrame:
    df = seller_monthly.copy()
    candidate = df[(df["free_shipping_item_rate"] >= 0.8) & (df["orders"] >= 30)]

    if candidate.empty:
        return pd.DataFrame(
            columns=[
                "seller_id",
                "campaign_months",
                "avg_orders_campaign",
                "avg_orders_non_campaign",
                "order_uplift_pct",
                "avg_gmv_campaign",
                "avg_gmv_non_campaign",
                "gmv_uplift_pct",
            ]
        )

    campaign_keys = set(zip(candidate["seller_id"], candidate["order_month"]))

    df["is_campaign_month"] = df.apply(
        lambda x: (x["seller_id"], x["order_month"]) in campaign_keys,
        axis=1,
    )

    rows = []
    for seller, part in df.groupby("seller_id"):
        camp = part[part["is_campaign_month"]]
        non = part[~part["is_campaign_month"]]
        if camp.empty or non.empty:
            continue

        avg_orders_campaign = camp["orders"].mean()
        avg_orders_non = non["orders"].mean()
        avg_gmv_campaign = camp["gmv"].mean()
        avg_gmv_non = non["gmv"].mean()

        rows.append(
            {
                "seller_id": seller,
                "campaign_months": ", ".join(sorted(camp["order_month"].astype(str).unique())),
                "avg_orders_campaign": avg_orders_campaign,
                "avg_orders_non_campaign": avg_orders_non,
                "order_uplift_pct": ((avg_orders_campaign - avg_orders_non) / avg_orders_non) * 100
                if avg_orders_non > 0
                else np.nan,
                "avg_gmv_campaign": avg_gmv_campaign,
                "avg_gmv_non_campaign": avg_gmv_non,
                "gmv_uplift_pct": ((avg_gmv_campaign - avg_gmv_non) / avg_gmv_non) * 100
                if avg_gmv_non > 0
                else np.nan,
            }
        )

    return pd.DataFrame(rows).sort_values("gmv_uplift_pct", ascending=False)


def build_recommendation_text(
    corr_df: pd.DataFrame,
    uplift_df: pd.DataFrame,
    ttest_df: pd.DataFrame,
    seller_uplift_df: pd.DataFrame,
    policy_sim: pd.DataFrame,
) -> str:
    corr_ship_order = corr_df.loc["order_count", "avg_freight_per_order"]

    free_row = uplift_df[uplift_df["segment"] == "FreeShipping"].iloc[0]
    paid_row = uplift_df[uplift_df["segment"] == "PaidShipping"].iloc[0]

    review_delta = free_row["avg_review"] - paid_row["avg_review"]
    gmv_delta_pct = ((free_row["avg_gmv"] - paid_row["avg_gmv"]) / paid_row["avg_gmv"]) * 100

    p_val = ttest_df.loc[0, "p_value"]
    sig = "statistically significant" if p_val < 0.05 else "not statistically significant"

    seller_line = "No campaign-like seller months detected under current thresholds."
    if not seller_uplift_df.empty:
        top = seller_uplift_df.iloc[0]
        seller_line = (
            f"Top campaign-like seller {top['seller_id']} showed "
            f"{top['gmv_uplift_pct']:.1f}% GMV uplift in campaign months."
        )

    avg_apply_rate = policy_sim["apply_rate"].mean() if not policy_sim.empty else np.nan
    avg_subsidy = (
        policy_sim["subsidy_cost_estimate"].sum() / policy_sim["gmv"].sum() * 100
        if not policy_sim.empty and policy_sim["gmv"].sum() > 0
        else np.nan
    )

    recommendation = f"""
[HK Free Shipping Strategy Recommendation]
1) Freight vs Orders correlation: {corr_ship_order:.3f} (negative is better for free-shipping rationale).
2) Free-shipping orders have {gmv_delta_pct:.1f}% higher average order GMV than paid-shipping orders.
3) Review score delta (Free - Paid): {review_delta:.3f}, and t-test is {sig} (p={p_val:.4g}).
4) {seller_line}
5) HK simulation average apply-rate: {avg_apply_rate:.2%}.
6) Estimated subsidy burden ratio: {avg_subsidy:.2f}% of GMV.

Action:
- Run a 2-month pilot in Hong Kong with threshold-based free shipping.
- Set subsidy caps by distance and item weight.
- Track post-campaign retention and repeat purchase rate before full rollout.
""".strip()
    return recommendation


# ------------------------------
# Main execution
# ------------------------------
def main() -> None:
    args = parse_args()
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    engine = build_engine(args)

    monthly, corr_input, order_review, seller_monthly, policy_sim = fetch_dataframes(engine)

    corr_df = correlation_analysis(corr_input)
    uplift_df = uplift_analysis(order_review)
    sim_uplift_df = simulation_uplift_analysis(order_review)
    ttest_df = ttest_analysis(order_review)
    seller_uplift_df = detect_campaign_sellers(seller_monthly)

    recommendation = build_recommendation_text(
        corr_df,
        uplift_df,
        ttest_df,
        seller_uplift_df,
        policy_sim,
    )

    monthly.to_csv(outdir / "monthly_kpi.csv", index=False)
    corr_input.to_csv(outdir / "monthly_corr_input.csv", index=False)
    corr_df.to_csv(outdir / "correlation_matrix.csv")
    uplift_df.to_csv(outdir / "shipping_segment_uplift.csv", index=False)
    sim_uplift_df.to_csv(outdir / "hk_policy_eligibility_uplift.csv", index=False)
    ttest_df.to_csv(outdir / "ttest_review_score.csv", index=False)
    seller_uplift_df.to_csv(outdir / "seller_campaign_uplift.csv", index=False)
    policy_sim.to_csv(outdir / "hk_policy_monthly_simulation.csv", index=False)

    (outdir / "recommendation.txt").write_text(recommendation, encoding="utf-8")

    print("Analysis complete. Output files:")
    for p in sorted(outdir.glob("*")):
        print(f"- {p.resolve()}")


if __name__ == "__main__":
    main()
