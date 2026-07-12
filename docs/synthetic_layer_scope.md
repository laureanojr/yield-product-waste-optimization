# The Synthetic Production Layer

## What this is

Bakery till data has no production in it — no batches, no downtime, no scrap, no yield. So the real layer, however good, can't show that I can model a manufacturing process. The data doesn't contain one.

This layer closes that gap. It's an MES-style star schema with a generator that writes raw production events, and SQL that derives yield, scrap cost and OEE from them.

**It produces no findings.** I wrote the data. Every pattern in it is a parameter in `config/synthetic_generator.yaml`, read back. The real analysis is in the POS layer.

What it proves: I can design a production data model and derive the standard metrics correctly.
What it doesn't prove: that I can analyse a plant. For that you'd need to give me a plant's data.

## What's real and what isn't

| | |
|---|---|
| Product list, demand mix, daily series, seasonality | Real — the POS layer |
| Median selling price per product | Real |
| Bake times | From experience — nine years in industrial food production |
| The plant: deck count, rack size, machine ages, failure rates | Assumed. No equipment data exists in the source. |
| Cost ratios, scrap rates, downtime rates, miscoding rates | Fabricated. All in the config. |
| Every batch, stop and inspection | Generated |

The only real value carried into the synthetic tables is `dim_product.v1_total_units`.

Full detail: [`synthetic_layer_assumptions.md`](synthetic_layer_assumptions.md).

## The design rule

The generator writes raw events only — quantities, times, good and scrap units, downtime intervals, inspection outcomes. It never writes a yield %, a waste rate or an OEE number. Everything derives in SQL.

A generator that writes its own KPIs proves only that it can write numbers.

## What it's actually for

Real production data is wrong in specific ways, and the generator reproduces two of them on purpose.

**Reason codes get miscoded.** The terminal has a list of causes; "Other" is the fastest button; an operator with dough on their hands picks the quickest option, not the accurate one. Short stops get miscoded far more than long ones.

**Micro-stops never get logged.** A tray catches, a door needs reseating. Thirty seconds to two minutes, constantly, and none of them reach a terminal.

The result:

**Operators type round numbers.** Real downtime logs heap hard on 5, 10, 15, 30 minutes — nobody enters "11.97". So the machine counter and the operator's form disagree on *duration* as well as on cause. Three quarters of the logged durations here land on a multiple of 5; on the machine counter, well under 1% do.

| Reason code | True share of lost time | As reported |
|---|---|---|
| 01 — Changeover | 77.9% | 52.1% |
| 06 — Micro-stops | 15.5% | **0.0%** |
| 02 — Mechanical | 3.1% | 3.4% |
| 03 — Process / materials | 1.8% | 1.6% |
| 04 — Personnel | 0.8% | 0.8% |
| 05 — Quality stop | 0.5% | 0.5% |
| 98 — Genuinely uncategorised | 0.4% | — |
| 99 — "Other" (the button) | — | **41.6%** |

The largest bucket in the plant's downtime report is a button, not a cause. The second-largest true cause of lost time is invisible.

Note code 98. **Some stops are genuinely uncategorised** — novel failures, incomplete investigations, causes nobody got to the bottom of. They report as "Other" because Other is the honest answer. So the catch-all is part real and part miscoding, and an analyst can't simply subtract it. A plant where nothing is ever truly Other would be the fantasy, not the pathology.

`v_downtime_pareto` reads the same reported codes and durations, so the damage is real inside the project, not just illustrative.

**Two things to be clear about.**

`v_dq_reason_coding` can't be built in a real plant. There's one reason code and no record of what it should have been — that's exactly why the problem is invisible from inside real data. It works here only because I wrote the data.

`v_dq_unaccounted_time` compares the machine counter against the operator log, and that comparison *is* runnable in a real plant. But in this project's own numbers it's a demonstration, not a distortion: `v_batch_oee` already uses the machine counter, so the OEE reported here is honest. The view shows what you'd conclude if you only had the log — which is often the situation.

**The framing, precisely.** This is not "how real production data is wrong." It is a *deliberately severe scenario built from common operator-logging failure modes*. The mechanisms are real; the severity is chosen.

## Limitations

**A × P × Q reconciling to OEE proves nothing.** It's an identity — run hours and earned hours cancel algebraically. The assertions on it are typo guards, not validation. Whether the OEE *methodology* is right is a modelling question, not a SQL one. The check that has bite is Performance ≤ 1.0, and it caught a real bug during the build.

