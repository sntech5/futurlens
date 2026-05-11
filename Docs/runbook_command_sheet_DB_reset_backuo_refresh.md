# Runbook Command Sheet (Staging and Production)

Last updated: 2026-04-23 (Australia/Sydney)

## References
- Main sequence: [prod_data_reload_playbook.md](./prod_data_reload_playbook.md)
- Warnings: [prod_data_reload_warnings.md](./prod_data_reload_warnings.md)

## Staging Window (Copy/Paste Order)

1. Preflight checks
```sql
-- sql/preflight_prod_reload.sql
```

2. Apply/confirm function patch
```sql
-- sql/patch_drop_base_total_score_scoring_v2.sql
-- sql/validate_scoring_model_v2.sql
```

3. Apply/confirm report schema and functions
```sql
-- sql/create_recommendation_report_tables.sql
-- sql/create_recommendation_report_functions.sql
-- sql/create_recommendation_report_storage.sql
```

4. Reset domain data
```sql
-- sql/reset_domain_data_prod.sql
```

5. Load staging data in this order
1. `suburbs`
2. `suburb_import_staging`
3. transform to `suburb_key_metrics_quarterly`
4. refresh `suburb_base_scores`

6. Recompute scores
```sql
select public.refresh_suburb_base_scores();
```

7. Post-load validation
```sql
-- sql/postload_validate_prod.sql
```

8. Function assertions
```sql
-- sql/test_recommendation_engine.sql
```

9. Fast smoke
```sql
-- sql/smoke_recommendation_2min.sql
```

10. UI smoke
- Follow: [ui_smoke_checklist_2min.md](./ui_smoke_checklist_2min.md)

Staging go/no-go:
- Go only if all SQL checks pass and UI smoke has no blocker.

## Production Window (Copy/Paste Order)

0. Freeze app writes (maintenance mode)
- Confirm no active write jobs.

1. Backup/snapshot (mandatory hold point)
- Take full backup before running any reset script.
- Record backup ID/time in change log.

2. Preflight checks
```sql
-- sql/preflight_prod_reload.sql
```

3. Apply/confirm function patch
```sql
-- sql/patch_drop_base_total_score_scoring_v2.sql
-- sql/validate_scoring_model_v2.sql
```

4. Apply/confirm report schema and functions
```sql
-- sql/create_recommendation_report_tables.sql
-- sql/create_recommendation_report_functions.sql
-- sql/create_recommendation_report_storage.sql
```

5. Reset domain data (destructive)
```sql
-- sql/reset_domain_data_prod.sql
```

6. Load production data in this order
1. `suburbs`
2. `suburb_import_staging`
3. transform to `suburb_key_metrics_quarterly`
4. refresh `suburb_base_scores`

7. Recompute scores
```sql
select public.refresh_suburb_base_scores();
```

8. Post-load validation
```sql
-- sql/postload_validate_prod.sql
```

9. Fast smoke
```sql
-- sql/smoke_recommendation_2min.sql
```

10. Optional deeper assertions (recommended during low traffic)
```sql
-- sql/test_recommendation_engine.sql
```

11. UI smoke
- Follow: [ui_smoke_checklist_2min.md](./ui_smoke_checklist_2min.md)

12. Unfreeze writes
- Reopen traffic only after validation + smoke pass.

## Rollback Trigger Conditions
- Any FK integrity check returns non-zero orphan counts.
- Recommendation smoke fails.
- UI shows failed generation or malformed output.

If triggered:
1. Keep writes frozen.
2. Restore backup.
3. Re-run preflight and smoke checks.
