-- Validation: confirms the loaded table matches the Python analysis
-- Expected: 232,679 rows | 147 products | 562,716.70 revenue
SELECT
  COUNT(*)               AS total_rows,
  COUNT(DISTINCT article) AS products,
  ROUND(SUM(revenue), 2) AS total_revenue
FROM `bakery.sales`;
