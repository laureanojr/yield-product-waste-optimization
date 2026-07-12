# Synthetic Layer — Equipment Basis and Fabricated Parameters

Every number the simulation is built from, so a reader can tell without opening the code which values came from the real dataset and which were invented.

What this layer is for, and what it doesn't prove: [`synthetic_layer_scope.md`](synthetic_layer_scope.md).

---

## The assumed plant

There is no equipment data in the source dataset. The plant below is declared, not observed.

> A central production bakery supplying two retail outlets. Three resources with fixed product routing: a deck oven line (bread), a rack oven line (viennoiserie and patisserie), and a manual assembly bench (sandwich). Manual loading throughout.

### Why the scale factor is 2

The real POS series is one retail shop — about 540 units a day across all 27 products. A single shop doesn't run an OEE programme; it has a baker who knows what to bake. Anchoring an industrial metric to shop-scale demand gives you idle ovens and an OEE that measures emptiness.

So the generator scales demand by a declared constant before planning, never by inflating generated data afterwards. The mix and the seasonality stay real; only the scale is fabricated.

The value came from a capacity check, not from taste:

| Factor | Deck hours/day | Rack hours/day | |
|---|---|---|---|
| 1 | 3.0 | 0.2 | idle most of the shift |
| **2** | **6.0** | **0.4** | **fits a 10-hour shift with margin** |
| 3 | 9.0 | 0.6 | no room for changeovers |
| 10 | 30.1 | 1.9 | impossible |

The deck oven is the plant — bread is ~90% of volume, and a deck load is 90 units against the rack's 288. At factor 2 the deck runs about 6 hours of a 10-hour shift. Push it higher and the plant fails to bake its own demand every day for 600 days.

This is not a finding. I chose the factor and I chose the oven.

### Calendar

Monday to Saturday, closed Sundays, on the plant's own schedule — it doesn't inherit the retail shop's Wednesday closure.

Sunday is the shop's biggest day and the plant is shut, so Sunday demand rolls into Saturday. That's why Saturday is a monster shift in a real bakery.

The shift is 02:00–12:00. Ten hours: roughly 6 of deck-oven bake time, the rest changeovers and downtime.

---

## Equipment basis

Six numbers. Every one of the 27 production rates derives from them plus a bake time.

| Parameter | Assumption |
|---|---|
| Deck oven — decks | 3 |
| Deck oven — baking surface | ~120 × 160 cm per deck |
| Deck oven — baguettes per deck | 30 (width-wise, ~5 cm pitch: piece plus a 2–3 cm airflow gap) → 90 per full load |
| Deck oven — handling per cycle | 6 min (2 per deck, product staged, peel loaded before the door opens) |
| Rack oven — trays per rack | 18 (600 × 400 mm, ~85 mm spacing) |
| Rack oven — croissants per tray | 16 (4 × 4, 70 g) → 288 per full rack |
| Rack oven — handling per cycle | 2 min (trolley swap, door open to door closed) |

The airflow gap isn't slack, it's the constraint — pack baguettes tighter than 2–3 cm and the side crust never sets. Same reasoning gives 4 × 4 croissants on a tray rather than 5 × 5: they need room for oven spring without edges touching.

Handling is why cycle time isn't just bake time. The deck oven is slow because three chambers get cleared and reloaded by hand; the rack is fast because one trolley rolls out and another rolls in. Both are working targets — a six-minute rack swap would bleed steam and thermal mass and leave a trolley gradient.

### The load unit is the tray, not the whole oven

No bakery bakes eighteen trays of nothing but éclairs. A batch takes the trays it needs and consumes oven time in proportion:

```
run_time = (trays_used / 18) × cycle_minutes
```

Same on the deck, with decks. Allocating a fraction of an oven cycle is a mild fiction — you can't run an eighteenth of a rack — but it's the standard capacity-share allocation for a shared resource. Without it, Performance would measure how I chose to batch rather than how the process ran.

### Rate definition

```
ideal_units_per_hr = units_per_full_load × (60 / (bake_minutes + handling_minutes))
```

Reference rates: traditional baguette **180.00/hr** (90 per load, 30-minute cycle), croissant **864.00/hr** (288 per rack, 20-minute cycle).

This is bake-cell capacity: maximum units per hour of run time, full load, no changeover, no downtime.

Finishing and labour stations aren't modelled, so hand-finished products — éclair, tartelette, the almond products — show lower Performance against an oven-based standard.

`SANDWICH COMPLET` is the only non-oven product: 60 seconds per unit, so 60/hr.

### Footprint factors

Load sizes come from each product's footprint relative to the reference product on its machine. That's geometry — a round loaf uses deck width worse than a long thin one — and it's reasoned about, not claimed from experience. Whole pieces per deck or per tray, because ovens hold whole pieces.

Deck oven, pieces per deck × 3:

| Class | Per deck | Full load |
|---|---|---|
| Ficelle | 39 | 117 |
| Banettine | 36 | 108 |
| Baguette format | 30 | 90 |
| Boule 200 g | 18 | 54 |
| Standard loaf | 15 | 45 |
| Boule 400 g | 12 | 36 |
| Country / specialty loaf | 9 | 27 |

Rack oven, pieces per 600 × 400 tray × 18:

| Class | Layout | Per tray | Full rack |
|---|---|---|---|
| Cookie | 6 × 4 | 24 | 432 |
| Éclair | 5 × 4 | 20 | 360 |
| Croissant (70 g) | 4 × 4 | 16 | 288 |
| Pain au chocolat, raisins, kouign amann, almond products, tartelette | 4 × 3 | 12 | 216 |
| Chausson aux pommes | 4 × 2 | 8 | 144 |

### Bake times

From experience, and the only part of the equipment model I'd defend that way.

Baguette 24 min · ficelle and banettine 22 · cereal baguette 26 · boule 200 g 28 · standard loaf 32 · boule 400 g 35 · specialty loaf 40 · country and wholemeal 42 · croissant 18 · pain au chocolat 19 · raisins, almond products, tartelette 20 · chausson 22 · kouign amann 24 · éclair shell 29 · cookie 13.

---

## Cost

`unit_cost_eur` is full standard cost per unit (materials plus conversion), used to value scrap.

Derived as: real median selling price × a fabricated category ratio — bread 0.30, viennoiserie 0.36, patisserie 0.40, sandwich 0.45.

All scrap is valued at full standard cost regardless of when it was rejected. A real plant charges scrap at the cost accumulated to that point: dough dumped at proofing is cheap, a loaf pulled after the bake carries the full oven. This schema has one stage.

The ratios are invented, so any statement of the form "category X carries the most scrap cost" is those ratios read back. Cost is a scaling constant here, not a source of insight.

---

## Generator parameters

Downtime rates, scrap rates, miscoding probabilities, the micro-stop process, the batch dispatch rule and the random seed all live in [`config/synthetic_generator.yaml`](../config/synthetic_generator.yaml), with the reasoning in the comments.
