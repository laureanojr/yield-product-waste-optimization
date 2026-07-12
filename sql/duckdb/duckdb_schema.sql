-- Schema for the whole project. Runs on DuckDB, no cloud account needed.
-- Executed by scripts/build_duckdb.py.
--
-- The BigQuery version of this is in sql/synthetic/ — that's where it was built.
-- This port exists so the repo can actually be run by anyone who clones it.


-- ---------------------------------------------------------------------------
-- Real layer: the cleaned POS export.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_sales AS
SELECT
  article    AS product,
  date       AS sale_date,
  "Quantity" AS quantity,
  unit_price,
  revenue
FROM read_csv(
  'data/cleaned/bakery_sales_clean.csv',
  header = true,
  -- Quote char must be explicit. Auto-detection guesses "no quoting" and then
  -- trips on rows like:  ...,"PLATPREPARE6,50",2.0,6.5,...
  -- That's a product name with a price and a decimal comma inside it. Same
  -- species as COUPE below: the till gets used for things that aren't products.
  quote = '"',
  types = {
    'date':       'DATE',
    'article':    'VARCHAR',
    'Quantity':   'DOUBLE',
    'unit_price': 'DOUBLE',
    'revenue':    'DOUBLE'
  }
);


-- ---------------------------------------------------------------------------
-- dim_product — 27 products: top 30 by real units, minus three that sell
-- through the till but aren't manufactured.
--
--   CAFE OU EAU       a drink
--   FORMULE SANDWICH  a meal-deal bundle, not a made item
--   COUPE             flat €0.15 across 20,386 sales and 21 months, zero price
--                     variation, while every real product repriced twice. An
--                     ancillary charge. Found by a price-invariance audit.
--
-- v1_total_units is the only real value in this table.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE dim_product AS
WITH real_units AS (
  SELECT product AS product_name, SUM(quantity) AS v1_total_units
  FROM v_sales
  WHERE quantity > 0
  GROUP BY product
),
top30 AS (
  SELECT * FROM real_units ORDER BY v1_total_units DESC LIMIT 30
),
manufactured AS (
  SELECT * FROM top30
  WHERE product_name NOT IN ('CAFE OU EAU', 'FORMULE SANDWICH', 'COUPE')
),
classified AS (
  -- Classified by process, not by how a shop displays them: kouign amann and
  -- chausson are laminated dough, so viennoiserie.
  SELECT
    product_name,
    v1_total_units,
    CASE
      WHEN product_name IN (
        'CROISSANT','PAIN AU CHOCOLAT','PAIN AUX RAISINS','CROISSANT AMANDES',
        'PAIN CHOCO AMANDES','KOUIGN AMANN','CHAUSSON AUX POMMES'
      ) THEN 'viennoiserie'
      WHEN product_name IN ('COOKIE','TARTELETTE','ECLAIR') THEN 'patisserie'
      WHEN product_name = 'SANDWICH COMPLET' THEN 'sandwich'
      ELSE 'bread'
    END AS product_category,
    CASE WHEN product_name = 'SANDWICH COMPLET' THEN 'assembled' ELSE 'baked' END
      AS process_type
  FROM manufactured
)
SELECT
  CAST(ROW_NUMBER() OVER (ORDER BY v1_total_units DESC) AS INTEGER) AS product_id,
  product_name,
  product_category,
  process_type,
  CAST(NULL AS INTEGER)      AS machine_id,
  CAST(NULL AS INTEGER)      AS units_per_full_load,
  CAST(NULL AS DOUBLE)       AS bake_minutes,
  CAST(NULL AS DECIMAL(8,2)) AS unit_cost_eur,
  CAST(NULL AS DOUBLE)       AS ideal_units_per_hr,
  CAST(v1_total_units AS INTEGER) AS v1_total_units
FROM classified;


-- ---------------------------------------------------------------------------
-- dim_machine — an assumed plant. No equipment data exists in the source, so
-- these are declared: a small production bakery, three resources, fixed
-- routing, manual handling.
--
-- base_failure_rate_per_hr drives unplanned breakdowns. It is NOT the main
-- driver of Availability in the output — changeover frequency is. See the
-- limitations section of docs/synthetic_layer_scope.md.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE dim_machine (
  machine_id               INTEGER PRIMARY KEY,
  machine_name             VARCHAR NOT NULL,
  machine_type             VARCHAR NOT NULL,
  install_year             INTEGER,
  capacity_units           VARCHAR,
  full_load_reference      VARCHAR,
  handling_minutes         DOUBLE,   -- load/unload, added to bake time per cycle
  base_failure_rate_per_hr DOUBLE
);

