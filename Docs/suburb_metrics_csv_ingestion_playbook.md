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
-> public.suburb_population_metrics_staging (if refreshing population coverage)
-> public.suburb_population_metrics (if refreshing population coverage)
-> public.refresh_suburb_base_scores()
-> public.suburb_base_scores
-> public.suburb_context_refresh_jobs
-> public.suburb_ai_context_facts
```

`public.suburb_monthly_data` is retired from the active app flow. Current market metrics are refreshed quarterly through `public.suburb_key_metrics_quarterly`.

Population metrics are a separate source-backed data path. Do not expect the
market-metrics CSV loader to populate population fields; it intentionally leaves
population values null unless they come from `public.suburb_population_metrics`.

AI/web-grounded context is also a separate cache path. The live report flow can
run without context facts, but context jobs should still be queued after metric
loads so newly added suburbs can be refreshed by the monthly batch process.

## Automation Contract

This playbook is intended to be executable later as an automated pipeline. Keep
future edits compatible with the following contract.

Pipeline inputs:
- market metrics CSV path or uploaded object reference
- optional population metrics CSV path or uploaded object reference
- target quarter period, defaulting to current quarter-end month in `YYYY-MM`
- AI context provider/model, defaulting to the current function defaults
- run mode: `dry_run`, `incremental`, or `full_reload`

Pipeline outputs:
- market staging row count
- inserted/updated suburb master count
- loaded quarterly metric row count for target quarter
- clean base score row count
- missing population count and missing population CSV/list artifact
- AI context enqueue counts: inserted, existing, total for month
- validation result set with pass/fail status per gate

Hard stop gates:
- market CSV is missing any required headers
- `public.suburb_import_staging` row count is `0` after import
- any quarterly metric row lacks a suburb master row
- any loaded quarterly metric row is missing a required market metric
- `public.suburb_base_scores` has rows with no quarterly source
- `public.suburb_population_metrics` has rows with no suburb master row

Soft gates:
- `quarterly_without_population > 0`
- AI context jobs are not fully completed for the month

Soft gates do not block MVP app testing when the missing data is documented and
the app/report hides unavailable sections. They should still be recorded in the
pipeline output.

Idempotency rules:
- staging tables may be truncated before each import
- `public.suburbs` upserts by `suburb_key`
- `public.suburb_key_metrics_quarterly` upserts by `suburb_key + quarter_period`
- `public.suburb_population_metrics` upserts by `suburb_key`
- `public.enqueue_suburb_context_refresh_jobs()` is safe to rerun because job
  uniqueness is `suburb_key + refresh_month + prompt_version + ai_provider + model`

Recommended pipeline stage map:

| Stage | Required | Inputs | Action | Success output |
|---|---:|---|---|---|
| `preflight` | Yes | database | capture row counts and relationship checks | preflight snapshot |
| `market_stage` | Yes | market CSV | truncate/import `suburb_import_staging` | staging row count > 0 |
| `suburb_master_sync` | Yes | market staging | upsert `public.suburbs` | no staged suburb has null key parts |
| `quarterly_metrics_load` | Yes | market staging, target quarter | run quarterly loader | required metrics loaded for source-backed rows |
| `base_scores_refresh` | Yes | quarterly metrics | `refresh_suburb_base_scores()` | clean base score count |
| `population_audit` | Yes | quarterly metrics, population table | missing population audit | missing count/list artifact |
| `population_load` | Optional | population CSV | load population staging/table, refresh scores | reduced missing population count |
| `ai_context_enqueue` | Yes | quarterly metrics | enqueue monthly jobs | queue count matches metric suburb count |
| `postload_validate` | Yes | database | run validation SQLs | hard gates pass |
| `smoke_test` | Recommended | app/database | recommendation/report smoke | recommendation output succeeds |

Machine-readable stage summary:

```yaml
pipeline: suburb_data_refresh
mode: incremental
stages:
  - id: preflight
    required: true
    hard_stop_on_failure: true
  - id: market_stage
    required: true
    hard_stop_on_failure: true
    requires_inputs:
      - market_metrics_csv
  - id: suburb_master_sync
    required: true
    hard_stop_on_failure: true
  - id: quarterly_metrics_load
    required: true
    hard_stop_on_failure: true
  - id: base_scores_refresh
    required: true
    hard_stop_on_failure: true
  - id: population_audit
    required: true
    hard_stop_on_failure: false
    emits_soft_gap: quarterly_without_population
  - id: population_load
    required: false
    hard_stop_on_failure: true
    requires_inputs:
      - population_metrics_csv
  - id: ai_context_enqueue
    required: true
    hard_stop_on_failure: false
  - id: postload_validate
    required: true
    hard_stop_on_failure: true
  - id: smoke_test
    required: false
    hard_stop_on_failure: false
