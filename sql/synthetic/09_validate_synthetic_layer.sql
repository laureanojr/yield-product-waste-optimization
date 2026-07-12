-- =============================================================================
-- 09_validate_synthetic_layer.sql
-- Run this after every regeneration. It fails loudly.
--
-- These are the checks that would catch a broken layer BEFORE it reaches a
-- dashboard or an interview. If one of them fires, something upstream is wrong
-- and no number in the project can be trusted until it is fixed.
--
-- IMPORTANT: set query processing location to EU before running.
-- =============================================================================


-- =============================================================================
-- 1. THE OEE IDENTITY
-- The one that matters. If Availability x Performance x Quality does not equal
-- OEE, the decomposition is decorative and every conclusion drawn from it is
-- worthless. This is the first thing a competent interviewer would test.
-- =============================================================================
ASSERT (
  SELECT COUNT(*)
  FROM `bakery_synthetic.v_batch_oee`
  WHERE ABS(availability * performance * quality - oee) > 1e-6
) = 0
  AS 'FAIL: OEE does not reconcile from A x P x Q at batch grain.';

-- And it must still hold after aggregation. Naive unit-based rollups break here
-- once products have different ideal rates — which is exactly why the views use
-- a time basis (earned hours) rather than raw units.
ASSERT (
  SELECT COUNT(*)
  FROM `bakery_synthetic.v_oee_daily`
  WHERE ABS(availability * performance * quality - oee) > 1e-3
) = 0
  AS 'FAIL: OEE does not reconcile after aggregation. The rollup is unit-based, not time-based.';


-- =============================================================================
-- 2. PERFORMANCE CANNOT EXCEED 100%
-- A plant producing faster than its own theoretical maximum is a plant with a
-- broken standard. The generator asserts this too, before it writes anything —
-- belt and braces, because this bug is easy to reintroduce (rounding UP a small
-- batch is enough to do it).
-- =============================================================================
ASSERT (
  SELECT COUNT(*) FROM `bakery_synthetic.v_batch_oee` WHERE performance > 1.0
) = 0
  AS 'FAIL: OEE Performance exceeds 1.0. Actual output beat the theoretical ceiling.';

ASSERT (
  SELECT COUNT(*) FROM `bakery_synthetic.v_batch_oee`
  WHERE availability > 1.0 OR quality > 1.0
     OR availability <= 0  OR quality <= 0 OR performance <= 0
) = 0
  AS 'FAIL: an OEE term is outside (0, 1].';


-- =============================================================================
-- 3. TIME RECONCILES
-- Run time plus stop time must equal planned time. If they drift, the downtime
-- intervals and the batch record are telling different stories.
-- =============================================================================
ASSERT (
  SELECT COUNT(*)
  FROM (
    SELECT
      b.batch_id,
      b.planned_production_minutes - b.run_time_minutes AS gap_minutes,
      COALESCE(SUM(d.duration_minutes), 0)              AS stop_minutes
    FROM `bakery_synthetic.fact_production_batch` b
    LEFT JOIN `bakery_synthetic.fact_downtime` d USING (batch_id)
    GROUP BY b.batch_id, gap_minutes
  )
  WHERE ABS(gap_minutes - stop_minutes) > 0.05
) = 0
  AS 'FAIL: downtime intervals do not reconcile with planned minus run time.';

ASSERT (
  SELECT COUNT(*) FROM `bakery_synthetic.fact_production_batch`
  WHERE run_time_minutes <= 0
     OR run_time_minutes > planned_production_minutes + 1e-6
) = 0
  AS 'FAIL: run time is non-positive or exceeds planned production time.';


-- =============================================================================
-- 4. REFERENTIAL INTEGRITY
-- BigQuery does not enforce foreign keys. So we do.
-- =============================================================================
ASSERT (
  SELECT COUNT(*) FROM `bakery_synthetic.fact_production_batch` b
  LEFT JOIN `bakery_synthetic.dim_product` p USING (product_id)
  WHERE p.product_id IS NULL
) = 0
  AS 'FAIL: orphan batches — product_id not in dim_product.';

