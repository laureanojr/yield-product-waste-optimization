-- KPI: units, revenue, and times sold per product (answers "which products drive the business")
CREATE OR REPLACE VIEW `bakery.kpi_product_performance` AS
SELECT
  product,
  SUM(quantity)         AS total_units,
  ROUND(SUM(revenue),2) AS total_revenue,
  COUNT(*)              AS times_sold
FROM `bakery.v_sales`
GROUP BY product
ORDER BY total_revenue DESC;
