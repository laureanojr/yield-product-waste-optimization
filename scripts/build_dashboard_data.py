"""Aggregate the cleaned sales data into a compact, dashboard-ready table.
Grain: one row per (date, product). Keeps day-of-week and month for the BI layer.
"""
import pandas as pd

df = pd.read_csv("data/cleaned/bakery_sales_clean.csv", parse_dates=["datetime"])

df["sale_date"]   = df["datetime"].dt.date
df["day_of_week"] = df["datetime"].dt.day_name()
df["sale_month"]  = df["datetime"].dt.to_period("M").dt.to_timestamp().dt.date

agg = (df.groupby(["sale_date", "day_of_week", "sale_month", "article"], as_index=False)
         .agg(units=("Quantity", "sum"),
              revenue=("revenue", "sum")))
agg = agg.rename(columns={"article": "product"})
agg["revenue"] = agg["revenue"].round(2)

agg.to_csv("data/processed/dashboard_data.csv", index=False)
print(f"Wrote {len(agg):,} rows to data/processed/dashboard_data.csv")
