# Production Data Reload Playbook

Last updated: 2026-04-23 (Australia/Sydney)

## Goal
Replace dummy domain data with production data while preserving key relationships, constraints, and app stability.

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
- Reference: [sql_reference_recommendation_pdf_reports.md](sql_reference_recommendation_pdf_reports.md)

3. Reset (destructive):
[reset_domain_data_prod.sql](../sql/reset_domain_data_prod.sql)

4. Load data:
- load `suburbs` first
- load `suburb_import_staging`
- transform/load `suburb_base_scores`
- load/update monthly and quarterly snapshot tables (if used)

5. Recompute:
- `select public.refresh_base_growth_scores();`
- Reference: [sql_reference_refresh_base_growth_scores.md](sql_reference_refresh_base_growth_scores.md)

6. Validate:
[postload_validate_prod.sql](../sql/postload_validate_prod.sql)

7. Smoke test:
[smoke_recommendation_2min.sql](../sql/smoke_recommendation_2min.sql)

## Load Order Details
- `suburbs` must exist before tables that reference `suburb_key`.
- `suburb_base_scores` load should happen after suburb master is ready.
- `recommendation_runs` and `recommendations` are app-generated; do not bulk-fill unless intentional.
- `recommendation_reports` and `recommendation_report_suburbs` are app-generated report records; preserve them unless intentionally resetting generated report history.

## Success Criteria
- No FK-orphan rows in post-load validation.
- No critical nulls in key base score fields.
- Recommendation smoke passes with array output for `top_suburbs`.
- Restrictive scenario returns empty array, not failure.
