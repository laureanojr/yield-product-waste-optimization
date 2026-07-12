-- =============================================================================
-- 06_author_product_standards.sql
-- Authors machine_id, unit_cost_eur, ideal_units_per_hr on dim_product
--
-- -----------------------------------------------------------------------------
-- WHAT IS REAL, WHAT IS REMEMBERED, WHAT IS DECLARED
-- -----------------------------------------------------------------------------
-- REAL       : median observed selling price per product (from the POS layer)
-- REAL       : v1_total_units, already on the table (reference outlet demand)
-- REMEMBERED : bake times, and the deck/tray load densities and handling
--              allowances in dim_machine — from nine years in industrial food
--              production, including production-oven work.
-- DECLARED   : the plant itself. No equipment data exists in the source
--              dataset, so the plant is an assumption, stated openly.
-- FABRICATED : the category cost ratios.
--
-- -----------------------------------------------------------------------------
-- ideal_units_per_hr — definition and derivation
-- -----------------------------------------------------------------------------
-- DEFINITION: nominal bake-cell capacity — theoretical maximum finished units
-- per hour OF RUN TIME, at full load, no changeover, no downtime.
--
-- Finishing and labour stations are NOT modelled. Hand-finished products
-- (eclair, tartelette, almond products) will therefore show lower Performance
-- against an oven-based standard. Stated simplification, not a bug.
--
-- DERIVATION:  ideal_units_per_hr = units_per_full_load x (60 / cycle_minutes)
--              cycle_minutes      = bake_minutes + machine handling_minutes
--
-- Equipment basis (dim_machine):
--   Deck oven : 3 decks, 120 x 160 cm surface, 30 baguettes per deck laid
--               width-wise at ~5 cm pitch (piece + 2-3 cm airflow gap).
--               = 90 per full load. 6 min handling for all three decks.
--   Rack oven : 18 trays (600 x 400 mm, ~85 mm spacing), 16 croissants per
--               tray (4 x 4, 70 g standard retail size) = 288 per full rack.
--               2 min handling — a trolley swap, door-open to door-closed.
--
-- The airflow gap is why load density is what it is: pack baguettes tighter and
-- the side crust never sets. That constraint is a real one, and it is the same
-- reason the tray layouts below are 4 x 4 rather than 5 x 5.
--
-- Load sizes for every other product derive from FOOTPRINT relative to the
-- reference product on its machine, expressed as whole pieces per deck or per
-- tray, because ovens hold whole pieces.
--
-- SANDWICH COMPLET has no oven. Rate = 3600 / assembly_seconds_per_unit.
--
-- -----------------------------------------------------------------------------
-- unit_cost_eur — definition and simplification
-- -----------------------------------------------------------------------------
-- DEFINITION: full standard cost per unit (materials + conversion), used to
-- value scrap.
--
-- SIMPLIFICATION: all scrap valued at full standard cost regardless of the
-- stage at which it was rejected. A real plant values scrap at cost accumulated
-- to the point of rejection — dough dumped at proofing is cheap, a loaf pulled
-- after the bake carries the full oven cost. Modelling that needs a multi-stage
-- process this five-table schema does not have.
--
-- DERIVED AS: real median selling price x a FABRICATED category cost ratio.
--
-- CIRCULARITY WARNING: the ratios are invented. Any statement of the form
-- "category X carries the most scrap cost" is those ratios read back. Cost is a
-- scaling constant. It supports no finding.
--
-- IMPORTANT: set query processing location to EU before running.
-- =============================================================================

ALTER TABLE `bakery_synthetic.dim_product`
  ADD COLUMN IF NOT EXISTS machine_id INT64;

-- The generator needs batch size and process time to size a batch and compute
-- its cycle. They belong here, on the product master — a real ERP product
-- master carries standard batch size and standard process time. Keeping them in
-- the table (rather than only in this script) means the generator holds NO
-- hardcoded product data and cannot drift from the dimension.
ALTER TABLE `bakery_synthetic.dim_product`
  ADD COLUMN IF NOT EXISTS units_per_full_load INT64;

