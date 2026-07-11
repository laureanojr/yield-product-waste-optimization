-- Creates the synthetic dataset and the product master for the SYNTHETIC layer.
-- Run once, in the BigQuery console.
--
-- IMPORTANT: set the query processing location to EU before running.
-- (More > Query settings > Data location > EU)
-- DDL that creates a new dataset has no table to infer the region from, so it
-- defaults to US and fails against the EU-resident `bakery` dataset.

CREATE SCHEMA IF NOT EXISTS `bakery_synthetic`
OPTIONS (location = 'EU');   -- must match the real `bakery` dataset (EU)

CREATE OR REPLACE TABLE `bakery_synthetic.dim_product` (
  product_id          INT64   NOT NULL,   -- surrogate key; clean joins, no French strings in facts
  product_name        STRING  NOT NULL,   -- real v1 article name — the tie back to the 147-product list
  product_category    STRING  NOT NULL,   -- bread | viennoiserie | patisserie | sandwich
  process_type        STRING  NOT NULL,   -- baked | assembled
  unit_cost_eur       NUMERIC,            -- SYNTHETIC standard cost. NUMERIC = exact decimal, money must not drift
  ideal_units_per_hr  FLOAT64,            -- SYNTHETIC theoretical max. The single denominator for OEE Performance
  v1_total_units      INT64               -- REAL units from v1. Demand anchor + coverage evidence
)
OPTIONS (
  description = "Product master for the SYNTHETIC manufacturing layer. 27 manufacturable products, selected as top-30 by real v1 units minus three items that sell through the till but are not made on a bakery line: CAFE OU EAU (a drink), FORMULE SANDWICH (a POS meal-deal bundle, not a made item), and COUPE (flat EUR 0.15 across 20,386 sales and 21 months with zero price variation, while every real product repriced — an ancillary charge, not a baked good). Covers 81.5% of real v1 units and 69.0% of real v1 revenue. unit_cost_eur and ideal_units_per_hr are FABRICATED standards, not real bakery figures. v1_total_units is the only real value in this table, used to shape synthetic demand — real data informs the shape of the simulation, never its contents."
);
