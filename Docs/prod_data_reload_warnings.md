# Production Reload Warnings

Last updated: 2026-04-23 (Australia/Sydney)

## Do Not Do These
- Do not run reset scripts directly on production without backup and freeze.
- Do not truncate `auth.users`/`user_profiles` unless explicitly planned.
- Do not load `suburb_base_scores` before `suburbs` (FK risk).
- Do not skip post-load integrity checks.
- Do not unfreeze writes before smoke tests pass.
- Do not run staging test scripts against prod without checking transactional behavior.

## Sequence Guardrails
- Always follow this order:
  1. preflight
  2. reset
  3. load master data
  4. load dependent score/snapshot data
  5. refresh scoring functions
  6. validate
  7. smoke test
  8. unfreeze writes

## High-Risk Mistakes
- Using `truncate ... cascade` blindly without confirming impact.
- Executing destructive SQL in the wrong environment.
- Reusing stale CSV headers that do not match staging import table columns.
- Forgetting to verify `run_recommendation_engine` patch is deployed (can reintroduce null `top_suburbs` failure).

## Rollback Readiness
- Keep latest backup reference ID before reset.
- Keep previous function DDL/version noted before patching.
- If post-load checks fail, halt traffic and restore from backup rather than hot-fixing under load.

