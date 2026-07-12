# The Synthetic Production Layer — Scope

## Read this first

**This layer produces no findings, by construction.**

I wrote the data. Every pattern in it is an assumption from `config/synthetic_generator.yaml`, read back at me. If I injected summer seasonality and then "discovered" summer overproduction, I would have found nothing but my own arithmetic.

What it demonstrates is narrower and, I think, more honest: that I can design an MES-style production data model, derive OEE correctly from raw events, and — the part that matters — recognise the ways real production data lies before trusting a single number that comes out of it.

The real analysis in this project is in the POS layer. That's where the findings are, and that's the work I'd defend.

---

## Why the layer exists at all

Bakery till data has no production in it. No batches, no downtime, no scrap, no yield. So the real layer, however good, cannot show that I can model a manufacturing process — the data simply doesn't contain one.

This layer closes exactly that gap and nothing more.

| | |
|---|---|
| **What it proves** | I can build a production data model and derive OEE that reconciles |
| **What it does not prove** | That I can analyse a plant. For that, give me a plant's data. |

The distinction matters. Being able to build the instrument is not the same as being able to read it, and only the second one is the job. I'd rather say so than let a reader assume otherwise.

---

## What's real and what isn't

| | Source |
|---|---|
| Product list, product mix, daily demand shape, seasonality | **Real** — the POS layer |
| Median selling price per product | **Real** — the POS layer |
| Bake times, oven load densities, handling allowances | **Remembered** — nine years in industrial food production, including production-oven work |
| The plant itself: deck count, rack size, machine ages, failure rates | **Declared** — no equipment data exists in the source dataset |
| Cost ratios, scrap rates, downtime rates, miscoding rates | **Fabricated** — declared in the config |
| Every batch, stop and inspection | **Generated** |

The only real value carried into the synthetic tables is `dim_product.v1_total_units`, the reference outlet demand. Real data informs the *shape* of the simulation, never its contents.

Full detail: [`synthetic_layer_assumptions.md`](synthetic_layer_assumptions.md).

---

## The design rule the whole layer rests on

**The generator writes raw events only.**

Planned and actual quantities. Start times. Run times. Good and scrap units. Downtime intervals. Inspection outcomes.

It never writes a yield percentage, a waste rate, or an OEE number. Not one. Every KPI derives in SQL, and OEE must reconcile from Availability × Performance × Quality — asserted at batch grain *and* after aggregation, because naive rollups break once products have different rates.

If a metric could be stored in the schema, it isn't. That's the point. A generator that writes its own KPIs proves nothing except that it can write numbers.

---

## The thing this layer is actually for

Real production data is systematically wrong in specific, knowable ways. The generator reproduces two of them on purpose, and the data-quality views measure the damage.

### 1. The catch-all reason code

The terminal offers a list of downtime reasons. "Other" is the fastest button. An operator with dough on their hands picks the quickest option, not the accurate one — and short stops get miscoded far more often than long ones.

### 2. Micro-stops nobody logs

A tray catches. A door needs reseating. Someone opens a damper. Thirty seconds to two minutes, constantly, and not one of them ever reaches a terminal. They don't appear in any downtime report, anywhere.

### What that does to the numbers

| Reason code | True share of lost time | As reported |
|---|---|---|
| **01 — Changeover** | **77.5%** | 53.1% |
| **06 — Micro-stops** | **15.8%** | **0.0%** |
| 02 — Mechanical | 3.2% | 3.3% |
| 03 — Process / materials | 2.2% | 2.4% |
| 04 — Personnel | 0.7% | 0.6% |
| 05 — Quality stop | 0.7% | 0.6% |
| **99 — "Other"** | **0.0%** | **40.0%** |

Read the first and last rows together. The **largest single bucket in the plant's own downtime report corresponds to nothing that ever happened**, and the second-largest true cause of lost time is *completely invisible* — 168 hours of it, not one minute recorded.

A maintenance team prioritising off that Pareto would work on the wrong thing, and would never learn that the biggest thing existed.

### And what it does to Availability

| Machine | Availability from the operator log | Actual |
|---|---|---|
| Deck Oven Line | 0.817 | 0.780 |
| Rack Oven Line | **0.757** | **0.534** |

The rack oven reads twenty-two points better than it is. Not because anyone lied — because the stops that went unrecorded are, by definition, invisible.

The asymmetry between the two ovens is mechanistic, not arbitrary: the rack runs short batches, so short unlogged stops eat a larger fraction of each one. It falls out of the model rather than being asserted.

`v_dq_unaccounted_time` is the check that catches this, and it's a check a real analyst **can** run in a real plant — machine counters against the operator log. `v_dq_reason_coding` is not: in a real plant there is only one reason code and no record of what it should have been. That view exists here *only* because the data is synthetic, which is precisely what lets the distortion be measured instead of asserted.

**This is a finding about data quality, not about bread.** It breaks no rule. Distrust the data first.

---

## Limitations, stated rather than discovered

**Fixed routing makes machine collinear with product family.** Bread is always on the old deck oven, viennoiserie always on the newer rack. A downtime pattern on the deck line cannot be distinguished from a downtime pattern on bread. Harmless here, because no findings are claimed — but real, and stated.

**The rack oven's low Availability is a consequence of my parameters, not a discovery.** It runs ten products in small batches with a changeover between each, and the changeover is sometimes longer than the run. That's a genuine phenomenon in a many-SKU line — but I chose the batch sizes and the changeover durations, so it is arithmetic on my own assumptions.

**Actual times equal scheduled times.** A batch occupies its planned window and downtime is consumed inside it, rather than pushing everything downstream late. In a live plant a breakdown shifts the whole schedule. OEE is unaffected — Availability compares run time to planned time, both intact — but `actual_start_ts` and `actual_end_ts` carry no information they didn't already have.

**Scrap is valued at full standard cost regardless of when it was rejected.** A real plant charges scrap at the cost accumulated to the point of rejection: dough dumped at proofing is cheap, a loaf pulled after the bake carries the full oven. This schema has one stage and cannot make that distinction.

**Finishing and labour stations are not modelled.** `ideal_units_per_hr` is bake-cell capacity. Hand-finished products therefore show lower Performance against an oven-based standard.

**No capacity-violation logic.** The scale factor was set from a capacity check, so the plant can bake its own demand. On peak days the shift runs long. I did not build spill-over logic, because a capacity violation here would be arithmetic on assumptions I chose — not a finding, and not worth the machinery.

---

## Reproducing it

Fixed seed. Same inputs, same output, every time. Anything run against BigQuery is in the repo — if it can't be reproduced, it isn't reproducible.

```bash
gcloud auth application-default login

# 1. dimensions
#    sql/synthetic/05_create_dim_machine.sql
#    sql/synthetic/06_author_product_standards.sql
# 2. empty fact tables
#    sql/synthetic/07_create_fact_tables.sql

# 3. generate and load
python scripts/generate_synthetic_production.py
python scripts/load_synthetic_to_bigquery.py

# 4. KPI views, then validate
#    sql/synthetic/08_create_kpi_views.sql
#    sql/synthetic/09_validate_synthetic_layer.sql
```

`09` is fifteen assertions and it fails loudly. It checks that OEE reconciles from A × P × Q, that Performance never exceeds 100%, that run time plus stop time equals planned time, that referential integrity holds, that nothing was produced on a Sunday — and that the pathology is still present, so a future edit can't quietly make the layer honest and turn the data-quality views into a demonstration of nothing.

**Scale:** 8,770 batches, 16,029 downtime events, 2,166 inspections, across 21 months of real demand.