```

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

## Incremental Refresh Load Order

Use this sequence when adding or refreshing suburb market metrics without a full
domain reset.

### 0. Preflight Snapshot

Pipeline stage: `preflight`

Inputs:
- database connection

Actions:
- capture key table row counts
- check existing relationship health before new data is loaded

Outputs:
- preflight row-count snapshot
- relationship issue counts

Before changing data, capture row counts and obvious relationship issues:

```sql
-- sql/preflight_prod_reload.sql
```

For a small incremental load, the most useful snapshot is:

```sql
select 'suburbs' as table_name, count(*) as row_count from public.suburbs
union all
select 'suburb_import_staging', count(*) from public.suburb_import_staging
union all
select 'suburb_key_metrics_quarterly', count(*) from public.suburb_key_metrics_quarterly
union all
select 'suburb_population_metrics', count(*) from public.suburb_population_metrics
union all
select 'suburb_base_scores', count(*) from public.suburb_base_scores
union all
select 'suburb_context_refresh_jobs', count(*) from public.suburb_context_refresh_jobs
order by table_name;
```

### 1. Clear Market Staging

Pipeline stage: `market_stage`

Inputs:
- market metrics CSV

Actions:
- validate required CSV headers before import
- truncate `public.suburb_import_staging`
- import market metrics CSV into `public.suburb_import_staging`

Outputs:
- market staging row count

Stop if:
- required headers are missing
- staging row count is `0`

Before importing a fresh market-metrics CSV, empty the staging table:

```sql
truncate table public.suburb_import_staging restart identity;
```

`public.suburb_import_staging` is temporary import workspace, not history.
Clearing it before every refresh prevents old CSV rows from mixing with the
new file and being transformed into the current quarter load.

### 2. Import Market CSV Into Staging

Pipeline stage: `market_stage`

Import the cleaned CSV into:

```text
public.suburb_import_staging
```

Do not import directly into `suburb_key_metrics_quarterly` or `suburb_base_scores`.

### 3. Insert Missing Suburbs Into Master

Pipeline stage: `suburb_master_sync`

Inputs:
- `public.suburb_import_staging`

Actions:
- derive `suburb_key`
- upsert `public.suburbs`

Outputs:
- all staged suburb keys exist in `public.suburbs`

Stop if:
- any staged row has missing `suburb`, `state`, or `post_code`

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

### 4. Load Quarterly Metrics From Staging

Pipeline stage: `quarterly_metrics_load`

Inputs:
- `public.suburb_import_staging`
- `public.suburbs`
- target quarter period

Actions:
- clean source metric text values
- derive `median_rent_weekly` from `typical_value * gross_rental_yield / 52`
- upsert `public.suburb_key_metrics_quarterly`

Outputs:
- quarterly row count for target quarter
- dropped/rejected row count, if automation captures it

Stop if:
- any loaded quarterly row has no suburb master row
- any loaded quarterly row is missing required metrics

Run:

```sql
-- sql/load_suburb_key_metrics_quarterly_from_staging.sql
```

This script joins staging rows to `public.suburbs`. Rows without matching master suburbs are not loaded.

### 5. Refresh Base Scores

Pipeline stage: `base_scores_refresh`

Inputs:
- `public.suburb_key_metrics_quarterly`
- optional existing `public.suburb_population_metrics`

Actions:
- run score refresh functions

Outputs:
- clean base score row count
- base scores without quarterly source count

Stop if:
- `base_scores_without_quarterly_source > 0`

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

If population metrics already exist, this function also preserves or refreshes
population momentum fields through the scoring functions. Missing population
rows are not invented; affected reports should omit population sections.

### 6. Refresh Population Metrics When Population Source Data Is Available

Pipeline stages: `population_audit`, optional `population_load`

Inputs:
- `public.suburb_key_metrics_quarterly`
- `public.suburb_population_metrics`
- optional population CSV

Actions:
- audit missing population coverage for all quarterly metric suburbs
- if population CSV exists, load through staging and refresh population scores

Outputs:
- `quarterly_without_population`
- missing population suburb list
- population staging row count, when loaded
- refreshed base score count, when loaded

Soft gate:
- `quarterly_without_population > 0`

Population is not loaded by the market CSV. If the refresh introduces new
suburbs, check population coverage before app testing:

```sql
-- sql/find_quarterly_suburbs_missing_population_metrics.sql
```

If missing suburbs have source-backed population data available, load the
population CSV through the population staging path:

```sql
truncate table public.suburb_population_metrics_staging restart identity;
```

Import the population CSV into:

```text
public.suburb_population_metrics_staging
```

Expected population staging headers:

```text
id
suburb_key
suburb_name
state
postcode
population_2025
growth_2023_2024_pct
growth_2024_2025_pct
source_level
allocation_method
source_year
source_name
created_at
updated_at
```

Then run:

```sql
-- sql/load_suburb_population_metrics_from_staging.sql
select public.refresh_population_growth_scores();
select public.refresh_suburb_base_scores();
```

Run the missing-population audit again:

```sql
-- sql/find_quarterly_suburbs_missing_population_metrics.sql
```

Acceptable outcomes:
- `quarterly_without_population = 0`, or
- remaining missing suburbs are documented and reports omit population fields
  for those suburbs.

Do not create manual placeholder population rows. If the population source does
not cover a suburb, leave the row missing until a verified source is available.

### 7. Enqueue Monthly AI Context Jobs

Pipeline stage: `ai_context_enqueue`

Inputs:
- `public.suburb_key_metrics_quarterly`
- current month
- AI provider/model defaults

Actions:
- enqueue monthly context refresh jobs for all metric suburbs
- check job queue coverage

Outputs:
- `inserted_count`
- `existing_count`
- `total_for_month`
- metric suburb count vs queued context suburb count

Soft gate:
- context jobs may remain pending/failed without blocking MVP reports, but the
  queue coverage should match metric suburb coverage

After loading quarterly metrics, enqueue monthly AI context refresh jobs:

```sql
select *
from public.enqueue_suburb_context_refresh_jobs();
```

The enqueue function reads distinct suburb keys from:

```text
public.suburb_key_metrics_quarterly
```

This means newly added metric suburbs are picked up automatically on the next
enqueue run. Existing jobs for the same `suburb_key + refresh_month +
prompt_version + ai_provider + model` are left unchanged, so it is safe to run
this after every metrics load and before each daily context-refresh batch.

Recommended daily batch order:

```text
enqueue missing jobs for the current month
-> process the next daily batch, e.g. 100 jobs
```

Check queue coverage:

```sql
select
  count(distinct q.suburb_key) as metric_suburbs,
  count(distinct j.suburb_key) as queued_context_suburbs
