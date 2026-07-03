-- KPI: demand by weekday, incl. avg revenue per OPEN day (handles the Wednesday-closed effect)
CREATE OR REPLACE VIEW `bakery.kpi_by_day_of_week` AS
SELECT
  day_of_week,
  COUNT(DISTINCT sale_date) AS days_open,
  SUM(quantity)             AS total_units,
  ROUND(SUM(revenue),2)     AS total_revenue,
  ROUND(SUM(revenue)/COUNT(DISTINCT sale_date),2) AS avg_revenue_per_open_day
FROM `bakery.v_sales`
GROUP BY day_of_week;
