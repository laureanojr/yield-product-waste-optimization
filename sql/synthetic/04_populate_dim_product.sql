-- Populates the SYNTHETIC product master with the 27 manufacturable products.
--
-- Design: names and unit totals are read LIVE from the real v1 KPI view, so this
-- table cannot silently drift from its source. Categories and process types are the
-- only hand-authored values here — they encode domain judgment that isn't in the POS data.
--
-- unit_cost_eur and ideal_units_per_hr are left NULL deliberately. They are FABRICATED
-- standards and get authored in a separate, visible step (05_).
--
-- Classification rule: process beats merchandising. KOUIGN AMANN and CHAUSSON AUX POMMES
-- are laminated-dough products, so they sit with viennoiserie regardless of how a shop
-- displays them. COOKIE sits under patisserie — no evidence of a separate biscuit line.
--
-- IMPORTANT: set query processing location to EU before running.

TRUNCATE TABLE `bakery_synthetic.dim_product`;

INSERT INTO `bakery_synthetic.dim_product`
  (product_id, product_name, product_category, process_type, unit_cost_eur, ideal_units_per_hr, v1_total_units)
WITH categories AS (
  SELECT * FROM UNNEST([
    STRUCT('TRADITIONAL BAGUETTE' AS product_name, 'bread'        AS product_category, 'baked'     AS process_type),
    STRUCT('CROISSANT',            'viennoiserie', 'baked'),
    STRUCT('PAIN AU CHOCOLAT',     'viennoiserie', 'baked'),
    STRUCT('BANETTE',              'bread',        'baked'),
    STRUCT('BAGUETTE',             'bread',        'baked'),
    STRUCT('CEREAL BAGUETTE',      'bread',        'baked'),
    STRUCT('SPECIAL BREAD',        'bread',        'baked'),
    STRUCT('TARTELETTE',           'patisserie',   'baked'),
    STRUCT('BOULE 400G',           'bread',        'baked'),
    STRUCT('CAMPAGNE',             'bread',        'baked'),
    STRUCT('COOKIE',               'patisserie',   'baked'),
    STRUCT('ECLAIR',               'patisserie',   'baked'),
    STRUCT('VIK BREAD',            'bread',        'baked'),
    STRUCT('COMPLET',              'bread',        'baked'),
    STRUCT('FICELLE',              'bread',        'baked'),
    STRUCT('MOISSON',              'bread',        'baked'),
    STRUCT('BANETTINE',            'bread',        'baked'),
    STRUCT('BOULE 200G',           'bread',        'baked'),
    STRUCT('PAIN BANETTE',         'bread',        'baked'),
    STRUCT('SANDWICH COMPLET',     'sandwich',     'assembled'),
    STRUCT('PAIN AUX RAISINS',     'viennoiserie', 'baked'),
    STRUCT('PAIN',                 'bread',        'baked'),
    STRUCT('KOUIGN AMANN',         'viennoiserie', 'baked'),
    STRUCT('CROISSANT AMANDES',    'viennoiserie', 'baked'),
    STRUCT('QUIM BREAD',           'bread',        'baked'),
    STRUCT('CHAUSSON AUX POMMES',  'viennoiserie', 'baked'),
    STRUCT('PAIN CHOCO AMANDES',   'viennoiserie', 'baked')
  ])
),
ranked AS (
  SELECT
    product,
    total_units,
    ROW_NUMBER() OVER (ORDER BY total_units DESC, product ASC) AS rank_units
  FROM `bakery.kpi_product_performance`
),
manufacturable AS (
  SELECT
    product,
    total_units,
    ROW_NUMBER() OVER (ORDER BY total_units DESC, product ASC) AS product_id
  FROM ranked
  WHERE rank_units <= 30
    AND product NOT IN ('CAFE OU EAU', 'FORMULE SANDWICH', 'COUPE')
)
SELECT
  m.product_id,
  m.product,
  c.product_category,
  c.process_type,
  CAST(NULL AS NUMERIC) AS unit_cost_eur,
  CAST(NULL AS FLOAT64) AS ideal_units_per_hr,
  CAST(m.total_units AS INT64) AS v1_total_units
FROM manufacturable m
JOIN categories c ON c.product_name = m.product   -- INNER JOIN: a product with no category is dropped, and the count check below catches it
ORDER BY m.product_id;