from public.suburb_key_metrics_quarterly q
left join public.suburb_context_refresh_jobs j
  on j.suburb_key = q.suburb_key
  and j.refresh_month = date_trunc('month', current_date)::date;
```

Check current job status:

```sql
select status, count(*)
from public.suburb_context_refresh_jobs
where refresh_month = date_trunc('month', current_date)::date
group by status
order by status;
```

Process batches with the deployed worker only after secrets and deployment are
confirmed in [suburb_context_refresh_batch_workflow.md](suburb_context_refresh_batch_workflow.md).

### 8. Validate

Pipeline stage: `postload_validate`

Inputs:
- database after market, optional population, score, and queue refresh stages

Actions:
- run post-load validation SQLs
- classify each result as hard pass/fail or documented soft gap

Outputs:
- validation result set
- hard gate pass/fail status

Stop if:
- any hard gate fails

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

Additional integrity checks:

```sql
select count(*) as quarterly_without_population
from public.suburb_key_metrics_quarterly q
left join public.suburb_population_metrics p
  on p.suburb_key = q.suburb_key
where p.suburb_key is null;
```

```sql
select count(*) as population_metrics_without_suburb
from public.suburb_population_metrics p
left join public.suburbs s
  on s.suburb_key = p.suburb_key
where s.suburb_key is null;
```

`quarterly_without_population` can be non-zero only when the missing suburbs
are explicitly accepted as a source-data coverage gap. `population_metrics_without_suburb`
must be `0`.

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
- population coverage has been audited, and any missing rows are documented
- monthly AI context jobs have been enqueued for all metric suburbs, even if
  the user-facing report flow does not depend on live context

Then test:

```text
Generate Recommendation
-> select suburbs
-> create report draft
-> preview PDF
-> export/store PDF
-> retrieve report by code
```
