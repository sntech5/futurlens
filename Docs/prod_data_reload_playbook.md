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

2. Reset (destructive):
[reset_domain_data_prod.sql](../sql/reset_domain_data_prod.sql)

3. Load data:
- load `suburbs` first
- load `suburb_import_staging`
- transform/load `suburb_base_scores`
- load/update monthly and quarterly snapshot tables (if used)

4. Recompute:
- `select public.refresh_base_growth_scores();`

5. Validate:
[postload_validate_prod.sql](../sql/postload_validate_prod.sql)

6. Smoke test:
[smoke_recommendation_2min.sql](../sql/smoke_recommendation_2min.sql)

## Load Order Details
- `suburbs` must exist before tables that reference `suburb_key`.
- `suburb_base_scores` load should happen after suburb master is ready.
- `recommendation_runs` and `recommendations` are app-generated; do not bulk-fill unless intentional.

## Success Criteria
- No FK-orphan rows in post-load validation.
- No critical nulls in key base score fields.
- Recommendation smoke passes with array output for `top_suburbs`.
- Restrictive scenario returns empty array, not failure.

