# SQL Reference: smoke_recommendation_2min.sql

File:
[smoke_recommendation_2min.sql](../sql/smoke_recommendation_2min.sql)

## Context
Fast release-gate smoke for recommendation flow.

## Purpose
- Confirm normal run returns array output.
- Confirm restrictive run returns array (including empty array) without crash.
- Confirm basic payload key shape.

## Execution Notes
- Runs in a transaction and rolls back.
- Use before release cut or after backend function changes.