INSERT INTO dim_machine VALUES
  (1, 'Deck Oven Line', 'deck_oven', 2012,
      '3 decks (120 x 160 cm); a batch takes the decks it needs',
      '30 baguettes per deck = 90 per full load',
      6.0, 0.045),
  (2, 'Rack Oven Line', 'rack_oven', 2019,
      '18 trays (600 x 400 mm); a batch takes the trays it needs',
      '16 croissants per tray (4 x 4, 70 g) = 288 per full rack',
      2.0, 0.020),
  (3, 'Assembly Bench', 'manual_assembly', 2019,
      'manual station, no oven',
      '60 seconds per sandwich = 60 units/hr',
      0.0, 0.005);


-- ---------------------------------------------------------------------------
-- Product standards.
--
--   ideal_units_per_hr = units_per_full_load x (60 / (bake_minutes + handling))
--
-- This is bake-cell capacity: max units per hour of run time, full load, no
-- changeover, no downtime. Finishing and labour stations aren't modelled, so
-- hand-finished products show lower Performance against an oven-based standard.
--
-- Every rate derives from six equipment numbers and a bake time. The bake times
-- are the only part I'd defend from experience; the equipment is assumed.
--
-- unit_cost_eur = real median selling price x a fabricated category ratio.
-- The ratios are invented, so nothing about relative scrap cost is a finding.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TEMP TABLE operating_standards (
  product_name        VARCHAR,
  machine_id          INTEGER,
  units_per_full_load INTEGER,
  bake_minutes        DOUBLE,
  assembly_seconds    DOUBLE
);

INSERT INTO operating_standards VALUES
  -- Deck oven: 30 baguettes/deck x 3 decks = 90 per full load
  ('TRADITIONAL BAGUETTE', 1,  90, 24.0, NULL),
  ('BAGUETTE',             1,  90, 24.0, NULL),
  ('BANETTE',              1,  90, 24.0, NULL),
  ('CEREAL BAGUETTE',      1,  90, 26.0, NULL),
  ('FICELLE',              1, 117, 22.0, NULL),   -- thinner, tighter pitch
  ('BANETTINE',            1, 108, 22.0, NULL),
  ('BOULE 200G',           1,  54, 28.0, NULL),   -- round loaves waste deck width
  ('BOULE 400G',           1,  36, 35.0, NULL),
  ('PAIN',                 1,  45, 32.0, NULL),
  ('PAIN BANETTE',         1,  45, 32.0, NULL),
  -- QUIM BREAD: grouped with the specialty loaves at first, on the name alone.
  -- Its real median price is ~€1.00 against ~€2.40 and ~€2.50 for SPECIAL BREAD
  -- and VIK BREAD. A €1 product doesn't bake for 40 minutes at a third of
  -- baguette density. Moved to standard loaf.
  ('QUIM BREAD',           1,  45, 32.0, NULL),
  ('CAMPAGNE',             1,  27, 42.0, NULL),
  ('COMPLET',              1,  27, 42.0, NULL),
  ('MOISSON',              1,  27, 42.0, NULL),
  ('SPECIAL BREAD',        1,  27, 40.0, NULL),
  ('VIK BREAD',            1,  27, 40.0, NULL),
  -- Rack oven: 16 croissants/tray x 18 trays = 288 per full rack
  ('CROISSANT',            2, 288, 18.0, NULL),
  ('PAIN AU CHOCOLAT',     2, 216, 19.0, NULL),
  ('PAIN AUX RAISINS',     2, 216, 20.0, NULL),
  ('CROISSANT AMANDES',    2, 216, 20.0, NULL),
  ('PAIN CHOCO AMANDES',   2, 216, 20.0, NULL),
  ('KOUIGN AMANN',         2, 216, 24.0, NULL),
  ('CHAUSSON AUX POMMES',  2, 144, 22.0, NULL),   -- large, needs spacing
  ('COOKIE',               2, 432, 13.0, NULL),
  ('TARTELETTE',           2, 216, 20.0, NULL),
  ('ECLAIR',               2, 360, 29.0, NULL),
  ('SANDWICH COMPLET',     3, NULL, NULL, 60.0);

