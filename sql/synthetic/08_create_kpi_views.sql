-- =============================================================================
-- 08_create_kpi_views.sql
-- Synthetic manufacturing layer — KPI views
--
-- Every metric in this project derives HERE. The fact tables hold raw events
-- only: no yield %, no waste rate, no OEE column anywhere in the schema.
--
-- -----------------------------------------------------------------------------
-- OEE IS COMPUTED ON A TIME BASIS, NOT A UNIT BASIS
-- -----------------------------------------------------------------------------
-- The products on this line run from 33.75 units/hr (campagne) to 1,728
-- units/hr (cookie). Summing units across them to roll up OEE would be
-- nonsense: a cookie and a country loaf are not comparable units, and the
-- cookie would swamp everything.
--
-- So each batch converts its output into EARNED HOURS — units / ideal rate, the
-- time it SHOULD have taken. Then:
--
--     Availability = run hours      / planned hours
--     Performance  = earned hours   / run hours
--     Quality      = good earned hrs/ earned hours
--     OEE          = good earned hrs/ planned hours
--
-- and A x P x Q = OEE EXACTLY, at every level of aggregation. A naive
-- unit-based rollup does not reconcile once products have different rates. This
-- is the standard time-based formulation, and it is why 09_validate.sql can
-- assert the identity holds rather than hoping it roughly does.
--
-- At batch grain, Quality here equals good_units / total_units exactly. The two
-- only diverge on rollup, where the time basis is the correct one.
--
-- -----------------------------------------------------------------------------
-- WHAT THE VIEWS ARE ALLOWED TO SEE
-- -----------------------------------------------------------------------------
-- The KPI views read ONLY `reported_reason_code`, and ONLY rows where
-- `was_logged = TRUE` — because that is all a real analyst would ever have.
--
-- `true_reason_code` and the unlogged rows exist for ONE purpose: the two
-- v_dq_* views at the bottom, which MEASURE the distortion instead of asserting
-- it. They are the ruler, not the data.
--
-- -----------------------------------------------------------------------------
-- NO FINDINGS
-- -----------------------------------------------------------------------------
-- I wrote this data. Every pattern these views surface is an assumption in
-- config/synthetic_generator.yaml, read back. These views demonstrate that the
-- metrics can be derived correctly and that a real analyst would know what to
-- look at. They discover nothing about bakeries.
--
-- IMPORTANT: set query processing location to EU before running.
-- =============================================================================


