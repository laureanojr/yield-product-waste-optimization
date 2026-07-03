-- KPI: units and revenue per month (seasonal trend)
CREATE OR REPLACE VIEW `bakery.kpi_monthly` AS
SELECT
  sale_month,
  SUM(quantity)         AS total_units,
  ROUND(SUM(revenue),2) AS total_revenue
FROM `bakery.v_sales`
GROUP BY sale_month
ORDER BY sale_month;
