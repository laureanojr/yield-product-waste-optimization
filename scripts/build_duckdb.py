#!/usr/bin/env python3
"""
build_duckdb.py
The entire project, end to end, on a laptop. No cloud account. No billing.

    pip install -r requirements.txt
    python scripts/build_duckdb.py

Builds bakery.duckdb from data/cleaned/bakery_sales_clean.csv:
  real layer -> dimensions -> generate synthetic events -> KPI views -> validate

WHY THIS EXISTS
The pipeline was built on BigQuery and those scripts are still in sql/synthetic/.
They ran; they are the record. But a repo that needs a Google Cloud account is a
repo nobody runs, and reproducibility is a stated standard of this project. This
is what it costs to actually mean it.

The generator's logic is imported from generate_synthetic_production.py — the
SAME code that ran against BigQuery. Only the data source changed. If the two
engines disagreed, one of them would be lying.
"""

from __future__ import annotations

import sys
from pathlib import Path

import duckdb
import pandas as pd
import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from generate_synthetic_production import (   # noqa: E402
    build_plant_demand,
    generate,
    validate as validate_generation,
)

DB = ROOT / "bakery.duckdb"
SQL = ROOT / "sql" / "duckdb"
CONFIG = ROOT / "config" / "synthetic_generator.yaml"


# =============================================================================
# Validation — the checks that would catch a broken layer BEFORE it reaches a
# dashboard or an interview. Each returns a count; anything but zero is a fail.
# =============================================================================
CHECKS: list[tuple[str, str]] = [

    # THE ONE THAT MATTERS. If A x P x Q does not equal OEE, the decomposition is
    # decorative and every conclusion drawn from it is worthless.
    ("OEE reconciles from A x P x Q at batch grain",
     "SELECT COUNT(*) FROM v_batch_oee "
     "WHERE ABS(availability * performance * quality - oee) > 1e-6"),

    # And it must still hold after aggregation. Naive unit-based rollups break
    # here once products have different ideal rates.
    ("OEE reconciles after aggregation",
     "SELECT COUNT(*) FROM v_oee_daily "
     "WHERE ABS(availability * performance * quality - oee) > 1e-3"),

    # A plant producing faster than its own theoretical maximum has a broken
    # standard. One careless round() is enough to cause this.
    ("Performance never exceeds 1.0",
     "SELECT COUNT(*) FROM v_batch_oee WHERE performance > 1.0"),

    ("every OEE term is inside (0, 1]",
     "SELECT COUNT(*) FROM v_batch_oee WHERE availability > 1.0 OR quality > 1.0 "
     "OR availability <= 0 OR quality <= 0 OR performance <= 0"),

    # Run time plus stop time must equal planned time, or the downtime intervals
    # and the batch record are telling different stories.
    ("downtime reconciles with planned minus run time",
     "SELECT COUNT(*) FROM ("
     "  SELECT b.batch_id,"
     "         b.planned_production_minutes - b.run_time_minutes AS gap,"
     "         COALESCE(SUM(d.duration_minutes), 0) AS stop"
     "  FROM fact_production_batch b"
     "  LEFT JOIN fact_downtime d USING (batch_id)"
     "  GROUP BY b.batch_id, gap"
     ") WHERE ABS(gap - stop) > 0.05"),

    ("run time is positive and within planned time",
     "SELECT COUNT(*) FROM fact_production_batch "
     "WHERE run_time_minutes <= 0 "
     "   OR run_time_minutes > planned_production_minutes + 1e-6"),

    ("no orphan batches",
     "SELECT COUNT(*) FROM fact_production_batch b "
     "LEFT JOIN dim_product p USING (product_id) WHERE p.product_id IS NULL"),

    # Fixed routing means the batch and the product master can never disagree.
    ("batch machine agrees with the routing on dim_product",
     "SELECT COUNT(*) FROM fact_production_batch b "
     "JOIN dim_product p USING (product_id) WHERE b.machine_id != p.machine_id"),

    ("no orphan downtime rows",
     "SELECT COUNT(*) FROM fact_downtime d "
     "LEFT JOIN fact_production_batch b USING (batch_id) WHERE b.batch_id IS NULL"),

    ("no orphan inspections",
     "SELECT COUNT(*) FROM fact_quality_inspection i "
     "LEFT JOIN fact_production_batch b USING (batch_id) WHERE b.batch_id IS NULL"),

    # The plant is closed on Sundays. Anything here means the demand rollover is
    # broken. DuckDB: dayofweek() -> 0 = Sunday.
    ("no production on a Sunday",
     "SELECT COUNT(*) FROM fact_production_batch WHERE dayofweek(production_date) = 0"),

    # -- The pathology must still be present. If a future edit quietly makes the
    # -- layer honest, the data-quality views become a demonstration of nothing.
    ("nothing was genuinely caused by 'Other' (99 is a reporting artefact)",
     "SELECT COUNT(*) FROM fact_downtime "
     "WHERE reported_reason_code = '99' AND true_reason_code = '99'"),

    ("not one micro-stop was ever logged",
     "SELECT COUNT(*) FROM fact_downtime WHERE true_reason_code = '06' AND was_logged"),

    ("dim_product still carries its real demand anchor",
     "SELECT COUNT(*) FROM dim_product WHERE v1_total_units IS NULL OR v1_total_units <= 0"),

    ("27 products, 3 machines",
     "SELECT (SELECT COUNT(*) FROM dim_product) - 27 "
     "     + (SELECT COUNT(*) FROM dim_machine) - 3"),
]

