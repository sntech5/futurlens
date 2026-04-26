# SQL Reference: postload_validate_prod.sql

File:
[postload_validate_prod.sql](/Users/sujithnair/Documents/Passionproject/Suburb Recommender/sql/postload_validate_prod.sql)

## Context
Validation checkpoint after production data load.

## Purpose
- Verify row counts and FK consistency.
- Check critical nulls in key tables.
- Confirm recommendation-related functions are present.

## Execution Notes
- Read-only checks.
- Run after load and before reopening writes.

