-- KPI: units and revenue per hour of day (the morning-rush pattern)
CREATE OR REPLACE VIEW `bakery.kpi_by_hour` AS
SELECT
  sale_hour,
  SUM(quantity)         AS total_units,
  ROUND(SUM(revenue),2) AS total_revenue
FROM `bakery.v_sales`
GROUP BY sale_hour
ORDER BY sale_hour;
