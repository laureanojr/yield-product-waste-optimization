-- KPI views. All metrics derive here; the fact tables hold raw events only.
--
-- OEE is computed on a time basis. Products run from 34 to 1,728 units/hr, so
-- summing units across them to roll up OEE would be meaningless. Each batch
-- converts its output into "earned hours" (units / ideal rate) instead.

CREATE OR REPLACE VIEW v_batch_oee AS
WITH logged_stops AS (
  -- was_logged only: micro-stops never reach a terminal, so an analyst working
  -- from the operator log can't see them either.
  SELECT batch_id,
         SUM(duration_minutes) AS logged_stop_minutes,
         COUNT(*)              AS logged_stop_events
  FROM fact_downtime
  WHERE was_logged
  GROUP BY batch_id
)
SELECT
  b.batch_id,
  b.production_date,
  b.product_id,
  p.product_name,
  p.product_category,
  b.machine_id,
  m.machine_name,

  b.planned_units,
  b.good_units,
  b.scrap_units,
  b.good_units + b.scrap_units                              AS total_units,

  b.planned_production_minutes / 60.0                       AS planned_hours,
  b.run_time_minutes / 60.0                                 AS run_hours,
  COALESCE(s.logged_stop_minutes, 0) / 60.0                 AS logged_stop_hours,
  COALESCE(s.logged_stop_events, 0)                         AS logged_stop_events,

  (b.good_units + b.scrap_units) / p.ideal_units_per_hr     AS earned_hours,
  b.good_units / p.ideal_units_per_hr                       AS good_earned_hours,

  -- Availability uses run_time_minutes, the machine's own counter — NOT the
  -- operator log. So the OEE reported by this project is not distorted by the
  -- unlogged micro-stops. v_dq_unaccounted_time shows what it would look like
  -- if it were.
  b.run_time_minutes / NULLIF(b.planned_production_minutes, 0)              AS availability,
  ((b.good_units + b.scrap_units) / p.ideal_units_per_hr)
      / NULLIF(b.run_time_minutes / 60.0, 0)                                AS performance,
  b.good_units / NULLIF(b.good_units + b.scrap_units, 0)                    AS quality,
  (b.good_units / p.ideal_units_per_hr)
      / NULLIF(b.planned_production_minutes / 60.0, 0)                      AS oee,

  -- Full standard cost, all scrap valued the same regardless of when it was
  -- rejected. Real plants charge scrap at cost accumulated to that point. The
  -- cost ratios are fabricated, so this column supports no conclusion.
  b.scrap_units * p.unit_cost_eur                           AS scrap_cost_eur

FROM fact_production_batch b
JOIN dim_product p USING (product_id)
JOIN dim_machine m ON m.machine_id = b.machine_id
LEFT JOIN logged_stops s USING (batch_id);


CREATE OR REPLACE VIEW v_oee_daily AS
SELECT
  production_date,
  machine_id,
  machine_name,
  COUNT(*)                      AS batches,
  SUM(total_units)              AS total_units,
  SUM(good_units)               AS good_units,
  SUM(scrap_units)              AS scrap_units,
  ROUND(SUM(scrap_cost_eur), 2) AS scrap_cost_eur,
  ROUND(SUM(planned_hours), 2)     AS planned_hours,
  ROUND(SUM(run_hours), 2)         AS run_hours,
  ROUND(SUM(logged_stop_hours), 2) AS logged_stop_hours,
  ROUND(SUM(run_hours)         / NULLIF(SUM(planned_hours), 0), 4) AS availability,
  ROUND(SUM(earned_hours)      / NULLIF(SUM(run_hours), 0),     4) AS performance,
  ROUND(SUM(good_earned_hours) / NULLIF(SUM(earned_hours), 0),  4) AS quality,
  ROUND(SUM(good_earned_hours) / NULLIF(SUM(planned_hours), 0), 4) AS oee
FROM v_batch_oee
GROUP BY production_date, machine_id, machine_name;


-- Scrap rate and scrap cost rank differently. Which one a plant chases is a
-- business call.
CREATE OR REPLACE VIEW v_scrap_by_product AS
SELECT
  product_id,
  product_name,
  product_category,
  machine_name,
  COUNT(*)         AS batches,
  SUM(total_units) AS total_units,
  SUM(scrap_units) AS scrap_units,
  ROUND(SUM(scrap_units)    / NULLIF(SUM(total_units), 0), 4) AS scrap_rate,
  ROUND(SUM(scrap_cost_eur), 2)                               AS scrap_cost_eur,
  ROUND(SUM(scrap_cost_eur) / NULLIF(SUM(total_units), 0), 4) AS scrap_cost_per_unit
