# Suburb Data Refresh Summary

Date: 2026-05-26
Operator: Sujith / Codex
Refresh mode: dry_run
Target quarter_period: 2026-06

## Source Files

Market metrics CSV:
`../futurlens_data/temp_csv/DSR-Data-NSW-Run2-26thMay2026.csv`

Population metrics CSV:
Not provided.

## CSV Validation

Market CSV data rows: 41

Required headers present:
- state
- post_code
- suburb
- typical_value
- gross_rental_yield
- vacancy_rate
- percent_stock_on_market
- days_on_market
- avg_vendor_discount

Recommended headers present:
- percent_renters_in_market

CSV key checks:
- blank identity rows: 0
- duplicate suburb keys in CSV: 0
- numeric parse issues: 0
- numeric values requiring cleaning: 287

Notes:
- Values such as `$923,200`, `4.63%`, and `30days` require standard loader cleaning.
- No population CSV is included in this refresh.

## Preflight

Row counts before refresh:

| Table | Count |
|---|---:|
| public.suburbs | 735 |
| public.suburb_import_staging | 47 |
| public.suburb_key_metrics_quarterly | 264 |
| public.suburb_base_scores | 264 |
| public.suburb_population_metrics | 658 |

CSV suburb master coverage:

| CSV suburb count | Already in suburb master | Missing from suburb master |
|---:|---:|---:|
| 41 | 31 | 10 |

Missing suburb master rows:

| suburb_key | suburb_name | state | postcode |
|---|---|---|---|
| BILAMBIL HEIGHTS_NSW_2486 | BILAMBIL HEIGHTS | NSW | 2486 |
| EAST ALBURY_NSW_2640 | EAST ALBURY | NSW | 2640 |
| LLANARTH_NSW_2795 | LLANARTH | NSW | 2795 |
| METFORD_NSW_2323 | METFORD | NSW | 2323 |
| MURWILLUMBAH_NSW_2484 | MURWILLUMBAH | NSW | 2484 |
| NAMBUCCA HEADS_NSW_2448 | NAMBUCCA HEADS | NSW | 2448 |
| THURGOONA_NSW_2640 | THURGOONA | NSW | 2640 |
| TWEED HEADS SOUTH_NSW_2486 | TWEED HEADS SOUTH | NSW | 2486 |
| WEST BALLINA_NSW_2478 | WEST BALLINA | NSW | 2478 |
| WEST NOWRA_NSW_2541 | WEST NOWRA | NSW | 2541 |

Preflight integrity:

| Check | Result |
|---|---:|
| existing rows for quarter_period 2026-06 | 264 |
| duplicate suburb master rows | 0 |
| quarterly rows without suburb master | 0 |
| base score rows without quarterly source | 0 |

Notes:
- `public.suburb_import_staging` already contains 47 rows and must be cleared before any real import.
- `public.suburb_key_metrics_quarterly` already contains rows for `2026-06`; the real load must use upsert/merge behavior keyed by `suburb_key + quarter_period`.
- Do not create duplicate suburbs in `public.suburbs`. Only the 10 missing suburb keys should be inserted; existing suburb keys must be updated/upserted by canonical `suburb_key`.

## Stage 4: Staging / Import Plan

Status: planned only; not executed in dry_run.

Real incremental execution sequence, if approved later:

1. Clear market staging:
   `truncate table public.suburb_import_staging restart identity;`

2. Import market metrics CSV into:
   `public.suburb_import_staging`

3. Validate staging:
   - staging row count should be 41
   - missing key parts should be 0
   - missing required metric values should be 0

4. Sync suburb master by canonical `suburb_key`:
   - use upsert only
   - insert the 10 missing suburb keys listed above
   - do not duplicate the 31 existing suburb keys

5. Load quarterly metrics for `quarter_period = '2026-06'`:
   - use upsert by `suburb_key + quarter_period`
   - expected eligible source rows: 41
   - existing `2026-06` rows may be updated, not duplicated

6. Refresh base scores after quarterly metrics load:
   `select public.refresh_suburb_base_scores();`

7. Run post-load validation and smoke test only after the real load.

Dry-run decision:
- Preflight supports proceeding to an incremental refresh later.
- Current mode remains `dry_run`; no Supabase writes have been approved or performed.

## Final Status

Status: dry_run_stage_4_planned

Operator notes:
- Awaiting operator confirmation before any incremental write stage.
