# Feature Requests

Purpose:
- capture product and operational improvements that should be considered after the current milestone work
- keep useful ideas visible without derailing the active implementation path

## Open Requests

### 1. CSV Header Normalizer For Staging Imports

Status:
- requested

Problem:
- fresh suburb metric CSV files often arrive with header names that do not exactly match
  `public.suburb_import_staging`
- this causes repeated manual cleanup before every import or refresh
- import failures slow down the quarterly data refresh workflow

Requested feature:
- develop a script that automatically converts incoming CSV field names into the exact
  staging-table-compatible header names required by `public.suburb_import_staging`

Desired behavior:
- accept a source CSV file with common header variants
- normalize header names to the required staging schema
- preserve all row data
- flag unknown or unmapped columns clearly
- optionally emit a cleaned CSV ready for Supabase import

Target staging schema:

```text
state
post_code
suburb
avg_vendor_discount
days_on_market
demand_to_supply_ratio
percent_renters_in_market
percent_stock_on_market
statistical_reliability
typical_value
vacancy_rate
gross_rental_yield
```

Why it matters:
- reduces manual effort every quarter
- lowers the chance of import errors caused by header mismatches
- makes the data refresh process more repeatable and less fragile

Suggested milestone fit:
- Milestone 4 follow-on operational improvement

### 2. One-Click Data Ingestion And Validation Workflow

Status:
- requested

Problem:
- refreshing fresh suburb data currently requires running multiple SQL steps manually
- the process is error-prone because each refresh depends on the correct order of:
  staging import, suburb master sync, quarterly metric load, base score refresh, and validation
- manual copy/paste makes every refresh slower and increases the chance of missing a step

Requested feature:
- develop a single-action workflow that runs all required SQL steps for data ingestion,
  refresh, and validation in the correct order

Desired behavior:
- trigger one workflow action after the CSV has been loaded into `public.suburb_import_staging`
- insert or update missing suburb master rows in `public.suburbs`
- load metrics into `public.suburb_key_metrics_quarterly`
- refresh `public.suburb_base_scores`
- run validation checks automatically
- produce a clear success/failure summary with counts and any blocking issues

Suggested workflow sequence:

```text
suburb_import_staging
-> suburbs sync
-> suburb_key_metrics_quarterly load
-> refresh_suburb_base_scores()
-> validation summary
```

Why it matters:
- reduces repeated manual SQL work every refresh cycle
- lowers the chance of operator error
- makes quarterly refreshes predictable and faster
- improves confidence before end-to-end app testing

Suggested milestone fit:
- Milestone 4 operational improvement before repeat refresh cycles