ALTER TABLE `bakery_synthetic.dim_product`
  ADD COLUMN IF NOT EXISTS bake_minutes FLOAT64;

BEGIN TRANSACTION;

MERGE `bakery_synthetic.dim_product` AS target
USING (

  WITH
  -- Real median observed selling price, taken across sales LINES (unweighted by
  -- quantity) so it lands on the modal price period rather than being dragged by
  -- volume. Exact median, not APPROX_QUANTILES: the table is small and a
  -- portfolio project should not ship an approximation it does not need.
  median_prices AS (
    SELECT DISTINCT
      product AS product_name,
      PERCENTILE_CONT(unit_price, 0.5) OVER (PARTITION BY product) AS median_unit_price_eur
    FROM `bakery.v_sales`
    WHERE quantity > 0 AND unit_price > 0
  ),

  -- units_per_full_load = whole pieces per deck x 3, or per tray x 18.
  operating_standards AS (
    SELECT * FROM UNNEST([

      -- ==== Deck Oven Line (machine 1) — bread ==============================
      -- reference: 30 baguettes per deck x 3 decks = 90 per full load
      STRUCT(
        'TRADITIONAL BAGUETTE' AS product_name,
        1                      AS machine_id,
        30                     AS pieces_per_deck_or_tray,
        90                     AS units_per_full_load,
        24.0                   AS bake_minutes,
        CAST(NULL AS FLOAT64)  AS assembly_seconds_per_unit
      ),
      STRUCT('BAGUETTE',            1, 30,  90, 24.0, CAST(NULL AS FLOAT64)),
      STRUCT('BANETTE',             1, 30,  90, 24.0, CAST(NULL AS FLOAT64)),
      -- heavier cereal dough, longer bake, same stick format
      STRUCT('CEREAL BAGUETTE',     1, 30,  90, 26.0, CAST(NULL AS FLOAT64)),
      -- thinner than a baguette: tighter pitch, more rows across the deck
      STRUCT('FICELLE',             1, 39, 117, 22.0, CAST(NULL AS FLOAT64)),
      STRUCT('BANETTINE',           1, 36, 108, 22.0, CAST(NULL AS FLOAT64)),
      -- round loaves use deck width poorly and need expansion room
      STRUCT('BOULE 200G',          1, 18,  54, 28.0, CAST(NULL AS FLOAT64)),
      STRUCT('BOULE 400G',          1, 12,  36, 35.0, CAST(NULL AS FLOAT64)),
      STRUCT('PAIN',                1, 15,  45, 32.0, CAST(NULL AS FLOAT64)),
      STRUCT('PAIN BANETTE',        1, 15,  45, 32.0, CAST(NULL AS FLOAT64)),
      -- QUIM BREAD: reclassified from specialty loaf to standard loaf on PRICE
      -- EVIDENCE. The name gives nothing away, so it was first grouped with the
      -- other unclear names. But its real median selling price is ~EUR 1.00 --
      -- baguette money, less than half what SPECIAL BREAD (~2.40) and VIK BREAD
      -- (~2.50) fetch. A EUR 1.00 product that bakes 40 minutes at a third of
      -- baguette load density does not hold together. The process assumption was
      -- checked against real price behaviour and lost. Same method that caught
      -- COUPE: judge a product by how it behaves, not by what it is called.
      STRUCT('QUIM BREAD',          1, 15,  45, 32.0, CAST(NULL AS FLOAT64)),
      STRUCT('CAMPAGNE',            1,  9,  27, 42.0, CAST(NULL AS FLOAT64)),
      -- wholemeal and seeded doughs bake long
      STRUCT('COMPLET',             1,  9,  27, 42.0, CAST(NULL AS FLOAT64)),
      STRUCT('MOISSON',             1,  9,  27, 42.0, CAST(NULL AS FLOAT64)),
      -- names give limited detail, but real median prices (~EUR 2.40 and 2.50)
      -- are consistent with specialty loaves — the grouping survives the same
      -- price check that QUIM BREAD failed.
      STRUCT('SPECIAL BREAD',       1,  9,  27, 40.0, CAST(NULL AS FLOAT64)),
      STRUCT('VIK BREAD',           1,  9,  27, 40.0, CAST(NULL AS FLOAT64)),

      -- ==== Rack Oven Line (machine 2) — viennoiserie and patisserie ========
      -- reference: 16 croissants per tray (4 x 4, 70 g) x 18 trays = 288
      STRUCT('CROISSANT',           2, 16, 288, 18.0, CAST(NULL AS FLOAT64)),
      -- wider rectangular footprint: 4 x 3
      STRUCT('PAIN AU CHOCOLAT',    2, 12, 216, 19.0, CAST(NULL AS FLOAT64)),
      STRUCT('PAIN AUX RAISINS',    2, 12, 216, 20.0, CAST(NULL AS FLOAT64)),
      STRUCT('CROISSANT AMANDES',   2, 12, 216, 20.0, CAST(NULL AS FLOAT64)),
      STRUCT('PAIN CHOCO AMANDES',  2, 12, 216, 20.0, CAST(NULL AS FLOAT64)),
      -- dense, buttery, individual forms; long bake
      STRUCT('KOUIGN AMANN',        2, 12, 216, 24.0, CAST(NULL AS FLOAT64)),
      -- large semicircle, generous spacing: 4 x 2
      STRUCT('CHAUSSON AUX POMMES', 2,  8, 144, 22.0, CAST(NULL AS FLOAT64)),
      -- small, flat, high tray density, short bake: 6 x 4
      STRUCT('COOKIE',              2, 24, 432, 13.0, CAST(NULL AS FLOAT64)),
      STRUCT('TARTELETTE',          2, 12, 216, 20.0, CAST(NULL AS FLOAT64)),
      -- narrow rectangular footprint: 5 x 4
      STRUCT('ECLAIR',              2, 20, 360, 29.0, CAST(NULL AS FLOAT64)),

      -- ==== Assembly Bench (machine 3) — no oven model =======================
      STRUCT('SANDWICH COMPLET',    3, CAST(NULL AS INT64), CAST(NULL AS INT64),
                                       CAST(NULL AS FLOAT64), 60.0)
    ])
  ),

  calculated_standards AS (
    SELECT
      d.product_name,
      o.machine_id,
      o.units_per_full_load,
      o.bake_minutes,

      -- full standard cost = real median price x fabricated category ratio
      CAST(
        ROUND(
          mp.median_unit_price_eur *
          CASE d.product_category
            WHEN 'bread'        THEN 0.30
            WHEN 'viennoiserie' THEN 0.36
            WHEN 'patisserie'   THEN 0.40
            WHEN 'sandwich'     THEN 0.45
          END,
        2)
      AS NUMERIC) AS unit_cost_eur,

      -- The arithmetic is visible on purpose. Every value in this column can be
      -- defended from six equipment numbers and one bake time. Change an input
      -- and every affected rate recomputes.
      ROUND(
        CASE
          WHEN o.assembly_seconds_per_unit IS NOT NULL
            THEN 3600.0 / o.assembly_seconds_per_unit
          ELSE o.units_per_full_load * (60.0 / (o.bake_minutes + m.handling_minutes))
        END,
      2) AS ideal_units_per_hr

    FROM `bakery_synthetic.dim_product` AS d
    JOIN operating_standards            AS o  ON o.product_name  = d.product_name
    JOIN median_prices                  AS mp ON mp.product_name = d.product_name
    JOIN `bakery_synthetic.dim_machine` AS m  ON m.machine_id    = o.machine_id
  )

  SELECT * FROM calculated_standards

) AS source
ON target.product_name = source.product_name
WHEN MATCHED THEN UPDATE SET
  machine_id          = source.machine_id,
  units_per_full_load = source.units_per_full_load,
  bake_minutes        = source.bake_minutes,
  unit_cost_eur       = source.unit_cost_eur,
  ideal_units_per_hr  = source.ideal_units_per_hr;

