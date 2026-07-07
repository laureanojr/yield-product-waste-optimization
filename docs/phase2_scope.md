# v2 Scope — Production, Waste & Yield Simulation

*This is the plan for the next stage of the project. v1 (real bakery sales analysis) is complete and live. v2 extends it with a synthetic manufacturing layer.*

## Why a synthetic dataset

Real production data — waste logs, machine downtime, quality inspections — isn't publicly available. So I build a synthetic dataset that simulates a Manufacturing Execution System (MES) for an industrial bakery. The point is to show how I would analyse production and waste in a real plant: the pipeline, the SQL modelling, the KPIs, the dashboard.

I want to be clear about this everywhere: **v2 is a demonstration of method, not a source of real findings.** Only v1 (real sales data) supports business conclusions. Any waste, yield, or OEE numbers in v2 come from data I generated, so they show capability, not discovery.

## What the synthetic data will include

An MES-style set of linked tables, realistic enough to carry genuine operational patterns (and deliberate messiness to clean):

- **production_batches** — batches produced, planned vs actual output, product, line, shift, date
- **waste_logs** — waste quantity and reason per batch (overproduction, quality fail, spoilage, changeover)
- **quality_inspections** — pass/fail, defect type, inspection score
- **machine_logs** — runtime, downtime, breakdown events per machine
- **production_schedules** — planned schedule vs actual (delays, adherence)

The synthetic data should connect believably to the v1 demand patterns (e.g. higher planned output on weekends and in summer), so the two halves tell one coherent story.

## Questions v2 will demonstrate

- Where does production waste occur most (by product, line, shift, machine)?
- What is production yield (actual vs planned output), and where is it lowest?
- Which machines have the most downtime, and how does it affect output?
- What drives quality failures?
- How do demand (v1) and production (v2) line up — is overproduction tied to weak-demand days?

## KPIs to build (in SQL, on top of the synthetic data)

Production yield %, waste %, waste cost, schedule adherence, machine availability / downtime, inspection pass rate, and a simplified OEE (Overall Equipment Effectiveness). Each as a BigQuery view, same pattern as the v1 KPI views.

## Deliverables

1. A synthetic-data generator script (documented, reproducible) in `scripts/`.
2. The synthetic CSVs in `data/synthetic/`.
3. SQL views for the production/waste/quality KPIs in `sql/`.
4. New dashboard pages (waste analysis, production/yield, machine performance), clearly labelled as simulated.
5. Notebook(s) for the synthetic EDA in `notebooks/`.
6. Updated README section and honest framing throughout.

## Build order (planned)

1. **First, finish v1's story** — add two dashboard pages to the existing dashboard: a "Why / context" page and a "Recommendations / Conclusion" page. Quick wins.
2. Design and generate the synthetic MES dataset.
3. Load into BigQuery, build the production/waste/quality KPI views.
4. Synthetic EDA in Python.
5. Extend the dashboard with the production/waste pages.
6. Update docs and README, commit, and this becomes v2.

## Working principles (unchanged from v1)

- Step by step, one thing at a time. I run the code and understand the why.
- Honest, critical feedback over praise.
- Everything documented and reproducible; verified numbers only.
- Synthetic clearly separated from real, always.
