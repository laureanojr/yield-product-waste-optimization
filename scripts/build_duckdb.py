#!/usr/bin/env python3
"""
Builds the whole project into bakery.duckdb.

    pip install -r requirements.txt
    python scripts/build_duckdb.py

Real layer -> dimensions -> generate synthetic events -> KPI views -> checks.

Built on BigQuery originally (sql/synthetic/); ported to DuckDB so the repo can
be run without a cloud account. The generator logic is imported unchanged, so
both engines produce identical output from the same seed.
"""

from __future__ import annotations

import sys
from pathlib import Path

import duckdb
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


# Arithmetic identities. These CANNOT fail — A x P x Q reduces to OEE by
# construction, since run_hours and earned_hours cancel. They're here to catch a
# typo in the view definitions, nothing more. Do not mistake them for evidence
# that the OEE methodology is right; that's a modelling question, not a SQL one.
IDENTITIES = [
    ("A x P x Q reduces to OEE (batch grain)",
     "SELECT COUNT(*) FROM v_batch_oee "
     "WHERE ABS(availability * performance * quality - oee) > 1e-6"),

    ("A x P x Q reduces to OEE (aggregated)",
     "SELECT COUNT(*) FROM v_oee_daily "
     "WHERE ABS(availability * performance * quality - oee) > 1e-3"),
]

# Checks that can actually fail, and have.
CHECKS = [
    # This one caught a real bug: rounding UP a small batch put output above the
    # theoretical ceiling and Performance went over 100%. Fixed by flooring.
    ("Performance never exceeds 1.0",
     "SELECT COUNT(*) FROM v_batch_oee WHERE performance > 1.0"),

    ("every OEE term is inside (0, 1]",
     "SELECT COUNT(*) FROM v_batch_oee WHERE availability > 1.0 OR quality > 1.0 "
     "OR availability <= 0 OR quality <= 0 OR performance <= 0"),

    ("run time + stop time = planned time",
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

    # Routing is fixed, so these can never legitimately disagree.
    ("batch machine matches the routing on dim_product",
     "SELECT COUNT(*) FROM fact_production_batch b "
     "JOIN dim_product p USING (product_id) WHERE b.machine_id != p.machine_id"),

    ("no orphan downtime rows",
     "SELECT COUNT(*) FROM fact_downtime d "
     "LEFT JOIN fact_production_batch b USING (batch_id) WHERE b.batch_id IS NULL"),

    ("no orphan inspections",
     "SELECT COUNT(*) FROM fact_quality_inspection i "
     "LEFT JOIN fact_production_batch b USING (batch_id) WHERE b.batch_id IS NULL"),

    # Plant is closed Sundays. Anything here means the demand rollover broke.
    ("no production on a Sunday",
     "SELECT COUNT(*) FROM fact_production_batch WHERE dayofweek(production_date) = 0"),

    ("27 products, 3 machines",
     "SELECT (SELECT COUNT(*) FROM dim_product) - 27 "
     "     + (SELECT COUNT(*) FROM dim_machine) - 3"),

    ("dim_product still has its real demand anchor",
     "SELECT COUNT(*) FROM dim_product WHERE v1_total_units IS NULL OR v1_total_units <= 0"),
]

# Not data checks — these confirm the generator's deliberate distortions are
# still being injected. If someone removes them, the data-quality views quietly
# become a demonstration of nothing, and these are what tells you.
GENERATOR_CONTRACT = [
    ("code 99 is only ever a reporting artefact, never a true cause",
     "SELECT COUNT(*) FROM fact_downtime "
     "WHERE reported_reason_code = '99' AND true_reason_code = '99'"),

    ("no micro-stop was ever logged",
     "SELECT COUNT(*) FROM fact_downtime WHERE true_reason_code = '06' AND was_logged"),
]


def main() -> None:
    if DB.exists():
        DB.unlink()          # fixed seed makes a clean rebuild safe

    con = duckdb.connect(str(DB))
    cfg = yaml.safe_load(CONFIG.read_text())

    print("Building schema and dimensions...")
    con.execute((SQL / "duckdb_schema.sql").read_text())

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
          f"{demand.sale_date.nunique()} trading days")

    print(f"Generating (seed {cfg['run']['random_seed']}, "
          f"factor {cfg['plant']['outlet_equivalent_factor']})...")
    plant_demand = build_plant_demand(demand, cfg)
    batches, downtimes, inspections = generate(cfg, products, machines, plant_demand)
    validate_generation(batches, downtimes, products)

    con.register("b_df", batches)
    con.register("d_df", downtimes)
    con.register("i_df", inspections)
    con.execute("INSERT INTO fact_production_batch SELECT * FROM b_df")
    con.execute("INSERT INTO fact_downtime SELECT * FROM d_df")
    con.execute("INSERT INTO fact_quality_inspection SELECT * FROM i_df")

    print("Creating KPI views...")
    con.execute((SQL / "duckdb_views.sql").read_text())

    failed = 0

    def run(group: str, items: list[tuple[str, str]]) -> None:
        nonlocal failed
        print(f"\n{group}")
        for name, sql in items:
            n = con.execute(sql).fetchone()[0]
            ok = (n == 0)
            failed += (not ok)
            print(f"  {'ok  ' if ok else 'FAIL'} {name}" + ("" if ok else f"  ({n})"))

    run("Arithmetic identities (cannot fail; typo guard only):", IDENTITIES)
    run("Data checks:", CHECKS)
    run("Generator contract (the deliberate distortions are still there):",
        GENERATOR_CONTRACT)

    if failed:
        print(f"\n{failed} check(s) failed.")
        sys.exit(1)

    print("\n--- Scale ---")
    for t in ("fact_production_batch", "fact_downtime", "fact_quality_inspection"):
        n = con.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
        print(f"  {t:<26} {n:>7,}")

    print("\n--- Downtime: what the operator log says vs what happened ---")
    print(con.execute("""
        SELECT reason_code, true_stop_hours, reported_stop_hours,
               true_share, reported_share
        FROM v_dq_reason_coding ORDER BY true_stop_hours DESC
    """).df().to_string(index=False))

    print("\n--- Availability: operator log vs machine counter ---")
    print(con.execute("""
        SELECT machine_name, logged_stop_hours, unaccounted_hours,
               availability_from_log, availability_actual
        FROM v_dq_unaccounted_time ORDER BY machine_id
    """).df().to_string(index=False))

    print(f"\nWritten to {DB.name}")
    con.close()


if __name__ == "__main__":
    main()
