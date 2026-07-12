#!/usr/bin/env python3
"""
load_synthetic_to_bigquery.py
Loads the three generated fact CSVs into bakery_synthetic.

WRITE_TRUNCATE, not append. Rerunning the generator and reloading must produce
the same tables, not double them. The seed is fixed, so the same inputs always
give the same output — if the repo cannot reproduce it, it is not reproducible.

The schema is NOT autodetected. The tables already exist, created by
sql/synthetic/07_create_fact_tables.sql with explicit types, partitioning and
clustering. Autodetect would silently redefine them and quietly drop the
partitioning.

USAGE
    python scripts/load_synthetic_to_bigquery.py
"""

from pathlib import Path

from google.cloud import bigquery

PROJECT = "bakery-analytics-501220"
DATASET = "bakery_synthetic"
LOCATION = "EU"

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data" / "synthetic"

TABLES = [
    "fact_production_batch",
    "fact_downtime",
    "fact_quality_inspection",
]


def main():
    client = bigquery.Client(project=PROJECT, location=LOCATION)

    for table in TABLES:
        path = DATA / f"{table}.csv"
        if not path.exists():
            raise SystemExit(f"missing {path} — run generate_synthetic_production.py first")

        ref = f"{PROJECT}.{DATASET}.{table}"

        job = client.load_table_from_file(
            path.open("rb"),
            ref,
            job_config=bigquery.LoadJobConfig(
                source_format=bigquery.SourceFormat.CSV,
                skip_leading_rows=1,
                write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
                # Keep the existing schema, partitioning and clustering.
                schema_update_options=None,
                autodetect=False,
            ),
        )
        job.result()

        n = client.get_table(ref).num_rows
        print(f"  {table:<28} {n:>8,} rows")

    print("\nLoaded. Next: sql/synthetic/08_create_kpi_views.sql")


if __name__ == "__main__":
    main()
