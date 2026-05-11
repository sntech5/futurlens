# SQL Reference: Archived run recommendation engine patch

File:
[patch_run_recommendation_engine_no_null_top_suburbs.sql](../sql/archive/patch_run_recommendation_engine_no_null_top_suburbs.sql)

Status:
Archived. This patch is kept for incident history only. The current
recommendation engine implementation is maintained through scoring v2 patches,
especially [patch_drop_base_total_score_scoring_v2.sql](../sql/patch_drop_base_total_score_scoring_v2.sql).

## Context
Fixes production/runtime failure where `recommendations.top_suburbs` violated NOT NULL on restrictive/no-match runs.

## Purpose
- Ensure `top_suburbs` is always a JSON array (`[]` when no matches).
- Preserve function signature: `public.run_recommendation_engine(p_run_id uuid)`.

## Expected Outcome
- No `23502` null-constraint errors on `top_suburbs`.
- Restrictive runs produce valid recommendation rows with empty `top_suburbs`.