-- -----------------------------------------------------------------------------
-- Validation — fail loudly, roll back on failure
-- -----------------------------------------------------------------------------

ASSERT (SELECT COUNT(*) FROM `bakery_synthetic.dim_product`) = 27
  AS 'Validation failed: dim_product must contain exactly 27 products.';

ASSERT (
  SELECT COUNT(*) FROM `bakery_synthetic.dim_product`
  WHERE machine_id IS NULL OR unit_cost_eur IS NULL OR ideal_units_per_hr IS NULL
) = 0
  AS 'Validation failed: every product must have a machine and both standards.';

ASSERT (
  SELECT COUNT(*) FROM `bakery_synthetic.dim_product`
  WHERE unit_cost_eur <= 0 OR ideal_units_per_hr <= 0
) = 0
  AS 'Validation failed: standards must be strictly positive.';

-- Routing must agree with process classification.
ASSERT (
  SELECT COUNT(*) FROM `bakery_synthetic.dim_product`
  WHERE NOT (
       (product_category = 'bread'                        AND machine_id = 1)
    OR (product_category IN ('viennoiserie','patisserie') AND machine_id = 2)
    OR (product_category = 'sandwich'                     AND machine_id = 3)
  )
) = 0
  AS 'Validation failed: product routing disagrees with product category.';

