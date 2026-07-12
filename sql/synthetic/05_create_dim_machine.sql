-- =============================================================================
-- 05_create_dim_machine.sql
-- Synthetic manufacturing layer — machine master
--
-- SYNTHETIC. No real equipment data exists in the source dataset. These rows
-- describe a DECLARED ASSUMED PLANT: a central production bakery supplying
-- multiple retail outlets, with three resources and fixed product routing.
--
-- The equipment basis below (deck count, load density, handling allowances)
-- comes from my own production-oven experience, not from the dataset. It is an
-- assumption about the simulated plant, stated openly, and every production
-- rate in dim_product derives from it.
--
-- handling_minutes is the load/unload allowance added to bake time to make a
-- full cycle. Deck oven: 6 min for all three decks (2 min per deck, product
-- staged at the bench, peel loaded before the door opens). Rack oven: 2 min,
-- door-open to door-closed — a trolley swap, not a manual clear-and-reload.
-- These are working targets, not slow-day observations: a 6-minute rack swap
-- would bleed steam and thermal mass and produce a trolley gradient.
--
-- base_failure_rate_per_hr drives downtime event frequency in the generator.
-- It is the ONLY causal channel by which machine age affects the data:
--   install year -> base failure rate -> downtime events -> OEE Availability.
--
-- KNOWN LIMITATION (documented, not a defect):
-- Routing is fixed, so machine is perfectly collinear with product family.
-- Downtime on the deck line cannot be distinguished from downtime on bread.
-- This layer produces no findings, so the confound is harmless — but stated.
--
-- IMPORTANT: set query processing location to EU before running.
-- =============================================================================

CREATE OR REPLACE TABLE `bakery_synthetic.dim_machine` (
  machine_id               INT64   NOT NULL,
  machine_name             STRING  NOT NULL,
  machine_type             STRING  NOT NULL,
  install_year             INT64,
  capacity_units           STRING,
  full_load_reference      STRING,
  handling_minutes         FLOAT64,
  base_failure_rate_per_hr FLOAT64
)
OPTIONS (
  description =
    'SYNTHETIC machine master for the simulated production bakery. No real '
    'equipment data exists in the source dataset. Three resources with fixed '
    'product routing: deck oven line (bread), rack oven line (viennoiserie and '
    'patisserie), assembly bench (sandwich). Equipment basis declared from '
    'production experience; base_failure_rate_per_hr is a generator input, not '
    'an observation.'
);

INSERT INTO `bakery_synthetic.dim_machine` (
  machine_id, machine_name, machine_type, install_year,
  capacity_units, full_load_reference, handling_minutes, base_failure_rate_per_hr
)
VALUES
  (1, 'Deck Oven Line',  'deck_oven',      2012,
      '3 decks (120 x 160 cm baking surface); batch occupies the decks it needs',
      '30 baguettes per deck, width-wise at ~5 cm pitch = 90 per full load',
      6.0,  0.045),

  (2, 'Rack Oven Line',  'rack_oven',      2019,
      '18 trays (600 x 400 mm, ~85 mm spacing); batch occupies the trays it needs',
      '16 croissants per tray (4 x 4, 70 g) = 288 per full rack',
      2.0,  0.020),

  (3, 'Assembly Bench',  'manual_assembly', 2019,
      'manual station; no oven load model',
      '60 seconds per completed sandwich = 60 units/hr',
      0.0,  0.005);

-- -----------------------------------------------------------------------------
-- Validation
-- -----------------------------------------------------------------------------

ASSERT (SELECT COUNT(*) FROM `bakery_synthetic.dim_machine`) = 3
  AS 'Validation failed: dim_machine must contain exactly 3 machines.';

ASSERT (
  SELECT COUNT(*) FROM `bakery_synthetic.dim_machine`
  WHERE base_failure_rate_per_hr IS NULL OR base_failure_rate_per_hr < 0
) = 0
  AS 'Validation failed: base_failure_rate_per_hr must be present and non-negative.';

-- The older deck oven must be the less reliable resource, or install year is
-- decorative rather than causal.
ASSERT (
  SELECT
    (SELECT base_failure_rate_per_hr FROM `bakery_synthetic.dim_machine` WHERE machine_id = 1)
    > (SELECT base_failure_rate_per_hr FROM `bakery_synthetic.dim_machine` WHERE machine_id = 2)
)
  AS 'Validation failed: the older deck oven must carry the higher base failure rate.';

-- Manual deck handling must be slower than a rack trolley swap. If this ever
-- flips, the handling model has been mis-entered.
ASSERT (
  SELECT
    (SELECT handling_minutes FROM `bakery_synthetic.dim_machine` WHERE machine_id = 1)
    > (SELECT handling_minutes FROM `bakery_synthetic.dim_machine` WHERE machine_id = 2)
)
  AS 'Validation failed: deck-oven handling must exceed rack-oven handling.';

SELECT * FROM `bakery_synthetic.dim_machine` ORDER BY machine_id;
