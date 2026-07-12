-- =============================================================================
-- duckdb_schema.sql
-- The whole project, portable. No cloud account, no credentials, no billing.
--
-- WHY THIS EXISTS
-- The pipeline was built on BigQuery and the BigQuery scripts are still in
-- sql/synthetic/ — they ran, and they are the record of that work. But a repo
-- that needs a Google Cloud account to run is a repo nobody runs. This port
-- means: clone, pip install, execute. Everything, on a laptop, in seconds.
--
-- Reproducibility is a stated standard of this project. This is what it costs
-- to actually mean it.
--
-- Executed by scripts/build_duckdb.py — see that file for the run order.
-- =============================================================================


-- =============================================================================
-- REAL LAYER
-- The cleaned POS export. Column names are normalised here so that everything
-- downstream reads the same names it read on BigQuery.
-- =============================================================================
CREATE OR REPLACE VIEW v_sales AS
SELECT
  article           AS product,
  date              AS sale_date,
  "Quantity"        AS quantity,
  unit_price,
  revenue
FROM read_csv(
  'data/cleaned/bakery_sales_clean.csv',
  header = true,
  -- The quote character MUST be set explicitly. Auto-detection guesses "no
  -- quoting" and then trips over rows like:
  --
  --     2021-07-12,11:30,187296,"PLATPREPARE6,50",2.0,6.5,...
  --
  -- That is a product name with a PRICE inside it and a European decimal comma
  -- ("plat préparé 6,50"). It is the same species as COUPE: the till was used
  -- as a catch-all for things that are not manufactured products. It sits well
  -- outside the top 30 so it never reaches dim_product — but it is the reason
  -- this view cannot rely on a sniffer.
  quote = '"',
  types = {
    'date':          'DATE',
    'article':       'VARCHAR',
    'Quantity':      'DOUBLE',
    'unit_price':    'DOUBLE',
    'revenue':       'DOUBLE'
  }
);