ASSERT (
  SELECT COUNT(*) FROM `bakery_synthetic.dim_product` WHERE machine_id = 3
) = 1
  AS 'Validation failed: the assembly bench must carry exactly one product.';

-- Every baked product must carry a load size and a bake time, or the generator
-- cannot size its batches. The assembly bench is the only permitted exception.
ASSERT (
  SELECT COUNT(*) FROM `bakery_synthetic.dim_product`
  WHERE process_type = 'baked'
    AND (units_per_full_load IS NULL OR bake_minutes IS NULL)
) = 0
  AS 'Validation failed: every baked product needs units_per_full_load and bake_minutes.';

-- The rate on the table must equal the rate its own inputs imply. If this ever
-- fails, someone has hand-edited a rate instead of changing an input.
ASSERT (
  SELECT COUNT(*)
  FROM `bakery_synthetic.dim_product` p
  JOIN `bakery_synthetic.dim_machine` m USING (machine_id)
  WHERE p.process_type = 'baked'
    AND ABS(
          p.ideal_units_per_hr
          - ROUND(p.units_per_full_load * (60.0 / (p.bake_minutes + m.handling_minutes)), 2)
        ) > 0.01
) = 0
  AS 'Validation failed: ideal_units_per_hr does not reconcile with its own load and cycle inputs.';

-- The rack oven must out-produce the deck oven per hour: 18 trays and a
-- 2-minute trolley swap against 3 decks and a 6-minute manual reload. If this
-- ever inverts, the handling model has been mis-entered.
ASSERT (
  SELECT
    (SELECT MAX(ideal_units_per_hr) FROM `bakery_synthetic.dim_product` WHERE machine_id = 2)
    > (SELECT MAX(ideal_units_per_hr) FROM `bakery_synthetic.dim_product` WHERE machine_id = 1)
)
  AS 'Validation failed: rack-oven peak rate must exceed deck-oven peak rate.';

COMMIT TRANSACTION;

-- -----------------------------------------------------------------------------
-- Review
-- -----------------------------------------------------------------------------
SELECT
  p.product_id,
  p.product_name,
  p.product_category,
  p.process_type,
  m.machine_name,
  p.units_per_full_load,
  p.bake_minutes,
  m.handling_minutes,
  p.unit_cost_eur,
  p.ideal_units_per_hr,
  p.v1_total_units
FROM `bakery_synthetic.dim_product` AS p
JOIN `bakery_synthetic.dim_machine` AS m USING (machine_id)
ORDER BY p.machine_id, p.ideal_units_per_hr DESC;
