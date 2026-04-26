# SQL Reference: preflight_prod_reload.sql

File:
[preflight_prod_reload.sql](/Users/sujithnair/Documents/Passionproject/Suburb Recommender/sql/preflight_prod_reload.sql)

## Context
First step before any destructive production data reset.

## Purpose
- Snapshot row counts.
- Detect existing integrity anomalies.
- Confirm required functions exist.

## Execution Notes
- Read-only checks.
- Must be run before reset.

