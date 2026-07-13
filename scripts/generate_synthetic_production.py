#!/usr/bin/env python3
"""
generate_synthetic_production.py
Synthetic manufacturing layer — event generator.

WHAT THIS DOES
    Reads the config, reads dim_product and dim_machine from BigQuery, reads the
    real daily demand series from the POS layer, and walks every production day
    writing RAW EVENTS to three CSVs.

WHAT THIS NEVER DOES
    It never writes a yield %, a waste rate, or an OEE number. Those derive in
    SQL. If a metric could be computed here, it isn't — that is the point.

NO FINDINGS
    Every pattern in the output is an assumption in the config, read back. This
    layer demonstrates that a production data model can be built and that OEE can
    be derived correctly from raw events. It is not a discovery about bakeries.

    See docs/synthetic_layer_assumptions.md.

USAGE
    gcloud auth application-default login
    python scripts/generate_synthetic_production.py
"""

from __future__ import annotations

import hashlib
import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd
import yaml

# NOTE: google-cloud-bigquery is imported LAZILY, inside main(). The generator's
# logic has no cloud dependency, and scripts/build_duckdb.py imports generate()
# and validate() directly to run the whole pipeline locally. Importing BigQuery
# at module level would force every user to install a cloud SDK they may never
# call — which would defeat the point of the DuckDB path.

PROJECT = "bakery-analytics-501220"
LOCATION = "EU"
ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "config" / "synthetic_generator.yaml"
OUT_DIR = ROOT / "data" / "synthetic"


# --- Load inputs ---

def load_config() -> dict:
    with open(CONFIG_PATH) as f:
        return yaml.safe_load(f)


def load_dimensions(client) -> tuple[pd.DataFrame, pd.DataFrame]:
    """dim_product and dim_machine. The generator holds NO hardcoded product or
    equipment data — everything comes from the dimensions, so the two cannot
    drift apart."""
    products = client.query("""
        SELECT product_id, product_name, product_category, process_type,
               machine_id, units_per_full_load, bake_minutes,
               unit_cost_eur, ideal_units_per_hr
        FROM `bakery_synthetic.dim_product`
        ORDER BY product_id
    """).to_dataframe()

    machines = client.query("""
        SELECT machine_id, machine_name, machine_type,
               handling_minutes, base_failure_rate_per_hr
        FROM `bakery_synthetic.dim_machine`
        ORDER BY machine_id
    """).to_dataframe()

    return products, machines


def load_real_demand(client, products: pd.DataFrame) -> pd.DataFrame:
    """The real daily demand series, one row per product per trading day.

    Seasonality is NOT modelled. It is inherited. Fitting a sine wave to demand
    would smooth away exactly the noise — local holidays, odd weeks, weather —
    that makes a real production plan fail. And injecting a seasonal curve, then
    'finding' seasonality in the output, would be finding nothing but my own
    assumption.
    """
    names = "', '".join(products["product_name"].tolist())
    return client.query(f"""
        SELECT
          product AS product_name,
          sale_date,
          SUM(quantity) AS units
        FROM `bakery.v_sales`
        WHERE quantity > 0
          AND product IN ('{names}')
        GROUP BY product, sale_date
        ORDER BY sale_date, product
    """).to_dataframe()


# --- Demand -> plant demand ---

def build_plant_demand(demand: pd.DataFrame, cfg: dict) -> pd.DataFrame:
    """Turn one shop's sales into the plant's daily production requirement.

    Two transformations, both declared:

    1. SCALE. The plant supplies several outlets; the real series is one of
       them. Demand is multiplied BEFORE planning, never by inflating generated
       data afterwards. The MIX and the SEASONALITY stay real; only the SCALE is
       fabricated.

    2. SUNDAY ROLLS INTO SATURDAY. The plant runs Mon-Sat. Sunday is the shop's
       biggest day, and a bakery bakes for it on Saturday — which is exactly why
       Saturday is a monster shift in a real bakery. No demand is invented and
       none is thrown away.

    Wednesdays where the shop was closed simply carry little or no demand. The
    plant is AVAILABLE Mon-Sat; it produces when there is something to produce.
    A light Wednesday is an honest consequence of the real data, not a defect.
    """
    n = cfg["plant"]["outlet_equivalent_factor"]
    d = demand.copy()
    d["sale_date"] = pd.to_datetime(d["sale_date"])
    d["units"] = d["units"] * n

    # weekday(): Monday=0 ... Sunday=6
    is_sunday = d["sale_date"].dt.weekday == 6
    d.loc[is_sunday, "sale_date"] = d.loc[is_sunday, "sale_date"] - pd.Timedelta(days=1)

    d = (d.groupby(["product_name", "sale_date"], as_index=False)["units"]
           .sum()
           .rename(columns={"sale_date": "production_date"}))

    # Anything left on a Sunday would be a bug in the rollover above.
    assert (d["production_date"].dt.weekday != 6).all(), "Sunday demand survived the rollover"
    return d