-- =============================================================================
-- v_batch_oee — the grain. One row per batch. Everything else builds on this.
-- =============================================================================
CREATE OR REPLACE VIEW `bakery_synthetic.v_batch_oee` AS
WITH logged_stops AS (
  -- WHERE was_logged: unlogged micro-stops are invisible to a real analyst, so
  -- they must be invisible here too.
  SELECT batch_id,
         SUM(duration_minutes) AS logged_stop_minutes,
         COUNT(*)              AS logged_stop_events
  FROM `bakery_synthetic.fact_downtime`
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
  b.good_units + b.scrap_units                             AS total_units,

  b.planned_production_minutes / 60.0                      AS planned_hours,
  b.run_time_minutes / 60.0                                AS run_hours,
  COALESCE(s.logged_stop_minutes, 0) / 60.0                AS logged_stop_hours,
  COALESCE(s.logged_stop_events, 0)                        AS logged_stop_events,

  -- Earned hours: the time the output SHOULD have taken at the ideal rate.
  (b.good_units + b.scrap_units) / p.ideal_units_per_hr    AS earned_hours,
  b.good_units / p.ideal_units_per_hr                      AS good_earned_hours,

  -- The three terms.
  SAFE_DIVIDE(b.run_time_minutes, b.planned_production_minutes)          AS availability,
  SAFE_DIVIDE((b.good_units + b.scrap_units) / p.ideal_units_per_hr,
              b.run_time_minutes / 60.0)                                 AS performance,
  SAFE_DIVIDE(b.good_units, b.good_units + b.scrap_units)                AS quality,
  SAFE_DIVIDE(b.good_units / p.ideal_units_per_hr,
              b.planned_production_minutes / 60.0)                       AS oee,

  -- Scrap valued at full standard cost. SIMPLIFICATION: a real plant values
  -- scrap at cost accumulated to the point of rejection — dough dumped at
  -- proofing is cheap, a loaf pulled after the bake carries the full oven cost.
  -- This schema has one stage, so it cannot make that distinction, and says so.
  --
  -- CIRCULARITY WARNING: unit_cost_eur derives from a FABRICATED category ratio.
  -- "Patisserie carries the most scrap cost" would be that ratio, read back. This
  -- column demonstrates the calculation. It supports no finding.
  b.scrap_units * p.unit_cost_eur                          AS scrap_cost_eur

FROM `bakery_synthetic.fact_production_batch` b
JOIN `bakery_synthetic.dim_product` p USING (product_id)
JOIN `bakery_synthetic.dim_machine` m ON m.machine_id = b.machine_id
LEFT JOIN logged_stops s USING (batch_id);


-- =============================================================================
-- v_oee_daily — OEE by machine and day. Aggregated on the time basis, so
-- A x P x Q still reconciles to OEE.
-- =============================================================================
CREATE OR REPLACE VIEW `bakery_synthetic.v_oee_daily` AS
SELECT
  production_date,
  machine_id,
  machine_name,

  COUNT(*)                     AS batches,
  SUM(total_units)             AS total_units,
  SUM(good_units)              AS good_units,
  SUM(scrap_units)             AS scrap_units,
  ROUND(SUM(scrap_cost_eur), 2) AS scrap_cost_eur,

  ROUND(SUM(planned_hours), 2)     AS planned_hours,
  ROUND(SUM(run_hours), 2)         AS run_hours,
  ROUND(SUM(logged_stop_hours), 2) AS logged_stop_hours,

  ROUND(SAFE_DIVIDE(SUM(run_hours),        SUM(planned_hours)), 4) AS availability,
  ROUND(SAFE_DIVIDE(SUM(earned_hours),     SUM(run_hours)),     4) AS performance,
  ROUND(SAFE_DIVIDE(SUM(good_earned_hours),SUM(earned_hours)),  4) AS quality,
  ROUND(SAFE_DIVIDE(SUM(good_earned_hours),SUM(planned_hours)), 4) AS oee

FROM `bakery_synthetic.v_batch_oee`
GROUP BY production_date, machine_id, machine_name;


-- =============================================================================
-- v_scrap_by_product — where the yield loss sits.
-- =============================================================================
CREATE OR REPLACE VIEW `bakery_synthetic.v_scrap_by_product` AS
SELECT
  product_id,
  product_name,
  product_category,
  machine_name,

  COUNT(*)         AS batches,
  SUM(total_units) AS total_units,
  SUM(scrap_units) AS scrap_units,
  ROUND(SAFE_DIVIDE(SUM(scrap_units), SUM(total_units)), 4) AS scrap_rate,
  ROUND(SUM(scrap_cost_eur), 2)                             AS scrap_cost_eur,

  -- Scrap RATE and scrap COST rank differently, and that gap is the point of
  -- costing scrap at all. A high-rate cheap product can matter less than a
  -- low-rate expensive one. Which one a plant chases is a business decision,
  -- not a statistical one.
  ROUND(SAFE_DIVIDE(SUM(scrap_cost_eur), SUM(total_units)), 4) AS scrap_cost_per_unit_produced

FROM `bakery_synthetic.v_batch_oee`
GROUP BY product_id, product_name, product_category, machine_name;


-- =============================================================================
-- v_downtime_pareto — WHAT A REAL ANALYST WOULD SEE.
-- Reported codes only. Logged rows only. No access to the truth.
-- This is the view you would actually build in a plant, and it is the one that
-- fails. See v_dq_reason_coding for why.
-- =============================================================================
CREATE OR REPLACE VIEW `bakery_synthetic.v_downtime_pareto` AS
WITH stops AS (
  SELECT
    d.machine_id,
    m.machine_name,
    d.reported_reason_code AS reason_code,
    d.reported_reason_label AS reason_label,
    d.duration_minutes
  FROM `bakery_synthetic.fact_downtime` d
  JOIN `bakery_synthetic.dim_machine` m USING (machine_id)
  WHERE d.was_logged
)
SELECT
  machine_id,
  machine_name,
  reason_code,
  reason_label,
  COUNT(*)                              AS events,
  ROUND(SUM(duration_minutes) / 60.0, 2) AS stop_hours,
  ROUND(SUM(duration_minutes) / SUM(SUM(duration_minutes)) OVER (PARTITION BY machine_id), 4)
                                        AS share_of_machine_stop_time,
  ROUND(SUM(SUM(duration_minutes)) OVER (
          PARTITION BY machine_id ORDER BY SUM(duration_minutes) DESC
        ) / SUM(SUM(duration_minutes)) OVER (PARTITION BY machine_id), 4)
                                        AS cumulative_share
FROM stops
GROUP BY machine_id, machine_name, reason_code, reason_label;


-- =============================================================================
-- v_dq_reason_coding — THE PATHOLOGY, MEASURED.
--
-- Compares what the operator reported against what actually happened. This view
-- CANNOT EXIST IN A REAL PLANT: there is only one reason code, and no record of
-- what it should have been. That is precisely why the problem is invisible from
-- inside real data, and why an analyst has to reason about it rather than query
-- it.
--
-- Here the generator knows the truth, so the distortion can be MEASURED instead
-- of asserted. That is the whole reason the synthetic layer earns its place.
-- =============================================================================
CREATE OR REPLACE VIEW `bakery_synthetic.v_dq_reason_coding` AS
WITH reported AS (
  SELECT reported_reason_code AS code,
         SUM(duration_minutes) AS reported_minutes
  FROM `bakery_synthetic.fact_downtime`
  WHERE was_logged                       -- what the analyst can see
  GROUP BY code
),
truth AS (
  SELECT true_reason_code AS code,
         SUM(duration_minutes) AS true_minutes
  FROM `bakery_synthetic.fact_downtime`  -- everything, logged or not
  GROUP BY code
)
SELECT
  COALESCE(r.code, t.code) AS reason_code,
  ROUND(COALESCE(t.true_minutes, 0) / 60.0, 1)     AS true_stop_hours,
  ROUND(COALESCE(r.reported_minutes, 0) / 60.0, 1) AS reported_stop_hours,

  ROUND(SAFE_DIVIDE(t.true_minutes,     SUM(t.true_minutes)     OVER ()), 4) AS true_share,
  ROUND(SAFE_DIVIDE(r.reported_minutes, SUM(r.reported_minutes) OVER ()), 4) AS reported_share,

  -- Negative = this cause is UNDERSTATED in the data a plant actually holds.
  -- Changeover is the big loser: it is mostly short stops, and short stops are
  -- exactly the ones that get dumped into the catch-all. So the single biggest
  -- lever on this line is the one its own downtime report hides.
  ROUND(
    SAFE_DIVIDE(r.reported_minutes, SUM(r.reported_minutes) OVER ())
    - SAFE_DIVIDE(t.true_minutes,   SUM(t.true_minutes)     OVER ()), 4
  ) AS share_distortion

FROM truth t
FULL OUTER JOIN reported r USING (code);


-- =============================================================================
-- v_dq_unaccounted_time — the second half of the pathology.
--
-- The machine was not running for (planned - run) minutes. The operator logged
-- stops totalling something less than that. The gap is time nobody recorded:
-- micro-stops too short for anyone to bother entering on the terminal.
--
-- This one an analyst CAN build in a real plant — machine counters versus the
-- operator log — and it is the check that catches an Availability figure that
-- looks better than the line really is. Distrust the data first.
-- =============================================================================
CREATE OR REPLACE VIEW `bakery_synthetic.v_dq_unaccounted_time` AS
SELECT
  machine_id,
  machine_name,

  ROUND(SUM(planned_hours - run_hours), 1)                    AS true_stop_hours,
  ROUND(SUM(logged_stop_hours), 1)                            AS logged_stop_hours,
  ROUND(SUM(planned_hours - run_hours)
        - SUM(logged_stop_hours), 1)                          AS unaccounted_hours,

  ROUND(1 - SAFE_DIVIDE(
          SUM(logged_stop_hours),
          SUM(planned_hours - run_hours)
        ), 4) AS unaccounted_share_of_stop_time,

  -- What Availability looks like if you trust the operator log, versus what the
  -- machine actually did. The first number is the one on the dashboard.
  ROUND(SAFE_DIVIDE(SUM(planned_hours) - SUM(logged_stop_hours),
                    SUM(planned_hours)), 4)          AS availability_from_operator_log,
  ROUND(SAFE_DIVIDE(SUM(run_hours), SUM(planned_hours)), 4) AS availability_actual

FROM `bakery_synthetic.v_batch_oee`
GROUP BY machine_id, machine_name;