**Machine age is not what drives the Availability gap.** `dim_machine` gives the older deck oven a higher failure rate, but the rack oven is *newer*, has a *lower* failure rate, and comes out with *worse* Availability (0.53 vs 0.78). The real driver is changeover frequency: the rack runs ten products in short batches, and the changeover is sometimes longer than the run. The output contradicts the stated causal channel, and I'd rather say so than have it found.

**The rack oven's 53% is a consequence of my parameters.** I chose the batch sizes and the changeover durations. Underloaded, many-SKU lines really do run like this — but this isn't evidence of it.

**Changeovers are not sequence-dependent.** Every product switch draws from the same duration distribution. In a real bakery it depends entirely on the pair — baguette to ficelle is nothing; a temperature-family change or an allergen change is a different order of cost. A transition matrix would be the right fix. It isn't here, and the 75% changeover share is partly a consequence of that plus my volume-descending dispatch rule. It is not a claim about bakeries.

**Fixed routing makes machine collinear with product family.** Bread is always on the deck oven, viennoiserie always on the rack. Downtime on a machine can't be separated from downtime on a product family.

**The Availability denominator is a choice.** Scheduled batch time, not shift length. Other plants use loading time, calendar time, or planned-vs-unplanned splits and get very different numbers. Mine is defensible; it isn't the only defensible one. It also hides utilisation entirely — the rack oven runs about 0.4 hours of a 10-hour shift, and OEE says nothing about that.

**Actual times equal scheduled times.** Downtime is consumed inside a batch's planned window rather than pushing the schedule late. Real breakdowns cascade.

**No proofing, lamination, mixing, preheat, WIP or blocking.** The model is one stage: dough goes in, product comes out. A real bakery has a proofer that gates the oven, and that's often where the real constraint sits.

**Tray-share is capacity allocation, not physical time.** A batch consumes `(trays_used / 18) × cycle_minutes`. But a rack with one tray in it still occupies the oven for the whole bake. There is no oven-load entity grouping concurrent batches into one physical cycle — the model allocates the shared cycle to product batches instead. That keeps batch-level OEE simple and is not a literal representation of elapsed time.

**No shift, crew or time-of-day effects.** Downtime and scrap don't respond to load or to where you are in the shift. Real data breathes with the schedule.

**Downtime reconciles perfectly.** Run time plus stop time equals planned time, exactly, on every batch. Real MES downtime never does — overlapping intervals, stops that begin before the batch, missing end timestamps, entries typed hours late. Perfect reconciliation is itself a synthetic fingerprint.

**The reason codes are compressed loss families, not a proposed reason-code hierarchy.** Real ones are two or three levels deep and the hard question is who owns the loss, not which family it belongs to. Is dough temperature Process, Materials, or Quality? Is waiting for maintenance Mechanical or Personnel? This model puts five neat options where a plant has a governance argument.

**"Scrap" here means finished-unit rejection, and nothing else.** It excludes dough loss at dividing, rework, trim, giveaway, packaging waste, and retail overproduction. Those are all called scrap in a bakery and they are all different quantities. The real layer's waste is *overproduction* — product that didn't sell. It shares a project title with this, not a definition.

Scrap is valued at full standard cost regardless of when it was rejected; real plants charge it at cost accumulated to that point. The cost ratios are invented, so nothing about relative scrap cost is a finding.

**Finishing and labour stations aren't modelled.** `ideal_units_per_hr` is bake-cell capacity, so hand-finished products show lower Performance against an oven-based standard.

**The demand scaling factor is 2, set from a capacity check, not from anything real.** The generator also has perfect foreknowledge of each day's demand — no forecasting, no planning error, which is a large part of what a real production planner actually does.

## Reproducing it

Fixed seed. Same inputs, same output.

```bash
pip install -r requirements.txt
python scripts/build_duckdb.py
```

Built originally on BigQuery. Those scripts are in `sql/synthetic/` and they are the record of how it was built, but **DuckDB is now canonical** — the BigQuery schema predates `reported_duration_minutes` and reason code 98, so it lags. Porting it back would cost a cloud account to verify and buy nothing, so I left it as the historical version and said so rather than quietly letting the two drift.

8,773 batches, 15,808 downtime events, 2,140 inspections, across 21 months of real demand.
