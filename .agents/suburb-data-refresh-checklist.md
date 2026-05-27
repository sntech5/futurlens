# Suburb Data Refresh Checklist

Use this checklist for every suburb data refresh.

## 0. Setup

- [ ] Refresh mode confirmed: dry_run / incremental / full_reload
- [ ] Target quarter_period confirmed, e.g. 2026-06
- [ ] Market metrics CSV path provided
- [ ] Population metrics CSV path provided or explicitly skipped
- [ ] Operator confirms this is not a destructive full reload unless full_reload mode is selected

## 1. CSV Header Validation

Market metrics CSV must include:
- [ ] state
- [ ] post_code
- [ ] suburb
- [ ] typical_value
- [ ] gross_rental_yield
- [ ] vacancy_rate
- [ ] percent_stock_on_market
- [ ] days_on_market
- [ ] avg_vendor_discount

Recommended:
- [ ] percent_renters_in_market

Population metrics CSV, if provided, should include:
- [ ] suburb_key
- [ ] suburb_name
- [ ] state
- [ ] postcode
- [ ] population_2025
- [ ] growth_2023_2024_pct
- [ ] growth_2024_2025_pct

## 2. Preflight

- [ ] Capture row counts
- [ ] Check existing FK/orphan issues
- [ ] Check whether target quarter already exists
- [ ] Confirm staging tables can be cleared

## 3. Market Staging

- [ ] Truncate public.suburb_import_staging
- [ ] Import market CSV into public.suburb_import_staging
- [ ] Validate staging row count > 0
- [ ] Validate required market fields are present
- [ ] Validate staged suburb keys are canonical
- [ ] Confirm no duplicate suburb master records will be created

## 4. Suburb Master Sync

- [ ] Upsert public.suburbs by canonical suburb_key
- [ ] Confirm no staged suburb has missing state/postcode/suburb name
- [ ] Confirm no duplicate public.suburbs rows exist by suburb_key

## 5. Quarterly Metrics Load

- [ ] Load public.suburb_key_metrics_quarterly from staging
- [ ] Confirm rows loaded for target quarter_period
- [ ] Confirm no quarterly metric rows lack suburb master records
- [ ] Confirm required metrics are not null for loaded rows

## 6. Score Refresh

- [ ] Run select public.refresh_suburb_base_scores();
- [ ] Confirm public.suburb_base_scores refreshed
- [ ] Confirm no base score rows exist without quarterly source rows

## 7. Population Coverage

- [ ] Run missing population audit
- [ ] If gaps exist, remind operator to use the `/abs-population-finder` skill in Manus to source verified population rows for the missing suburbs
- [ ] If population CSV exists, truncate public.suburb_population_metrics_staging
- [ ] Import population CSV into public.suburb_population_metrics_staging
- [ ] Load public.suburb_population_metrics from staging
- [ ] Refresh scores again after population load
- [ ] Document any remaining missing population rows

## 8. AI Context Queue

- [ ] Run select * from public.enqueue_suburb_context_refresh_jobs();
- [ ] Confirm queue count matches metric suburb count for the month, or document gap

## 9. Validation

- [ ] Run sql/postload_validate_prod.sql
- [ ] Confirm hard validation gates pass
- [ ] Document soft warnings

## 10. Smoke Test

- [ ] Run sql/smoke_recommendation_2min.sql
- [ ] Confirm normal scenario returns array
- [ ] Confirm restrictive scenario returns array, possibly empty
- [ ] Confirm expected payload keys exist

## 11. Refresh Summary

Record:
- [ ] Refresh mode
- [ ] Target quarter_period
- [ ] Market staging row count
- [ ] Quarterly rows loaded
- [ ] Base score rows refreshed
- [ ] Population rows loaded
- [ ] Missing population count/list
- [ ] AI jobs enqueued
- [ ] Validation result
- [ ] Smoke test result
- [ ] Operator notes
