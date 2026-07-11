# Synthetic Manufacturing Layer — Scope

*This project has two data layers. The **real layer** is a complete analysis of 232,679 lines of French bakery POS data (Jan 2021 – Sep 2022) — it is live, and it is the only layer that supports business conclusions. The **synthetic layer**, described here, is a simulated manufacturing dataset built alongside it. It is in active development.*

## Why a synthetic layer

Real production data — waste logs, machine downtime, quality inspections — isn't publicly available. A bakery's till tells you what sold; it tells you nothing about what was baked, scrapped, or lost to a broken oven. So to demonstrate production and waste analytics, I generate the plant data that the POS data can't provide.

**This layer demonstrates method. It produces no findings.** Every yield, waste, and OEE figure in it comes from data I fabricated, so it shows how I would model and query a plant — not anything true about a real one. That constraint is architectural, not a disclaimer: the synthetic tables live in a separate BigQuery dataset (`bakery_synthetic`), separate CSVs (`data/synthetic/`), and separate SQL (`sql/synthetic/`). Nothing real is mixed in.

## The core principle: generate events, derive metrics

The generator writes **raw events only** — planned and actual quantities, start times, run times, good and scrapped units, downtime intervals with reasons, inspection outcomes. It never writes a yield percentage, a waste rate, or an OEE number.

Every KPI is derived from those events in SQL. OEE in particular must reconcile from its components — Availability × Performance × Quality — each computed from the underlying facts. If a metric can't be rebuilt from the events, it doesn't belong in the model.

This is what makes the layer worth building. A fabricated dataset with fabricated KPIs proves nothing. A fabricated dataset whose KPIs *derive correctly* proves the modelling.

## What the demand tie is, and isn't

The synthetic plant produces the products the real bakery actually sold, in roughly the volumes it sold them — so the data is plausible rather than arbitrary. **That tie exists to make the simulation believable. It is never the insight.**

If I injected summer seasonality into planned output and then "discovered" summer overproduction, I'd have found nothing but my own assumptions. Any chart that reads like a finding in this layer is mislabelled. Two years of data buys plausibility, not a year-over-year result.

## Data model — five tables

A lean star schema. Two dimensions, three fact tables:

- **`dim_product`** — the 27 manufacturable products. Category, process type, synthetic standard cost, synthetic ideal rate. *Built.*
- **`dim_machine`** — production lines: identity, age, and the availability behaviour that follows from it. *Not yet spec'd.*
- **`fact_production_batch`** — planned and actual quantities, planned vs actual start and run time, good and scrapped units. Drives yield, waste, waste cost, schedule adherence, and the Performance and Quality components of OEE. *Not yet spec'd.*
- **`fact_downtime`** — machine, duration, reason. Drives Availability. *Not yet spec'd.*
- **`fact_quality_inspection`** — batch, pass/fail, defect type. Drives inspection pass rate. *Not yet spec'd.*

An earlier draft of this scope proposed eight tables, including separate `waste_logs` and `production_schedules`. Both were folded in: waste is a scrap column on the batch, and planned-vs-actual is two more columns on the same row. Fewer tables, same analysis, less to explain.

## Product coverage and the manufacturability audit

The synthetic plant makes **27 products** — the top 30 by real units sold, minus three that sell through the till but aren't made on a bakery line:

- **CAFE OU EAU** — a drink. No production rate, no scrap.
- **FORMULE SANDWICH** — a POS meal-deal bundle, not a manufactured item.
- **COUPE** — priced at a flat €0.15 across 20,386 sales and 21 months, with zero price variation, while every genuine product repriced twice. An ancillary charge, not a baked good.

The COUPE exclusion came out of a price-invariance check against the real data (`sql/synthetic/03_audit_product_manufacturability.sql`), not out of reading the name. The remaining 27 all passed.

Those 27 cover **81.5% of real units sold and 69.0% of real revenue** — both figures documented on the table itself.

## KPIs to derive

Production yield %, waste %, waste cost, schedule adherence, machine availability, inspection pass rate, and OEE — each a BigQuery view in `sql/synthetic/`, following the same pattern as the real layer's KPI views.

## Open — not yet decided

Recorded honestly rather than invented:

- Column specs and behavioural rules for the four remaining tables
- Synthetic standard cost and ideal production rate (the two null columns on `dim_product`)
- Whether the synthetic plant runs on the real bakery's opening calendar or its own — a plant and a shop front don't have to share one
- Whether this layer gets its own dashboard pages, and if so, what they'd show

## Working principles

- Generate events; derive every metric. Never fabricate a KPI directly.
- Synthetic stays architecturally separate from real, at every layer.
- Real data informs the *shape* of the simulation, never its *contents*.
- Anything run against BigQuery gets committed to `sql/`. If the repo can't reproduce it, it isn't reproducible.
- Seeded RNG throughout.