# --- Batch construction ---

@dataclass
class Reasons:
    """Downtime reason codes.

    Changeover (01) is deterministic — one per product switch — so it isn't in the
    random-failure draw. Codes 02-05 are, with weights renormalised.

    Code 01 is the changeover between products: cleaning down, moving the oven
    temperature, swapping formats. It is NOT the routine load/unload handling,
    which already sits inside the cycle time behind the ideal rate. Logging that
    as downtime too would penalise it twice — once in Performance, once in
    Availability.
    """
    codes: list[str]
    labels: dict[str, str]
    weights: np.ndarray          # over failure codes only (02-05)
    failure_codes: list[str]
    durations: dict[str, dict]

    @classmethod
    def from_config(cls, cfg: dict) -> "Reasons":
        rc = cfg["downtime"]["reason_codes"]
        labels = {k: v["label"] for k, v in rc.items()}

        # The micro-stop code is NOT in the failure draw. It has its own process
        # and its own code, so it never gets sampled as an ordinary breakdown.
        micro = cfg["downtime"].get("micro_stops", {})
        if micro.get("enabled"):
            labels[micro["true_reason_code"]] = micro["true_reason_label"]

        # 01 is deterministic (one per product switch), so it's never drawn.
        # Everything else is, including 98 — some stops genuinely don't fit the
        # taxonomy, and a model where nothing is ever truly "Other" is the
        # fantasy, not the pathology.
        failure_codes = [k for k in rc if k != "01"]
        w = np.array([rc[k]["weight"] for k in failure_codes], dtype=float)
        return cls(
            codes=list(rc),
            labels=labels,
            weights=w / w.sum(),
            failure_codes=failure_codes,
            durations={k: v["duration_minutes"] for k, v in rc.items()},
        )


def draw_truncated(rng, spec: dict) -> float:
    """Normal draw, clipped to the configured range. Clipping rather than
    resampling keeps the seed reproducible and the tails honest."""
    return float(np.clip(rng.normal(spec["mean"], spec["std"]), spec["min"], spec["max"]))


def batch_id(date, product_id: int, seq: int) -> str:
    raw = f"{date:%Y%m%d}-{product_id}-{seq}"
    return "B" + hashlib.md5(raw.encode()).hexdigest()[:12]


# --- The generator ---