-- =============================================================================
-- dim_product
--
-- 27 products: the top 30 by real units, minus three that sell through the till
-- but are not manufactured.
--
--   CAFE OU EAU       a drink.                     Excluded on category.
--   FORMULE SANDWICH  a POS meal-deal bundle.      Excluded on domain knowledge.
--   COUPE             EXCLUDED ON EVIDENCE. Flat EUR 0.15 across 20,386 sales
--                     and 21 months, zero price variation, while every genuine
--                     product repriced twice. An ancillary charge, not a baked
--                     good. Caught by a price-invariance audit, not by reading
--                     the name.
--
-- v1_total_units is the ONLY real value in this table — the demand anchor. Real
-- data informs the shape of the simulation, never its contents.
-- =============================================================================
CREATE OR REPLACE TABLE dim_product AS
WITH real_units AS (
  SELECT product AS product_name, SUM(quantity) AS v1_total_units
  FROM v_sales
  WHERE quantity > 0
  GROUP BY product
),
top30 AS (
  SELECT * FROM real_units
  ORDER BY v1_total_units DESC
  LIMIT 30
),
manufactured AS (
  SELECT * FROM top30
  WHERE product_name NOT IN ('CAFE OU EAU', 'FORMULE SANDWICH', 'COUPE')
),
-- Classification rule: PROCESS BEATS MERCHANDISING. Kouign amann and chausson
-- aux pommes are laminated dough, so viennoiserie regardless of how a shop
-- displays them. Cookie -> patisserie; no evidence of a separate biscuit line.
classified AS (
  SELECT
    m.product_name,
    m.v1_total_units,
    CASE
      WHEN m.product_name IN (
        'CROISSANT','PAIN AU CHOCOLAT','PAIN AUX RAISINS','CROISSANT AMANDES',
        'PAIN CHOCO AMANDES','KOUIGN AMANN','CHAUSSON AUX POMMES'
      ) THEN 'viennoiserie'
      WHEN m.product_name IN ('COOKIE','TARTELETTE','ECLAIR') THEN 'patisserie'
      WHEN m.product_name = 'SANDWICH COMPLET' THEN 'sandwich'
      ELSE 'bread'
    END AS product_category,
    CASE WHEN m.product_name = 'SANDWICH COMPLET'
         THEN 'assembled' ELSE 'baked' END AS process_type
  FROM manufactured m
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


-- =============================================================================
-- dim_machine
--
-- SYNTHETIC. No equipment data exists in the source dataset. These rows describe
-- a DECLARED ASSUMED PLANT — a central production bakery supplying two retail
-- outlets, three resources, fixed product routing.
--
-- The equipment basis (deck count, load density, handling allowances) comes from
-- my own production-oven experience. The plant is an assumption; the process
-- values are not. The difference is marked.
--
-- base_failure_rate_per_hr is the ONLY causal channel from equipment to data:
--   install year -> failure rate -> downtime events -> OEE Availability.
-- =============================================================================
CREATE OR REPLACE TABLE dim_machine (
  machine_id               INTEGER PRIMARY KEY,
  machine_name             VARCHAR NOT NULL,
  machine_type             VARCHAR NOT NULL,
  install_year             INTEGER,
  capacity_units           VARCHAR,
  full_load_reference      VARCHAR,
  handling_minutes         DOUBLE,
  base_failure_rate_per_hr DOUBLE
);

INSERT INTO dim_machine VALUES
  (1, 'Deck Oven Line', 'deck_oven', 2012,
      '3 decks (120 x 160 cm baking surface); batch occupies the decks it needs',
      '30 baguettes per deck, width-wise at ~5 cm pitch = 90 per full load',
      6.0, 0.045),
  (2, 'Rack Oven Line', 'rack_oven', 2019,
      '18 trays (600 x 400 mm, ~85 mm spacing); batch occupies the trays it needs',
      '16 croissants per tray (4 x 4, 70 g) = 288 per full rack',
      2.0, 0.020),
  (3, 'Assembly Bench', 'manual_assembly', 2019,
      'manual station; no oven load model',
      '60 seconds per completed sandwich = 60 units/hr',
      0.0, 0.005);


-- =============================================================================
-- Product standards — routing, load size, bake time, cost, ideal rate
--
-- ideal_units_per_hr = units_per_full_load x (60 / (bake_minutes + handling))
--
-- Nominal BAKE-CELL CAPACITY: theoretical maximum finished units per hour of RUN
-- TIME, at full load, no changeover, no downtime. Finishing and labour stations
-- are NOT modelled, so hand-finished products show lower Performance against an
-- oven-based standard. Stated simplification.
--
-- The arithmetic is visible on purpose. Every rate derives from six equipment
-- numbers and one bake time. Change an input, every affected rate recomputes.
--
-- unit_cost_eur = real median selling price x a FABRICATED category ratio.
-- Full standard cost; all scrap valued at it regardless of rejection stage.
-- CIRCULARITY WARNING: the ratios are invented. "Patisserie carries the most
-- scrap cost" would be those ratios read back. Cost supports no finding.
-- =============================================================================
CREATE OR REPLACE TEMP TABLE operating_standards (
  product_name        VARCHAR,
  machine_id          INTEGER,
  units_per_full_load INTEGER,
  bake_minutes        DOUBLE,
  assembly_seconds    DOUBLE
);

INSERT INTO operating_standards VALUES
  -- Deck Oven Line: 30 baguettes/deck x 3 decks = 90 per full load
  ('TRADITIONAL BAGUETTE', 1,  90, 24.0, NULL),
  ('BAGUETTE',             1,  90, 24.0, NULL),
  ('BANETTE',              1,  90, 24.0, NULL),
  ('CEREAL BAGUETTE',      1,  90, 26.0, NULL),   -- heavier dough, longer bake
  ('FICELLE',              1, 117, 22.0, NULL),   -- thinner: tighter pitch
  ('BANETTINE',            1, 108, 22.0, NULL),
  ('BOULE 200G',           1,  54, 28.0, NULL),   -- round loaves waste deck width
  ('BOULE 400G',           1,  36, 35.0, NULL),
  ('PAIN',                 1,  45, 32.0, NULL),
  ('PAIN BANETTE',         1,  45, 32.0, NULL),
  -- QUIM BREAD reclassified from specialty loaf to standard loaf on PRICE
  -- EVIDENCE: real median ~EUR 1.00, baguette money, against ~2.40 and ~2.50
  -- for SPECIAL BREAD and VIK BREAD. A EUR 1 product that bakes 40 minutes at a
  -- third of baguette load density does not hold together. Same method that
  -- caught COUPE: judge a product by how it behaves, not what it is called.
  ('QUIM BREAD',           1,  45, 32.0, NULL),
  ('CAMPAGNE',             1,  27, 42.0, NULL),
  ('COMPLET',              1,  27, 42.0, NULL),   -- wholemeal bakes long
  ('MOISSON',              1,  27, 42.0, NULL),
  ('SPECIAL BREAD',        1,  27, 40.0, NULL),
  ('VIK BREAD',            1,  27, 40.0, NULL),
  -- Rack Oven Line: 16 croissants/tray x 18 trays = 288 per full rack
  ('CROISSANT',            2, 288, 18.0, NULL),
  ('PAIN AU CHOCOLAT',     2, 216, 19.0, NULL),   -- 4 x 3, wider footprint
  ('PAIN AUX RAISINS',     2, 216, 20.0, NULL),
  ('CROISSANT AMANDES',    2, 216, 20.0, NULL),
  ('PAIN CHOCO AMANDES',   2, 216, 20.0, NULL),
  ('KOUIGN AMANN',         2, 216, 24.0, NULL),   -- dense, individual forms
  ('CHAUSSON AUX POMMES',  2, 144, 22.0, NULL),   -- 4 x 2, generous spacing
  ('COOKIE',               2, 432, 13.0, NULL),   -- 6 x 4, short bake
  ('TARTELETTE',           2, 216, 20.0, NULL),
  ('ECLAIR',               2, 360, 29.0, NULL),   -- 5 x 4, narrow
  -- Assembly Bench: no oven
  ('SANDWICH COMPLET',     3, NULL, NULL, 60.0);

-- Real median observed selling price, across sales LINES (unweighted by
-- quantity) so it lands on the modal price period rather than being dragged by
-- volume. Exact median: the table is small and a portfolio project should not
-- ship an approximation it does not need.
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


-- =============================================================================
-- FACT TABLES — raw events only.
--
-- No yield %, no waste rate, no OEE column anywhere in this schema. Every KPI
-- derives in SQL. If a metric could be stored here, it isn't. That is the point:
-- a generator that writes its own KPIs proves only that it can write numbers.
-- =============================================================================
CREATE OR REPLACE TABLE fact_production_batch (
  batch_id                   VARCHAR NOT NULL,
  production_date            DATE    NOT NULL,
  product_id                 INTEGER NOT NULL,
  machine_id                 INTEGER NOT NULL,
  planned_units              INTEGER NOT NULL,
  loads_used                 DOUBLE  NOT NULL,
  scheduled_start_ts         TIMESTAMP NOT NULL,
  scheduled_end_ts           TIMESTAMP NOT NULL,
  -- PLANNED PRODUCTION TIME — the denominator of OEE Availability.
  -- Scheduled BATCH time, not shift length. A batch allocated 40 minutes that
  -- lost 8 to a breakdown ran at 80% availability. Using shift length here would
  -- make Availability a measure of how idle the plant was, which is not what the
  -- metric is for.
  planned_production_minutes DOUBLE  NOT NULL,
  actual_start_ts            TIMESTAMP NOT NULL,
  actual_end_ts              TIMESTAMP NOT NULL,
  -- Stop time is NOT stored here. It lives as intervals in fact_downtime and is
  -- summed in SQL. Storing both would let them drift.
  run_time_minutes           DOUBLE  NOT NULL,
  -- total_units is NOT stored. It is good + scrap, and storing a derivable sum
  -- invites it to disagree with its own parts.
  good_units                 INTEGER NOT NULL,
  scrap_units                INTEGER NOT NULL
);

CREATE OR REPLACE TABLE fact_downtime (
  downtime_id           VARCHAR NOT NULL,
  batch_id              VARCHAR NOT NULL,
  machine_id            INTEGER NOT NULL,
  production_date       DATE    NOT NULL,
  start_ts              TIMESTAMP NOT NULL,
  end_ts                TIMESTAMP NOT NULL,
  duration_minutes      DOUBLE  NOT NULL,
  -- WHAT THE OPERATOR PRESSED. The only code a real analyst has. May be '99'
  -- (Other) even when the true cause was a changeover — because Other is the
  -- fastest button and the operator has dough on their hands.
  reported_reason_code  VARCHAR NOT NULL,
  reported_reason_label VARCHAR NOT NULL,
  -- WHAT ACTUALLY HAPPENED. Does not exist in a real MES.
  true_reason_code      VARCHAR NOT NULL,
  true_reason_label     VARCHAR NOT NULL,
  -- FALSE = a micro-stop that never reached the terminal at all. Invisible to
  -- the KPI views, which is the point: unlogged stops silently INFLATE
  -- Availability, and from inside real data you cannot see the gap.
  was_logged            BOOLEAN NOT NULL
);

CREATE OR REPLACE TABLE fact_quality_inspection (
  inspection_id   VARCHAR NOT NULL,
  batch_id        VARCHAR NOT NULL,
  production_date DATE    NOT NULL,
  inspection_ts   TIMESTAMP NOT NULL,
  -- Sampled, not census. This table does NOT feed the Quality term of OEE (that
  -- derives from good/scrap on every batch). It is a separate signal about
  -- whether defects were CAUGHT.
  sample_size     INTEGER NOT NULL,
  defects_found   INTEGER NOT NULL,
  outcome         VARCHAR NOT NULL,
  defect_type     VARCHAR
);