FROM v_batch_oee
GROUP BY product_id, product_name, product_category, machine_name;


-- The downtime report a plant would actually have: reported codes, logged rows.
-- This is the view that's wrong, and v_dq_reason_coding shows by how much.
CREATE OR REPLACE VIEW v_downtime_pareto AS
SELECT
  d.machine_id,
  m.machine_name,
  d.reported_reason_code  AS reason_code,
  d.reported_reason_label AS reason_label,
  COUNT(*)                                 AS events,
  ROUND(SUM(d.duration_minutes) / 60.0, 2) AS stop_hours,
  ROUND(SUM(d.duration_minutes)
        / SUM(SUM(d.duration_minutes)) OVER (PARTITION BY d.machine_id), 4)
                                           AS share_of_machine_stop_time
FROM fact_downtime d
JOIN dim_machine m USING (machine_id)
WHERE d.was_logged
GROUP BY d.machine_id, m.machine_name, d.reported_reason_code, d.reported_reason_label;


-- Reported reason codes against what actually caused each stop.
--
-- This view can't be built in a real plant: there is one reason code and no
-- record of what it should have been. It works here only because the data is
-- synthetic. The distortion it measures is real in its effect though —
-- v_downtime_pareto reads the same reported codes, so the Pareto a maintenance
-- team would prioritise off is genuinely misleading.
CREATE OR REPLACE VIEW v_dq_reason_coding AS
WITH reported AS (
  SELECT reported_reason_code AS code, SUM(duration_minutes) AS reported_minutes
  FROM fact_downtime WHERE was_logged
  GROUP BY code
),
truth AS (
  SELECT true_reason_code AS code, SUM(duration_minutes) AS true_minutes
  FROM fact_downtime
  GROUP BY code
),
totals AS (
  SELECT (SELECT SUM(true_minutes) FROM truth)        AS t_all,
         (SELECT SUM(reported_minutes) FROM reported) AS r_all
)
SELECT
  COALESCE(t.code, r.code) AS reason_code,
  ROUND(COALESCE(t.true_minutes, 0) / 60.0, 1)     AS true_stop_hours,
  ROUND(COALESCE(r.reported_minutes, 0) / 60.0, 1) AS reported_stop_hours,
  ROUND(t.true_minutes     / totals.t_all, 4)      AS true_share,
  ROUND(r.reported_minutes / totals.r_all, 4)      AS reported_share,
  -- Negative = understated in the data a plant would actually hold.
  ROUND(COALESCE(r.reported_minutes, 0) / totals.r_all
        - COALESCE(t.true_minutes, 0) / totals.t_all, 4) AS share_distortion
FROM truth t
FULL OUTER JOIN reported r USING (code)
CROSS JOIN totals;


-- Machine counter against operator log. The gap is stop time nobody recorded.
--
-- This is a CHECK, not a flaw in the numbers above. v_batch_oee already uses the
-- machine counter, so availability_actual is what this project reports. The
-- point of the view is that plants often have only the operator log —
-- availability_from_log is what you would conclude if you trusted it, and the
-- gap between the two columns is the reason to run the comparison at all.
CREATE OR REPLACE VIEW v_dq_unaccounted_time AS
SELECT
  machine_id,
  machine_name,
  ROUND(SUM(planned_hours - run_hours), 1)                          AS true_stop_hours,
  ROUND(SUM(logged_stop_hours), 1)                                  AS logged_stop_hours,
  ROUND(SUM(planned_hours - run_hours) - SUM(logged_stop_hours), 1) AS unaccounted_hours,
  ROUND(1 - SUM(logged_stop_hours)
            / NULLIF(SUM(planned_hours - run_hours), 0), 4)         AS unaccounted_share,
  ROUND((SUM(planned_hours) - SUM(logged_stop_hours))
        / NULLIF(SUM(planned_hours), 0), 4)                         AS availability_from_log,
  ROUND(SUM(run_hours) / NULLIF(SUM(planned_hours), 0), 4)          AS availability_actual
FROM v_batch_oee
GROUP BY machine_id, machine_name;
