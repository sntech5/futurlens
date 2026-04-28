# Production Data Reload Playbook

Last updated: 2026-04-23 (Australia/Sydney)

## Goal
Replace dummy domain data with production data while preserving key relationships, constraints, and app stability.

CSV/schema reference:
- [suburb_metrics_csv_ingestion_playbook.md](suburb_metrics_csv_ingestion_playbook.md)

Data integrity guardrail:
- no made-up suburb metrics should be loaded into production-facing recommendation/report tables
- do not create `suburb_base_scores` rows from suburb master records alone
- do not overwrite existing real metrics with nulls from incomplete source data
- see [no_made_up_data_guardrail.md](no_made_up_data_guardrail.md)

## Mandatory Sequence
1. Freeze writes to the app.
2. Take full backup/snapshot.
3. Run preflight checks.
4. Run reset script (destructive).
5. Load production source data in dependency order.
6. Run score-refresh functions.
7. Run post-load validations.
8. Run recommendation smoke tests.
9. Unfreeze writes.

## Scripts and Order
1. Preflight:
[preflight_prod_reload.sql](../sql/preflight_prod_reload.sql)

2. Apply/confirm app functions:
- [patch_run_recommendation_engine_no_null_top_suburbs.sql](../sql/patch_run_recommendation_engine_no_null_top_suburbs.sql)
- [create_recommendation_report_tables.sql](../sql/create_recommendation_report_tables.sql)
- [create_recommendation_report_functions.sql](../sql/create_recommendation_report_functions.sql)
- [create_recommendation_report_storage.sql](../sql/create_recommendation_report_storage.sql)
- [rename_suburb_quarterly_to_key_metrics.sql](../sql/rename_suburb_quarterly_to_key_metrics.sql)
- Reference: [sql_reference_recommendation_pdf_reports.md](sql_reference_recommendation_pdf_reports.md)

3. Reset (destructive):
[reset_domain_data_prod.sql](../sql/reset_domain_data_prod.sql)

4. Load data:
- load `suburbs` first
- load `suburb_import_staging`
- transform/load verified market metrics into `suburb_key_metrics_quarterly`
- refresh `suburb_base_scores` from `suburb_key_metrics_quarterly`

5. Recompute:
- `select public.refresh_suburb_base_scores();`
- Reference: [sql_reference_refresh_base_growth_scores.md](sql_reference_refresh_base_growth_scores.md)

Quarterly staging transform:
- [load_suburb_key_metrics_quarterly_from_staging.sql](../sql/load_suburb_key_metrics_quarterly_from_staging.sql)
- This transform derives `median_rent_weekly` only from real `typical_value` and `gross_rental_yield` source fields.
- If a required source metric is missing, the suburb is not loaded into `suburb_key_metrics_quarterly`.

Retired table:
- `public.suburb_monthly_data` is no longer part of active logic.
- Drop it only after backup using [drop_retired_suburb_monthly_data.sql](../sql/drop_retired_suburb_monthly_data.sql).

6. Validate:
[postload_validate_prod.sql](../sql/postload_validate_prod.sql)

7. Smoke test:
[smoke_recommendation_2min.sql](../sql/smoke_recommendation_2min.sql)

## Load Order Details
- `suburbs` must exist before tables that reference `suburb_key`.
- `suburb_key_metrics_quarterly` is the source table for current market metrics, including price, rent, yield, vacancy, stock, days on market, vendor discount, and supporting factors.
- `suburb_base_scores` is refreshed from `suburb_key_metrics_quarterly`; do not load it directly from suburb master records.
- `recommendation_runs` and `recommendations` are app-generated; do not bulk-fill unless intentional.
- `recommendation_reports` and `recommendation_report_suburbs` are app-generated report records; preserve them unless intentionally resetting generated report history.

## Success Criteria
- No FK-orphan rows in post-load validation.
- No critical nulls in key base score fields.
- No base score rows created solely from `suburbs` master records.
- Recommendation smoke passes with array output for `top_suburbs`.
- Restrictive scenario returns empty array, not failure.
