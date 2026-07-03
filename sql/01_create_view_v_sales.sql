-- Clean base view: friendly column names + extracted date parts (day, hour, month)
CREATE OR REPLACE VIEW `bakery.v_sales` AS
SELECT
  ticket_number,
  article                              AS product,
  Quantity                             AS quantity,
  unit_price,
  revenue,
  datetime,
  DATE(datetime)                       AS sale_date,
  EXTRACT(HOUR   FROM datetime)        AS sale_hour,
  FORMAT_DATE('%A', DATE(datetime))    AS day_of_week,
  DATE_TRUNC(DATE(datetime), MONTH)    AS sale_month
FROM `bakery.sales`;
