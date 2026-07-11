-- Selects the 27 manufacturable products for the SYNTHETIC product master.
-- Reads the REAL v1 KPI view (read-only). No real row enters the synthetic layer —
-- only product names and unit totals, used to anchor synthetic demand.
--
-- Selection: top 30 by real v1 units, minus three items that sell through the till
-- but are not manufactured on a bakery line:
--   CAFE OU EAU      — a drink. No production rate, no scrap.
--   FORMULE SANDWICH — a POS meal-deal bundle, not a made item.
--   COUPE            — flat EUR 0.15 across 20,386 sales and 21 months, zero price
--                      variation while every real product repriced. An ancillary
--                      charge, not a baked good. See 03_audit_product_manufacturability.sql
--
-- Result: 27 products = 81.5% of real v1 units, 69.0% of real v1 revenue.
--
-- IMPORTANT: set query processing location to EU before running.

WITH ranked AS (
  SELECT
    product,
    total_units,
    ROW_NUMBER() OVER (ORDER BY total_units DESC, product ASC) AS rank_units
  FROM `bakery.kpi_product_performance`
),
manufacturable AS (
  SELECT product, total_units
  FROM ranked
  WHERE rank_units <= 30
    AND product NOT IN ('CAFE OU EAU', 'FORMULE SANDWICH', 'COUPE')
)
SELECT
  ROW_NUMBER() OVER (ORDER BY total_units DESC, product ASC) AS product_id,
  product     AS product_name,
  total_units AS v1_total_units
FROM manufacturable
ORDER BY product_id;
