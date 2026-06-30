# Yield & Production Waste Optimization in Industrial Food Manufacturing

**An end-to-end data analytics project analyzing bakery demand and simulating production performance to reduce waste and improve operational efficiency.**

> Built by a working Journeyman Baker (Bäckergeselle) at an industrial bakery in Hamburg, using real bakery sales data and a purpose-built synthetic manufacturing dataset.

---

## Why I built this

I work on the production side of an industrial bakery. Every day I see the same tension up close: produce too much and it becomes waste; produce too little and you miss sales. This project explores how data can take some of the guesswork out of that decision — using real sales data to understand demand, and a simulated production environment to demonstrate how an analytics workflow would support a plant team.

---

## What's real and what's simulated (read this first)

Being explicit about data provenance, because it matters:

- **Sales data — real.** A public bakery sales dataset (~232,710 transactions, Jan 2021–Sep 2022, [N] products after cleaning). All demand, revenue, seasonality, and Pareto analysis is performed on this real data. This is where the *insights* come from.
- **Production / waste / quality / machine data — synthetic.** Production-level data isn't publicly available, so I generated a realistic synthetic dataset that simulates a Manufacturing Execution System (MES), including missing values, downtime, schedule delays, failed inspections, and ingredient overuse. This layer exists to **demonstrate the SQL modeling, pipeline, and dashboard-building workflow** — not to claim discovered operational findings. Any waste/yield figures from it are illustrative.

---

## Business question

> How can an industrial bakery reduce production waste while still meeting customer demand and protecting revenue?

Supporting hypotheses (tested on real sales data): see [`docs/hypotheses_and_research_questions.md`](docs/hypotheses_and_research_questions.md).

---

## Key findings *(in progress)*

*Real-data analysis:*
- [ ] Demand concentration: the top [X] products account for [Y]% of volume.
- [ ] Volume ≠ revenue: [example of a high-volume / low-margin or vice-versa product].
- [ ] Weekly pattern: busiest day is [day], quietest is [day], with [magnitude] difference.
- [ ] Seasonality: [highest-demand months / trend over time].

*Each finding will link to the supporting notebook and a dashboard view.*

---

## Tech stack

| Layer | Tools |
|---|---|
| Language | Python (pandas, NumPy), SQL (BigQuery) |
| Analysis | Jupyter notebooks, Matplotlib, Plotly |
| Storage | CSV, Google BigQuery |
| Dashboard | Data Studio |
| Tooling | VS Code, Git, GitHub, venv |

---

## Repository structure

```
yield-product-waste-optimization/
├── data/
│   ├── raw/         # real bakery sales dataset
│   ├── synthetic/   # simulated MES tables (production, waste, quality, machines)
│   ├── cleaned/     # cleaned outputs
│   └── processed/
├── notebooks/       # 01_understanding → 05_business_analysis
├── sql/             # table creation, cleaning views, KPI views
├── dashboard/       # Data Studio exports + screenshots
├── docs/            # project scope, hypotheses, executive summary
├── images/
└── README.md
```

---

## How to reproduce

```bash
git clone https://github.com/[username]/yield-product-waste-optimization.git
cd yield-product-waste-optimization
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
# run notebooks in order, 01 → 05
```

---

## Dashboard

🔗 **[Live Data Studio dashboard →](#)** *(link once published)*

![Dashboard preview](dashboard/screenshots/overview.png) *(add once built)*

---

## Roadmap

- [x] Project scope, hypotheses, and data organized
- [ ] **v1:** Clean real sales data → EDA → 2–3 page demand dashboard → executive summary
- [ ] **v2:** Synthetic MES modeling in BigQuery → full production/waste/quality/OEE dashboard
- [ ] Business recommendations + quantified (illustrative) impact

---

## About me

Journeyman Baker transitioning into data analytics, combining 9+ years in industrial food manufacturing and international hospitality operations with a B.Sc. in Business Administration and a Data Analytics bootcamp. I use my production-floor experience as the domain lens for analytics work.

📫 [LinkedIn] · [Email]
