# Suburb Metrics CSV Ingestion Playbook

Purpose:
- define the CSV schema for refreshing suburb metric data
- keep ingestion repeatable for every quarterly refresh
- protect the no-made-up-data rule
- ensure every metric row belongs to a valid suburb master row

Active data path:

```text
CSV/XLS source file
-> public.suburb_import_staging
-> public.suburbs
-> public.suburb_key_metrics_quarterly
-> public.refresh_suburb_base_scores()
-> public.suburb_base_scores
```

`public.suburb_monthly_data` is retired from the active app flow. Current market metrics are refreshed quarterly through `public.suburb_key_metrics_quarterly`.

Historical quarter key:

```text
suburb_key + quarter_period
```

`quarter_period` uses the quarter-end month format:

```text
YYYY-MM
```

Examples:

```text
2026-03
2026-06
2026-09
2026-12
```

## CSV Header Schema

The CSV should use these exact snake_case headers before importing into `public.suburb_import_staging`.

| CSV column | Required | Target usage | Notes |
|---|---:|---|---|
| `state` | Yes | `suburbs.state`, suburb key | Use state abbreviation such as `NSW`, `VIC`, `QLD`. |
| `post_code` | Yes | `suburbs.postcode`, suburb key | Keep as text if leading zeroes are possible. |
| `suburb` | Yes | `suburbs.suburb_name`, suburb key | Trim spaces; uppercase/lowercase is normalised during transform. |
| `typical_value` | Yes | `suburb_key_metrics_quarterly.median_price` | Median/typical dwelling value. Numeric or currency-formatted text is accepted by transform. |
| `gross_rental_yield` | Yes | `suburb_key_metrics_quarterly.gross_yield` | Can be `4.5%`, `4.5`, or `0.045`; transform stores decimal yield such as `0.045`. |
| `vacancy_rate` | Yes | `suburb_key_metrics_quarterly.vacancy_rate` | Stored as numeric value from source. |
| `percent_stock_on_market` | Yes | `suburb_key_metrics_quarterly.stock_on_market_pct` | Stored as numeric value from source. |
| `days_on_market` | Yes | `suburb_key_metrics_quarterly.days_on_market` | Text like `90days` is cleaned to `90`. |
| `avg_vendor_discount` | Yes | `suburb_key_metrics_quarterly.vendor_discount_pct` | Negative values are allowed if source data contains them. |
| `percent_renters_in_market` | Recommended | `suburb_key_metrics_quarterly.renters_pct` | Used in reports/context, not currently required for scoring. |
| `demand_to_supply_ratio` | Optional | Staging/reference | Not currently loaded by the active quarterly transform. |
| `statistical_reliability` | Optional | Staging/reference | Keep for review, not currently loaded by the active quarterly transform. |

## Derived Fields

`median_rent_weekly` is not guessed.

If the source file does not provide weekly rent directly, the current transform derives it only from two real source fields:

```text
median_rent_weekly = typical_value * gross_rental_yield / 52
```

Example:

```text
typical_value = 720000
gross_rental_yield = 0.045
median_rent_weekly = 720000 * 0.045 / 52 = 623.08
```

This is allowed because it is a transparent calculation from real source metrics.

## Suburb Key Format

The system key is:

```text
UPPER(TRIM(suburb)) || '_' || UPPER(TRIM(state)) || '_' || TRIM(post_code)
```

Example:

```text
MAITLAND_NSW_2320
```

This key must exist in `public.suburbs` before a row is loaded into `public.suburb_key_metrics_quarterly`.

## Quarterly Uniqueness Rule

The quarterly metric table is historical, not just a latest snapshot table.

Business key:

```text
suburb_key + quarter_period
```

Example:

```text
MAITLAND_NSW_2320 + 2026-09
```

This avoids storing unnecessary exact dates while still preserving quarter-over-quarter history.

Legacy compatibility note:
- if `public.suburb_key_metrics_quarterly` still has a `quarter_date` column from an older schema, the loader will populate it with the quarter-end date
- business uniqueness still uses `suburb_key + quarter_period`

## Required Load Order

### 1. Import CSV Into Staging

Import the cleaned CSV into:

```text
public.suburb_import_staging
```

Do not import directly into `suburb_key_metrics_quarterly` or `suburb_base_scores`.

### 2. Insert Missing Suburbs Into Master

Run this before loading quarterly metrics:

```sql
insert into public.suburbs (
  suburb_key,
  suburb_name,
  state,
  postcode
)
select distinct
  upper(trim(suburb)) || '_' || upper(trim(state)) || '_' || trim(post_code) as suburb_key,
  trim(suburb) as suburb_name,
  upper(trim(state)) as state,
  trim(post_code) as postcode
from public.suburb_import_staging
where suburb is not null
  and state is not null
  and post_code is not null
on conflict (suburb_key) do update set
  suburb_name = excluded.suburb_name,
  state = excluded.state,
  postcode = excluded.postcode;
```

If latitude/longitude columns exist in `public.suburbs` and are present in staging, update them in this step too.

### 3. Load Quarterly Metrics From Staging

Run:

```sql
-- sql/load_suburb_key_metrics_quarterly_from_staging.sql
```

This script joins staging rows to `public.suburbs`. Rows without matching master suburbs are not loaded.

### 4. Refresh Base Scores

Run:

```sql
select public.refresh_suburb_base_scores();
```

This refreshes:

```text
public.suburb_base_scores
```

from:

```text
public.suburb_key_metrics_quarterly
```

### 5. Validate

Run:

```sql
-- sql/postload_validate_prod.sql
```

Minimum expected results:

```text
quarterly_without_suburb = 0
quarterly_rows_missing_required_metrics = 0
empty_base_score_rows = 0
base_scores_without_quarterly_source = 0
```

For useful end-to-end testing, aim for at least:

```text
20 clean suburb_base_scores rows
```

Preferably:

```text
50+ clean suburb_base_scores rows
```

## No-Made-Up-Data Checks

Before running app tests, confirm:

```sql
select count(*) as clean_base_score_rows
from public.suburb_base_scores
where median_price is not null
  and median_rent_weekly is not null
  and gross_yield is not null
  and vacancy_rate is not null
  and stock_on_market_pct is not null
  and days_on_market is not null
  and vendor_discount_pct is not null;
```

And:

```sql
select count(*) as quarterly_without_suburb
from public.suburb_key_metrics_quarterly q
left join public.suburbs s on s.suburb_key = q.suburb_key
where s.suburb_key is null;
```

Expected:

```text
quarterly_without_suburb = 0
```

## End-To-End Test Readiness

Only start end-to-end app testing when:

- `public.suburbs` contains all suburbs from the CSV
- `public.suburb_key_metrics_quarterly` contains only source-backed metric rows
- `public.suburb_base_scores` has enough clean rows for meaningful recommendations
- no quarterly metric row exists without a suburb master row
- no base score row exists without quarterly source data

Then test:

```text
Generate Recommendation
-> select suburbs
-> create report draft
-> preview PDF
-> export/store PDF
-> retrieve report by code
```
