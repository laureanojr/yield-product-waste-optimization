# Bakery Sales & Demand Analysis

**An end-to-end data analytics project turning two years of real bakery sales into production-planning insight, built by a working baker moving into data.**

> **Status:** Phase 1 complete — Sales & Demand Analysis (this repo).
> Phase 2 planned — Production, Waste & Yield Simulation.

🔗 **[Live dashboard →](https://datastudio.google.com/reporting/bde95bb5-686c-4339-b187-8d770afe2693)**

![Executive dashboard](dashboard/screenshots/dashboard_overview.png)

---

## Why I built this

I'm a baker. I trained as a Bäckergeselle and spent about nine years in industrial food production before moving into data analytics, so this isn't a dataset I picked at random. It's the problem I lived with every day.

In a bakery you're always guessing. Make too much and it goes in the bin at closing. Make too little and you turn customers away and lose the sale. This project uses real sales data to take some of that guessing out of production planning, so a bakery can make less waste without losing sales.

---

## Two parts, and only one is real

The sales analysis here is built on real data, and it's the only part I draw business conclusions from. A later extension will add a *synthetic* production dataset (waste, machine downtime, quality) to show how I'd analyse a real plant. That part will be a clearly-labelled demonstration of method, not a source of findings.

---

## The data

A real point-of-sale export from a French bakery, January 2021 to September 2022. I started with 234,005 raw rows and cleaned it down to **232,679 sales lines across 147 products**, worth **€562,717** in revenue. Cleaning meant converting text prices like `"0,90 €"` into real numbers, merging separate date and time columns into one timestamp, and removing 1,295 returns and 31 zero-price rows (a refund isn't demand, so it doesn't belong in a demand analysis). Every column is documented in [`docs/data_dictionary.md`](docs/data_dictionary.md).

---

## What I found

**One product carries the business.** The traditional baguette is about a third of every item sold and roughly a quarter of all revenue, more than the next four products put together.

**Best sellers aren't best earners.** Sandwiches sell in much smaller numbers but jump near the top on revenue, because they carry a far higher price than a ninety-cent baguette. Planning production off unit counts alone would quietly undervalue them.

**Demand is weekend-heavy.** Sunday is the biggest day by a wide margin, around two and a half times a normal weekday. Wednesday looks like the deadest day, but that's because the bakery is closed most Wednesdays (62 trading days versus about 90 for other days), not because nobody wants bread. Catching that before writing it down mattered.

**There's a repeatable summer peak.** July and August are the strongest months in both 2021 and 2022, and it holds up even when I compare average revenue per open day, so it's a real seasonal signal rather than a counting quirk.

**It's a morning business.** Sales concentrate between 8am and noon, peaking around 11, then drop off sharply in the afternoon.

**So what:** prioritise baguette availability, treat sandwiches as high-value items worth protecting, and scale production up for weekends and summer.

---

## How I built it

The full write-up of every step and the reasoning behind it is in [`docs/build_guide.md`](docs/build_guide.md).

- **Cleaning and analysis:** Python (pandas, NumPy) in Jupyter notebooks. See [`notebooks/`](notebooks/).
- **Data modelling:** loaded the clean data into Google BigQuery and built KPI views in SQL. See [`sql/`](sql/).
- **Dashboard:** Google Data Studio, sourced from an aggregated table, published and public.
- **Charts:** Matplotlib. See [`images/charts/`](images/charts/).

---

## Repository structure

```
├── data/            raw + cleaned data
├── notebooks/       01 understanding → 03 exploratory analysis
├── sql/             BigQuery views and KPI queries
├── dashboard/       dashboard screenshots + SQL proof
├── images/charts/   analysis charts
├── docs/            project scope, hypotheses, data dictionary, build guide
└── scripts/         dashboard data aggregation
```

---

## Reproduce it

```bash
git clone https://github.com/laureanojr/yield-product-waste-optimization.git
cd yield-product-waste-optimization
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
# run the notebooks in order, 01 → 03
```

---

## About me

Journeyman baker moving into data analytics, based in the Hamburg area. I combine nine years in industrial food manufacturing with a B.Sc. in Business Administration and a data analytics bootcamp, and I use the production floor as the lens for my analytics work.

📫 [LinkedIn](https://www.linkedin.com/in/laureanojr-cantor) · [Email](mailto:laureano@jrcantor.de)