def generate(cfg: dict, products: pd.DataFrame, machines: pd.DataFrame,
             plant_demand: pd.DataFrame):

    rng = np.random.default_rng(cfg["run"]["random_seed"])
    reasons = Reasons.from_config(cfg)

    mach = machines.set_index("machine_id").to_dict("index")
    prod = products.set_index("product_name").to_dict("index")

    mis = cfg["downtime"]["miscoding"]
    unlogged_below = cfg["downtime"]["unlogged_below_minutes"]
    rounding = cfg["downtime"].get("operator_rounding", {})
    per_stop_penalty = cfg["scrap"].get("per_stop_penalty", 0.0)
    perf_spec = cfg["performance"]["achieved_rate_fraction"]
    scrap_spec = cfg["scrap"]["base_rate"]
    scrap_mult = cfg["scrap"]["category_multiplier"]
    insp_rate = cfg["quality"]["inspection_rate"]
    fail_thresh = cfg["quality"]["fail_threshold_scrap_rate"]

    # The planner does not schedule at the ideal rate — nobody does. A standard
    # rate carries an efficiency allowance, because a line that never breaks and
    # never slows does not exist. Schedule at ideal and every batch would appear
    # to overrun before a single thing went wrong.
    planning_efficiency = 0.85

    shift_start = cfg["plant"]["shift_start"]

    batches, downtimes, inspections = [], [], []

    # Sub-full-load demand accumulates rather than firing an oven for four
    # croissants. Low-volume products therefore run every few days, which is how
    # a real bakery schedules them.
    carry: dict[str, float] = {}

    for date, day in plant_demand.groupby("production_date"):
        day = day.copy()
        day["units"] = day["units"] + day["product_name"].map(carry).fillna(0)

        # Volume descending. Not an optimiser — this is plausible history, not a
        # scheduling problem. The volume driver leads and the specialty items
        # follow, which is how a shift actually runs.
        # Sort on product_name as a tiebreaker, and use a STABLE sort.
        #
        # pandas defaults to quicksort, which isn't stable — so when two products
        # have identical demand, the order is arbitrary. numpy's sort is
        # SIMD-accelerated and breaks those ties differently on ARM than on x86,
        # which meant this pipeline produced different output on a Mac than on a
        # Linux CI runner. Same seed, same code, different numbers.
        #
        # CI caught it. Nothing else had, including me.
        day = day.sort_values(
            ["units", "product_name"], ascending=[False, True], kind="stable"
        )

        # Each machine has its own clock. Deck, rack and bench run in parallel.
        elapsed = {m: 0.0 for m in mach}
        last_product = {m: None for m in mach}
        seq = 0

        for _, row in day.iterrows():
            name = row["product_name"]
            p = prod[name]
            mid = int(p["machine_id"])
            m = mach[mid]

            units = float(row["units"])
            baked = p["process_type"] == "baked"

            if baked:
                full_load = int(p["units_per_full_load"])
                # One deck (of 3) or one tray (of 18) is the smallest sensible
                # firing. Below that, hold the demand for another day.
                divisor = 3 if m["machine_type"] == "deck_oven" else 18
                min_units = full_load / divisor
                if units < min_units:
                    carry[name] = units
                    continue
                loads_used = units / full_load
                cycle = float(p["bake_minutes"]) + float(m["handling_minutes"])
            else:
                loads_used = 0.0          # the bench has no oven load model
                cycle = 0.0

            carry[name] = 0.0
            planned_units = int(round(units))
            if planned_units <= 0:
                continue

            ideal_rate = float(p["ideal_units_per_hr"])
            ideal_minutes = planned_units / ideal_rate * 60.0
            planned_minutes = ideal_minutes / planning_efficiency

            seq += 1
            bid = batch_id(date, int(p["product_id"]), seq)

            # Changeover on every product switch.
            batch_downtime = []
            if last_product[mid] is not None and last_product[mid] != name:
                dur = draw_truncated(rng, reasons.durations["01"])
                batch_downtime.append(("01", dur))
            last_product[mid] = name

            # Unplanned breakdowns: Poisson on the machine's base failure rate.
            # The 2012 deck oven breaks more often than the 2019 rack. Note this
            # is NOT what drives the Availability gap in the output — changeover
            # frequency is, and by a long way.
            lam = float(m["base_failure_rate_per_hr"]) * (planned_minutes / 60.0)
            for _ in range(rng.poisson(lam)):
                code = rng.choice(reasons.failure_codes, p=reasons.weights)
                dur = draw_truncated(rng, reasons.durations[code])
                batch_downtime.append((str(code), dur))

            # Micro-stops: a tray catches, a door needs reseating. Thirty seconds
            # to two minutes, constantly, and nobody enters them on the terminal.
            # Their own process — the failure draws above can't produce a stop this
            # short, so without this the "unlogged" mechanism would be dead code.
            micro = cfg["downtime"].get("micro_stops", {})
            if micro.get("enabled"):
                n_micro = rng.poisson(micro["rate_per_hour"] * (planned_minutes / 60.0))
                for _ in range(n_micro):
                    dur = draw_truncated(rng, micro["duration_minutes"])
                    batch_downtime.append((micro["true_reason_code"], dur))

            total_stop = sum(d for _, d in batch_downtime)

            # GUARDRAIL, NOT A MODEL. A batch cannot spend most of its window
            # broken. This exists so the draws can never produce a negative run
            # time — it is not supposed to shape the output. Set high on purpose:
            # if this cap ever binds often enough to matter, the failure and
            # micro-stop rates are wrong and should be fixed there, not clipped
            # here.
            cap = 0.85 * planned_minutes
            if total_stop > cap and total_stop > 0:
                k = cap / total_stop
                batch_downtime = [(c, d * k) for c, d in batch_downtime]
                total_stop = cap

            run_minutes = planned_minutes - total_stop

            achieved = draw_truncated(rng, perf_spec)   # < 1.0 by config

            # Floor, not round. Rounding up a small batch pushes output above what
            # the run time could theoretically produce and Performance breaks
            # 100%. You can't bake nine tenths of a baguette.
            total_units = int(math.floor(run_minutes / 60.0 * ideal_rate * achieved))
            if total_units < 1:
                continue

            # A stop doesn't just cost time — the oven cools, the proof runs on,
            # and the first units after a restart come out wrong. Downtime and
            # scrap co-move in a plant; modelling them independently is a
            # white-collar mistake.
            n_stops = sum(1 for _, d in batch_downtime if d >= unlogged_below)
            sr = draw_truncated(rng, scrap_spec) * scrap_mult[p["product_category"]]
            sr += n_stops * per_stop_penalty
            sr = min(sr, 0.30)
            scrap_units = int(round(total_units * sr))
            good_units = total_units - scrap_units

            start = pd.Timestamp(f"{date:%Y-%m-%d} {shift_start}") + pd.Timedelta(minutes=elapsed[mid])
            end = start + pd.Timedelta(minutes=planned_minutes)

            batches.append(dict(
                batch_id=bid,
                production_date=date.date(),
                product_id=int(p["product_id"]),
                machine_id=mid,
                planned_units=planned_units,
                loads_used=round(loads_used, 4),
                scheduled_start_ts=start,
                scheduled_end_ts=end,
                planned_production_minutes=round(planned_minutes, 2),
                actual_start_ts=start,
                actual_end_ts=end,
                run_time_minutes=round(run_minutes, 2),
                good_units=good_units,
                scrap_units=scrap_units,
            ))

            # Shuffle so micro-stops interleave with the larger stops rather than
            # all landing at the end of the batch.
            batch_downtime = [batch_downtime[i]
                              for i in rng.permutation(len(batch_downtime))]
            offset = 0.0
            for i, (true_code, dur) in enumerate(batch_downtime):
                ds = start + pd.Timedelta(minutes=offset)
                offset += dur
                de = ds + pd.Timedelta(minutes=dur)

                # Below the threshold, the stop never reaches the terminal.
                # Nobody fills in a form for a two-minute stop.
                was_logged = dur >= unlogged_below

                # Short stops get miscoded to "Other" far more often than long
                # ones — fastest button, and the operator has dough on their hands.
                if dur < 10:
                    p_mis = mis["probability_by_duration"]["under_10_min"]
                elif dur < 30:
                    p_mis = mis["probability_by_duration"]["under_30_min"]
                else:
                    p_mis = mis["probability_by_duration"]["over_30_min"]

                if true_code == "98":
                    # Genuinely uncategorised. The operator presses Other because
                    # Other is the honest answer. This is why an analyst can't
                    # just subtract the catch-all bucket: some of it is real.
                    rep_code, rep_label = mis["catchall_code"], mis["catchall_label"]
                elif mis["enabled"] and was_logged and rng.random() < p_mis:
                    rep_code, rep_label = mis["catchall_code"], mis["catchall_label"]
                else:
                    rep_code, rep_label = true_code, reasons.labels[true_code]

                # Operators type round numbers. A logged duration of 11.97
                # minutes is the fastest possible tell that data is generated —
                # real MES exports heap hard on 5, 10, 15, 30. The machine knows
                # the exact figure; the form doesn't.
                rep_dur = dur
                if was_logged and rounding.get("enabled") \
                        and rng.random() < rounding["probability"]:
                    step = rounding["to_nearest_minutes"]
                    rep_dur = max(step, round(dur / step) * step)

                downtimes.append(dict(
                    downtime_id=f"D{bid[1:]}-{i}",
                    batch_id=bid,
                    machine_id=mid,
                    production_date=date.date(),
                    start_ts=ds,
                    end_ts=de,
                    duration_minutes=round(dur, 2),
                    reported_duration_minutes=round(rep_dur, 2),
                    reported_reason_code=rep_code,
                    reported_reason_label=rep_label,
                    true_reason_code=true_code,
                    true_reason_label=reasons.labels[true_code],
                    was_logged=bool(was_logged),
                ))

            # Sampled inspection, not census.
            if rng.random() < insp_rate:
                sample = min(50, max(5, total_units // 20))
                defects = int(rng.binomial(sample, min(sr, 0.5)))
                failed = sr > fail_thresh
                inspections.append(dict(
                    inspection_id=f"I{bid[1:]}",
                    batch_id=bid,
                    production_date=date.date(),
                    inspection_ts=end,
                    sample_size=sample,
                    defects_found=defects,
                    outcome="FAIL" if failed else "PASS",
                    defect_type=(rng.choice(["underweight", "misshapen", "colour", "underproofed"])
                                 if failed else None),
                ))

            elapsed[mid] += planned_minutes

    return (pd.DataFrame(batches),
            pd.DataFrame(downtimes),
            pd.DataFrame(inspections))


# ---------------------------------------------------------------------------
# Checks that run before anything is written. These can fail; the Performance one
# did, during the build.
# ---------------------------------------------------------------------------

def validate(batches: pd.DataFrame, downtimes: pd.DataFrame, products: pd.DataFrame):
    p = products.set_index("product_id")["ideal_units_per_hr"]

    total = batches["good_units"] + batches["scrap_units"]
    hours = batches["run_time_minutes"] / 60.0
    perf = (total / hours) / batches["product_id"].map(p)

    # A plant can't produce faster than its own theoretical maximum. This caught a
    # real bug during the build: rounding up small batches.
    assert perf.max() <= 1.0, f"Performance exceeded 1.0 (max {perf.max():.4f})"

    assert (batches["run_time_minutes"] > 0).all(), "non-positive run time"
    assert (batches["run_time_minutes"] <= batches["planned_production_minutes"] + 1e-6).all(), \
        "run time exceeds planned production time"
    assert (batches["scrap_units"] >= 0).all()
    assert (batches["good_units"] > 0).all()

    # Downtime must reconcile with the gap between planned and run time.
    stop = downtimes.groupby("batch_id")["duration_minutes"].sum()
    gap = (batches.set_index("batch_id")["planned_production_minutes"]
           - batches.set_index("batch_id")["run_time_minutes"])
    joined = gap.to_frame("gap").join(stop.rename("stop")).fillna(0)
    assert (joined["gap"] - joined["stop"]).abs().max() < 0.05, \
        "downtime intervals do not reconcile with planned minus run time"

    print(f"  Performance max : {perf.max():.4f}  (must be <= 1.0)")
    print(f"  Performance mean: {perf.mean():.4f}")


# =============================================================================

def main():
    from google.cloud import bigquery      # lazy: only the BigQuery path needs it

    cfg = load_config()
    client = bigquery.Client(project=PROJECT, location=LOCATION)

    print("Reading dimensions and real demand...")
    products, machines = load_dimensions(client)
    demand = load_real_demand(client, products)
    plant_demand = build_plant_demand(demand, cfg)

    print(f"Generating (seed {cfg['run']['random_seed']}, "
          f"factor {cfg['plant']['outlet_equivalent_factor']})...")
    batches, downtimes, inspections = generate(cfg, products, machines, plant_demand)

    print("Validating...")
    validate(batches, downtimes, products)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    batches.to_csv(OUT_DIR / "fact_production_batch.csv", index=False)
    downtimes.to_csv(OUT_DIR / "fact_downtime.csv", index=False)
    inspections.to_csv(OUT_DIR / "fact_quality_inspection.csv", index=False)

    logged = downtimes["was_logged"].mean()
    other = (downtimes.loc[downtimes["was_logged"], "reported_reason_code"] == "99").mean()

    print(f"\n  batches      {len(batches):>7,}")
    print(f"  downtime     {len(downtimes):>7,}   ({logged:.1%} logged, "
          f"{1-logged:.1%} unlogged micro-stops)")
    print(f"  inspections  {len(inspections):>7,}")
    print(f"\n  Of the downtime an analyst would actually see, {other:.1%} is coded 'Other'.")
    print("  That is the pathology. It is a finding about data quality, not about bread.")
    print(f"\n  Written to {OUT_DIR}")


if __name__ == "__main__":
    main()