# Checked separately: this one must be ABOVE a threshold, not zero.
MATERIALITY = (
    "the catch-all bucket is material enough to demonstrate something",
    "SELECT SUM(CASE WHEN reported_reason_code = '99' THEN duration_minutes END) "
    "     / SUM(duration_minutes) FROM fact_downtime WHERE was_logged",
    0.15,
)


def run_sql_file(con, path: Path) -> None:
    con.execute(path.read_text())


def main() -> None:
    if DB.exists():
        DB.unlink()          # rebuild from scratch; a fixed seed makes this safe

    con = duckdb.connect(str(DB))
    cfg = yaml.safe_load(CONFIG.read_text())

    print("Building schema and dimensions...")
    run_sql_file(con, SQL / "duckdb_schema.sql")

    products = con.execute("SELECT * FROM dim_product ORDER BY product_id").df()
    machines = con.execute("SELECT * FROM dim_machine ORDER BY machine_id").df()
    demand = con.execute("""
        SELECT product AS product_name, sale_date, SUM(quantity) AS units
        FROM v_sales
        WHERE quantity > 0
          AND product IN (SELECT product_name FROM dim_product)
        GROUP BY product, sale_date
    """).df()

    print(f"  {len(products)} products, {len(machines)} machines, "
          f"{demand.sale_date.nunique()} trading days of real demand")

    print(f"Generating (seed {cfg['run']['random_seed']}, "
          f"factor {cfg['plant']['outlet_equivalent_factor']})...")
    plant_demand = build_plant_demand(demand, cfg)
    batches, downtimes, inspections = generate(cfg, products, machines, plant_demand)

    # Same assertions the BigQuery path runs, before anything is written.
    validate_generation(batches, downtimes, products)

    con.register("b_df", batches)
    con.register("d_df", downtimes)
    con.register("i_df", inspections)
    con.execute("INSERT INTO fact_production_batch SELECT * FROM b_df")
    con.execute("INSERT INTO fact_downtime SELECT * FROM d_df")
    con.execute("INSERT INTO fact_quality_inspection SELECT * FROM i_df")

    print("Creating KPI views...")
    run_sql_file(con, SQL / "duckdb_views.sql")

    print("\nValidating:")
    failed = 0
    for name, sql in CHECKS:
        n = con.execute(sql).fetchone()[0]
        ok = (n == 0)
        failed += (not ok)
        print(f"  {'PASS' if ok else 'FAIL'}  {name}" + ("" if ok else f"  ({n})"))

    name, sql, floor = MATERIALITY
    share = con.execute(sql).fetchone()[0]
    ok = share is not None and share > floor
    failed += (not ok)
    print(f"  {'PASS' if ok else 'FAIL'}  {name}  ({share:.1%})")

    if failed:
        print(f"\n{failed} check(s) FAILED. The layer is not trustworthy.")
        sys.exit(1)

    # -- What the layer actually shows ----------------------------------------
    print("\nAll checks passed.\n")

    print("  Scale:")
    for t in ("fact_production_batch", "fact_downtime", "fact_quality_inspection"):
        n = con.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
        print(f"    {t:<26} {n:>7,}")

    print("\n  What an analyst would see vs what happened:")
    print(con.execute("""
        SELECT reason_code, true_stop_hours, reported_stop_hours,
               true_share, reported_share
        FROM v_dq_reason_coding ORDER BY true_stop_hours DESC
    """).df().to_string(index=False))

    print("\n  Availability, from the operator log vs the machine:")
    print(con.execute("""
        SELECT machine_name, logged_stop_hours, unaccounted_hours,
               availability_from_log, availability_actual
        FROM v_dq_unaccounted_time ORDER BY machine_id
    """).df().to_string(index=False))

    print("\n  The largest bucket in the plant's own downtime report corresponds")
    print("  to nothing that happened. A finding about data quality, not bread.")
    print(f"\n  Written to {DB.name}")
    con.close()


if __name__ == "__main__":
    main()