-- The batch says one machine, the product master says another. With fixed
-- routing these can never disagree, and this is the check that proves it.
ASSERT (
  SELECT COUNT(*) FROM `bakery_synthetic.fact_production_batch` b
  JOIN `bakery_synthetic.dim_product` p USING (product_id)
  WHERE b.machine_id != p.machine_id
) = 0
  AS 'FAIL: batch machine disagrees with the routing on dim_product.';

ASSERT (
  SELECT COUNT(*) FROM `bakery_synthetic.fact_downtime` d
  LEFT JOIN `bakery_synthetic.fact_production_batch` b USING (batch_id)
  WHERE b.batch_id IS NULL
) = 0
  AS 'FAIL: orphan downtime rows — batch_id not in fact_production_batch.';

ASSERT (
  SELECT COUNT(*) FROM `bakery_synthetic.fact_quality_inspection` i
  LEFT JOIN `bakery_synthetic.fact_production_batch` b USING (batch_id)
  WHERE b.batch_id IS NULL
) = 0
  AS 'FAIL: orphan inspections — batch_id not in fact_production_batch.';


-- =============================================================================
-- 5. THE CALENDAR
-- The plant runs Mon-Sat. Anything on a Sunday means the demand rollover in the
-- generator is broken.
-- =============================================================================
ASSERT (
  SELECT COUNT(*) FROM `bakery_synthetic.fact_production_batch`
  WHERE EXTRACT(DAYOFWEEK FROM production_date) = 1   -- BigQuery: 1 = Sunday
) = 0
  AS 'FAIL: production on a Sunday. The plant is closed.';


-- =============================================================================
-- 6. THE PATHOLOGY IS ACTUALLY PRESENT
-- If the generator ever stops injecting the distortion, the data-quality views
-- become a demonstration of nothing. These checks fail if the layer quietly
-- turns honest.
-- =============================================================================
ASSERT (
  SELECT COUNT(*) FROM `bakery_synthetic.fact_downtime`
  WHERE reported_reason_code = '99' AND true_reason_code = '99'
) = 0
  AS 'FAIL: a stop was genuinely caused by "Other". Nothing is. 99 is a reporting artefact only.';

-- Micro-stops must NEVER appear in the operator log. Not one.
ASSERT (
  SELECT COUNT(*) FROM `bakery_synthetic.fact_downtime`
  WHERE true_reason_code = '06' AND was_logged
) = 0
  AS 'FAIL: a micro-stop was logged. By construction they never reach a terminal.';

-- And the distortion must be material, or the layer proves nothing.
ASSERT (
  SELECT SAFE_DIVIDE(
    SUM(CASE WHEN reported_reason_code = '99' THEN duration_minutes END),
    SUM(duration_minutes)
  )
  FROM `bakery_synthetic.fact_downtime`
  WHERE was_logged
) > 0.15
  AS 'FAIL: the catch-all bucket is too small to demonstrate anything.';


-- =============================================================================
-- 7. THE REAL/SYNTHETIC BOUNDARY
-- v1_total_units is the ONLY real value in the synthetic layer. If a fact table
-- ever contained real data, or the dimension lost its anchor, the separation
-- this whole project rests on would be broken.
-- =============================================================================
ASSERT (
  SELECT COUNT(*) FROM `bakery_synthetic.dim_product`
  WHERE v1_total_units IS NULL OR v1_total_units <= 0
) = 0
  AS 'FAIL: dim_product lost its real demand anchor.';


-- =============================================================================
-- If every assertion above passed, the layer is internally consistent.
-- What it is NOT: true. Every pattern here is an assumption from
-- config/synthetic_generator.yaml, read back. See docs/synthetic_layer_scope.md.
-- =============================================================================
SELECT
  'All assertions passed.' AS status,
  (SELECT COUNT(*) FROM `bakery_synthetic.fact_production_batch`)   AS batches,
  (SELECT COUNT(*) FROM `bakery_synthetic.fact_downtime`)           AS downtime_events,
  (SELECT COUNT(*) FROM `bakery_synthetic.fact_quality_inspection`) AS inspections,
  (SELECT ROUND(AVG(oee), 4) FROM `bakery_synthetic.v_oee_daily`)   AS mean_daily_oee;