-- Median across sales lines, not weighted by quantity, so it lands on the modal
-- price rather than being dragged by volume.
CREATE OR REPLACE TEMP TABLE median_prices AS
SELECT product AS product_name, median(unit_price) AS median_unit_price_eur
FROM v_sales
WHERE quantity > 0 AND unit_price > 0
GROUP BY product;

UPDATE dim_product AS d
SET machine_id          = o.machine_id,
    units_per_full_load = o.units_per_full_load,
    bake_minutes        = o.bake_minutes,
    unit_cost_eur       = CAST(ROUND(
      mp.median_unit_price_eur *
      CASE d.product_category
        WHEN 'bread'        THEN 0.30
        WHEN 'viennoiserie' THEN 0.36
        WHEN 'patisserie'   THEN 0.40
        WHEN 'sandwich'     THEN 0.45
      END, 2) AS DECIMAL(8,2)),
    ideal_units_per_hr  = ROUND(
      CASE
        WHEN o.assembly_seconds IS NOT NULL THEN 3600.0 / o.assembly_seconds
        ELSE o.units_per_full_load * (60.0 / (o.bake_minutes + m.handling_minutes))
      END, 2)
FROM operating_standards o, median_prices mp, dim_machine m
WHERE o.product_name  = d.product_name
  AND mp.product_name = d.product_name
  AND m.machine_id    = o.machine_id;


-- ---------------------------------------------------------------------------
-- Fact tables. Raw events only — no yield, waste or OEE columns anywhere.
-- Everything derives in duckdb_views.sql.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE fact_production_batch (
  batch_id                   VARCHAR   NOT NULL,
  production_date            DATE      NOT NULL,
  product_id                 INTEGER   NOT NULL,
  machine_id                 INTEGER   NOT NULL,
  planned_units              INTEGER   NOT NULL,
  loads_used                 DOUBLE    NOT NULL,   -- decks or trays, fractional
  scheduled_start_ts         TIMESTAMP NOT NULL,
  scheduled_end_ts           TIMESTAMP NOT NULL,
  -- Denominator of Availability. Scheduled BATCH time, not shift length: a batch
  -- given 40 minutes that lost 8 to a breakdown ran at 80%. Shift length would
  -- make Availability a measure of how idle the plant was.
  planned_production_minutes DOUBLE    NOT NULL,
  actual_start_ts            TIMESTAMP NOT NULL,
  actual_end_ts              TIMESTAMP NOT NULL,
  -- The machine's own counter. Stop time isn't stored here; it lives as
  -- intervals in fact_downtime and gets summed in SQL.
  run_time_minutes           DOUBLE    NOT NULL,
  good_units                 INTEGER   NOT NULL,
  scrap_units                INTEGER   NOT NULL
);

CREATE OR REPLACE TABLE fact_downtime (
  downtime_id           VARCHAR   NOT NULL,
  batch_id              VARCHAR   NOT NULL,
  machine_id            INTEGER   NOT NULL,
  production_date       DATE      NOT NULL,
  start_ts              TIMESTAMP NOT NULL,
  end_ts                TIMESTAMP NOT NULL,
  -- What the machine's counter says.
  duration_minutes           DOUBLE NOT NULL,
  -- What went on the form. Operators type round numbers — real downtime logs
  -- heap on 5, 10, 15, 30 minutes. Nobody enters "11.97". This is the column an
  -- analyst actually has.
  reported_duration_minutes  DOUBLE NOT NULL,
  -- What the operator pressed. The only code a real analyst has.
  reported_reason_code  VARCHAR   NOT NULL,
  reported_reason_label VARCHAR   NOT NULL,
  -- What actually happened. Doesn't exist in a real MES; here so the
  -- data-quality views can measure the gap instead of arguing about it.
  true_reason_code      VARCHAR   NOT NULL,
  true_reason_label     VARCHAR   NOT NULL,
  -- FALSE = never made it onto the terminal at all.
  was_logged            BOOLEAN   NOT NULL
);

CREATE OR REPLACE TABLE fact_quality_inspection (
  inspection_id   VARCHAR   NOT NULL,
  batch_id        VARCHAR   NOT NULL,
  production_date DATE      NOT NULL,
  inspection_ts   TIMESTAMP NOT NULL,
  -- Sampled, not census. This table does not feed the Quality term of OEE —
  -- that comes from good/scrap on every batch. This is a separate signal about
  -- whether defects were caught.
  sample_size     INTEGER   NOT NULL,
  defects_found   INTEGER   NOT NULL,
  outcome         VARCHAR   NOT NULL,
  defect_type     VARCHAR
);
