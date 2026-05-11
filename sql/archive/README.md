# SQL Archive

This folder contains superseded SQL patches and diagnostics kept for audit
history only.

Do not apply these files to the current database unless you are deliberately
reconstructing an old incident or migration step. Several archived patches
reference retired fields such as `base_total_score` and can overwrite current
scoring v2 behavior if re-run.

Current scoring and recommendation function references live in:

- `sql/patch_drop_base_total_score_scoring_v2.sql`
- `sql/patch_scoring_model_v2_strategy_totals.sql`
- `sql/patch_scoring_model_v2_risk_safety_and_yield_bands.sql`
- `sql/validate_scoring_model_v2.sql`
- `sql/incremental_suburb_key_metrics_refresh_runbook.sql`
