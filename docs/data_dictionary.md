# Data Dictionary — Bakery Sales (Cleaned)

**File:** `data/cleaned/bakery_sales_clean.csv`
**Rows:** 232,679 sales lines
**Period:** 2 January 2021 → 30 September 2022
**Unique products:** 147
**Source:** French bakery point-of-sale export (real data)

Each row represents **one product line on one receipt** — not one customer visit. A single purchase (ticket) can span several rows, one per item bought.

---

## Columns

| Column | Meaning (plain English) | Type | Example | Notes |
|---|---|---|---|---|
| `date` | Calendar date of the transaction | text (YYYY-MM-DD) | `2021-01-02` | Kept from the raw data |
| `time` | Time of day of the transaction | text (HH:MM) | `08:38` | Kept from the raw data |
| `datetime` | Full timestamp — date and time combined | datetime | `2021-01-02 08:38:00` | **Derived.** Merged `date` + `time` so we can extract day-of-week, hour, and month for demand analysis |
| `ticket_number` | Receipt / transaction ID | integer | `150040` | Shared across items bought together. Converted from decimal (`150040.0`) to whole number |
| `article` | Product name (in French) | text | `BAGUETTE` | 147 distinct values after cleaning. A few are catch-all register categories (e.g. `DIVERS …`) rather than specific products |
| `Quantity` | Number of units sold on this line | number | `1.0` | Capitalised name kept from the raw file. All values are positive after cleaning (returns removed) |
| `unit_price` | Price per single unit, in euros (€) | number | `0.90` | **Transformed.** Converted from French text format `"0,90 €"` to a numeric value |
| `revenue` | Money earned on this line | number | `0.90` | **Derived.** `Quantity × unit_price`, in euros |

---

## Cleaning decisions applied to reach this dataset

Starting from **234,005** raw rows, the following were applied (see `notebooks/02_data_cleaning.ipynb`):

1. **Dropped the `Unnamed: 0` column** — a leftover row-number index with no business meaning.
2. **Converted `unit_price` from text to a number** — the raw values were strings like `"0,90 €"` (euro symbol, comma decimal), which cannot be used in calculations.
3. **Combined `date` + `time` into `datetime`** — to enable time-based analysis.
4. **Removed 1,295 returns** (negative quantities) — a refund is not customer demand, and this project analyses demand.
5. **Removed 31 zero-price rows** — likely giveaways or till errors; excluded to keep revenue figures honest. *(32 rows had a zero price, but 1 was also a return and removed in step 4.)*
6. **Created the `revenue` column** — `Quantity × unit_price`.

**Result: 232,679 clean sales lines across 147 products.** Product count dropped from 149 to 147 because two products appeared only in the removed rows.

---

## Known caveats (for honest analysis)

- **Catch-all categories:** entries like `DIVERS VIENNOISERIE` ("miscellaneous pastries") are real sales but not specific products. They are kept in the dataset but should be excluded when ranking individual top-selling products, so they don't distort results.
- **Coverage:** the data ends in September 2022, so 2022 is a partial year — relevant when comparing annual or seasonal totals.
- **One bakery:** this is a single French bakery's data, so patterns reflect its local customers, not bakeries in general.
