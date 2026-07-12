-- =============================================================================
-- duckdb_views.sql — KPI views
--
-- OEE IS COMPUTED ON A TIME BASIS, NOT A UNIT BASIS.
--
-- Products on this line run from 33.75 units/hr (campagne) to 1,728 units/hr
-- (cookie). Summing units across them to roll up OEE would be nonsense — a
-- cookie and a country loaf are not comparable units, and the cookie would
-- swamp everything.
--
-- So each batch converts its output into EARNED HOURS: units / ideal rate, the
-- time it SHOULD have taken. Then
--
--     Availability = run hours       / planned hours
--     Performance  = earned hours    / run hours
--     Quality      = good earned hrs / earned hours
--     OEE          = good earned hrs / planned hours
--
-- and A x P x Q = OEE EXACTLY, at every level of aggregation. A naive unit-based
-- rollup does not reconcile once products have different rates. This is why the
-- validation suite can ASSERT the identity rather than hope it roughly holds.
--
-- WHAT THE VIEWS ARE ALLOWED TO SEE
-- KPI views read ONLY reported_reason_code, and ONLY rows where was_logged —
-- because that is all a real analyst would ever have. true_reason_code and the
-- unlogged rows exist for the two v_dq_* views alone: they are the ruler, not
-- the data.
-- =============================================================================

CREATE OR REPLACE VIEW v_batch_oee AS
WITH logged_stops AS (
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

  b.run_time_minutes / NULLIF(b.planned_production_minutes, 0)              AS availability,
  ((b.good_units + b.scrap_units) / p.ideal_units_per_hr)
      / NULLIF(b.run_time_minutes / 60.0, 0)                                AS performance,
  b.good_units / NULLIF(b.good_units + b.scrap_units, 0)                    AS quality,
  (b.good_units / p.ideal_units_per_hr)
      / NULLIF(b.planned_production_minutes / 60.0, 0)                      AS oee,

  -- Scrap at full standard cost. SIMPLIFICATION: a real plant charges scrap at
  -- cost accumulated to the point of rejection — dough dumped at proofing is
  -- cheap, a loaf pulled after the bake carries the full oven. One stage here.
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
  -- Scrap RATE and scrap COST rank differently, and that gap is the whole point
  -- of costing scrap. A high-rate cheap product can matter less than a low-rate
  -- expensive one. Which one a plant chases is a business decision.
  ROUND(SUM(scrap_cost_eur) / NULLIF(SUM(total_units), 0), 4) AS scrap_cost_per_unit
FROM v_batch_oee
GROUP BY product_id, product_name, product_category, machine_name;


-- WHAT A REAL ANALYST WOULD SEE. Reported codes, logged rows, no access to the
-- truth. This is the view you would actually build in a plant — and it is the
-- one that fails.
CREATE OR REPLACE VIEW v_downtime_pareto AS
SELECT
  d.machine_id,
  m.machine_name,
  d.reported_reason_code  AS reason_code,
  d.reported_reason_label AS reason_label,
  COUNT(*)                               AS events,
  ROUND(SUM(d.duration_minutes) / 60.0, 2) AS stop_hours,
  ROUND(SUM(d.duration_minutes)
        / SUM(SUM(d.duration_minutes)) OVER (PARTITION BY d.machine_id), 4)
                                         AS share_of_machine_stop_time
FROM fact_downtime d
JOIN dim_machine m USING (machine_id)
WHERE d.was_logged
GROUP BY d.machine_id, m.machine_name, d.reported_reason_code, d.reported_reason_label;


-- THE PATHOLOGY, MEASURED.
--
-- THIS VIEW CANNOT EXIST IN A REAL PLANT. There is one reason code and no record
-- of what it should have been — which is precisely why the problem is invisible
-- from inside real data, and why an analyst has to reason about it rather than
-- query it.
--
-- Here the generator knows the truth, so the distortion can be MEASURED instead
-- of asserted. That is what the synthetic layer is FOR.
CREATE OR REPLACE VIEW v_dq_reason_coding AS
WITH reported AS (
  SELECT reported_reason_code AS code, SUM(duration_minutes) AS reported_minutes
  FROM fact_downtime WHERE was_logged          -- what the analyst can see
  GROUP BY code
),
truth AS (
  SELECT true_reason_code AS code, SUM(duration_minutes) AS true_minutes
  FROM fact_downtime                            -- everything, logged or not
  GROUP BY code
),
totals AS (
  SELECT (SELECT SUM(true_minutes) FROM truth)         AS t_all,
         (SELECT SUM(reported_minutes) FROM reported)  AS r_all
)
SELECT
  COALESCE(t.code, r.code) AS reason_code,
  ROUND(COALESCE(t.true_minutes, 0) / 60.0, 1)     AS true_stop_hours,
  ROUND(COALESCE(r.reported_minutes, 0) / 60.0, 1) AS reported_stop_hours,
  ROUND(t.true_minutes     / totals.t_all, 4)      AS true_share,
  ROUND(r.reported_minutes / totals.r_all, 4)      AS reported_share,
  -- Negative = this cause is UNDERSTATED in the data a plant actually holds.
  -- Changeover is the big loser: it is mostly short stops, and short stops are
  -- exactly what gets dumped into the catch-all. The single biggest lever on the
  -- line is the one its own downtime report hides.
  ROUND(COALESCE(r.reported_minutes, 0) / totals.r_all
        - COALESCE(t.true_minutes, 0) / totals.t_all, 4) AS share_distortion
FROM truth t
FULL OUTER JOIN reported r USING (code)
CROSS JOIN totals;


-- The second half of the pathology — and unlike the view above, an analyst CAN
-- build this one in a real plant: machine counters against the operator log.
--
-- The machine was not running for (planned - run) minutes. The operator logged
-- less than that. The gap is time nobody recorded: micro-stops too short for
-- anyone to bother entering. This is the check that catches an Availability
-- figure flattering the line. Distrust the data first.
CREATE OR REPLACE VIEW v_dq_unaccounted_time AS
SELECT
  machine_id,
  machine_name,
  ROUND(SUM(planned_hours - run_hours), 1)                          AS true_stop_hours,
  ROUND(SUM(logged_stop_hours), 1)                                  AS logged_stop_hours,
  ROUND(SUM(planned_hours - run_hours) - SUM(logged_stop_hours), 1) AS unaccounted_hours,
  ROUND(1 - SUM(logged_stop_hours)
            / NULLIF(SUM(planned_hours - run_hours), 0), 4)         AS unaccounted_share,
  -- The first number is the one that ends up on the dashboard.
  ROUND((SUM(planned_hours) - SUM(logged_stop_hours))
        / NULLIF(SUM(planned_hours), 0), 4)                         AS availability_from_log,
  ROUND(SUM(run_hours) / NULLIF(SUM(planned_hours), 0), 4)          AS availability_actual
FROM v_batch_oee
GROUP BY machine_id, machine_name;
