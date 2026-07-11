-- Audit: does each candidate product behave like a manufactured item?
-- A real product's price moves over 21 months (price rises, promos, size variants).
-- A flat, never-changing price signals an ancillary charge (bag, wrapper, fee), not a baked good.
SELECT
  product,
  COUNT(*)                    AS times_sold,
  SUM(quantity)               AS units,
  COUNT(DISTINCT unit_price)  AS distinct_prices,
  MIN(unit_price)             AS min_price,
  MAX(unit_price)             AS max_price,
  ROUND(MAX(unit_price) - MIN(unit_price), 2) AS price_spread
FROM `bakery.v_sales`
WHERE product IN (
  'TRADITIONAL BAGUETTE','CROISSANT','PAIN AU CHOCOLAT','BANETTE','BAGUETTE',
  'CEREAL BAGUETTE','SPECIAL BREAD','TARTELETTE','BOULE 400G','CAMPAGNE',
  'COOKIE','ECLAIR','VIK BREAD','COMPLET','FICELLE','MOISSON','BANETTINE',
  'BOULE 200G','PAIN BANETTE','SANDWICH COMPLET','PAIN AUX RAISINS','PAIN',
  'KOUIGN AMANN','CROISSANT AMANDES','QUIM BREAD','CHAUSSON AUX POMMES',
  'PAIN CHOCO AMANDES'
)
GROUP BY product
ORDER BY distinct_prices ASC, price_spread ASC;
