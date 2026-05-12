# Suburb Data Refresh Summary

Date:
Operator:
Refresh mode:
Target quarter_period:

## Source Files

Market metrics CSV:
Population metrics CSV:

## Preflight

Row counts before refresh:

| Table | Count |
|---|---:|
| public.suburbs | |
| public.suburb_import_staging | |
| public.suburb_key_metrics_quarterly | |
| public.suburb_base_scores | |
| public.suburb_population_metrics | |
| public.suburb_population_metrics_staging | |

Notes:

## Market Staging

Staging truncated:
Market CSV imported:
Staging row count:

Header validation:
Duplicate suburb_key check:
Suburb master duplicate risk:

Notes:

## Quarterly Metrics Load

Rows loaded/updated:
Target quarter_period:
Rows skipped:
Reason for skipped rows:

Notes:

## Score Refresh

refresh_suburb_base_scores run:
Base score rows refreshed:
Scoring validation result:

Notes:

## Population Coverage

Population CSV provided:
Population rows staged:
Population rows loaded/updated:
Missing population count:
Missing population suburbs/list:

Notes:

## AI Context Queue

enqueue_suburb_context_refresh_jobs run:
Jobs inserted:
Jobs already existing:
Total jobs for month:
Queue gaps:

Notes:

## Postload Validation

postload_validate_prod.sql run:

Hard gate result:
Soft warnings:

Notes:

## Smoke Test

smoke_recommendation_2min.sql run:

Normal scenario:
Restrictive scenario:
Payload key check:

Notes:

## Final Status

Status: pass / pass_with_warnings / failed

Operator notes:
Follow-up actions: