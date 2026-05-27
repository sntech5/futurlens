# Suburb Data Refresh Summary

Date: 2026-05-27
Operator: Sujith / Codex
Refresh mode: incremental
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
- numeric values requiring loader cleanup: 287

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

Missing suburb master rows identified before sync:

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

## Market Staging

Staging truncated: yes
Market CSV imported: yes

Staging validation:

| staging_rows | missing_key_parts | missing_required_metric_values |
|---:|---:|---:|
| 41 | 0 | 0 |

## Suburb Master Sync

Suburb master sync completed using upsert by canonical `suburb_key`.

Validation:
- staged keys without suburb master: 0
- duplicate suburb master rows after sync: 0

Notes:
- The 10 missing suburb master rows were added.
- Existing suburb master rows were not duplicated.

## Quarterly Metrics Load

Quarterly business-key guardrail:
- duplicate `suburb_key + quarter_period` rows before load: 0

Quarterly uniqueness index confirmed:
- `suburb_key_metrics_quarterly_suburb_key_period_uidx`

Quarterly load completed:
- target `quarter_period`: 2026-06
- behavior: upsert by `suburb_key + quarter_period`

Load validation:

| staged_valid_source_rows | staged_valid_rows_loaded_to_quarter | quarterly_rows_missing_required_metrics |
|---:|---:|---:|
| 41 | 41 | 0 |

## Score Refresh

`public.refresh_suburb_base_scores()` run: yes

Score validation:

| base_score_rows | base_scores_without_quarterly_source | null_suburb_key_rows |
|---:|---:|---:|
| 276 | 0 | 0 |

## Population Coverage

Population CSV provided: no

Population coverage for `2026-06`:

| quarterly_suburbs_for_target_period | suburbs_with_population_metrics | suburbs_missing_population_metrics |
|---:|---:|---:|
| 276 | 246 | 30 |

Missing population metrics:

| suburb_key | suburb_name | state | postcode |
|---|---|---|---|
| BATEHAVEN_NSW_2536 | BATEHAVEN | NSW | 2536 |
| BILAMBIL HEIGHTS_NSW_2486 | BILAMBIL HEIGHTS | NSW | 2486 |
| BOAMBEE EAST_NSW_2452 | BOAMBEE EAST | NSW | 2452 |
| BOOROOMA_NSW_2650 | BOOROOMA | NSW | 2650 |
| BOURKELANDS_NSW_2650 | BOURKELANDS | NSW | 2650 |
| EAST ALBURY_NSW_2640 | EAST ALBURY | NSW | 2640 |
| EAST TAMWORTH_NSW_2340 | EAST TAMWORTH | NSW | 2340 |
| ESTELLA_NSW_2650 | ESTELLA | NSW | 2650 |
| GLENFIELD PARK_NSW_2650 | GLENFIELD PARK | NSW | 2650 |
| HILLVUE_NSW_2340 | HILLVUE | NSW | 2340 |
| KOORINGAL_NSW_2650 | KOORINGAL | NSW | 2650 |
| LLANARTH_NSW_2795 | LLANARTH | NSW | 2795 |
| LLOYD_NSW_2650 | LLOYD | NSW | 2650 |
| METFORD_NSW_2323 | METFORD | NSW | 2323 |
| MURWILLUMBAH_NSW_2484 | MURWILLUMBAH | NSW | 2484 |
| NAMBUCCA HEADS_NSW_2448 | NAMBUCCA HEADS | NSW | 2448 |
| SOUTH BATHURST_NSW_2795 | SOUTH BATHURST | NSW | 2795 |
| SOUTH GRAFTON_NSW_2460 | SOUTH GRAFTON | NSW | 2460 |
| SOUTH NOWRA_NSW_2541 | SOUTH NOWRA | NSW | 2541 |
| SPRINGDALE HEIGHTS_NSW_2641 | SPRINGDALE HEIGHTS | NSW | 2641 |
| SUNSHINE BAY_NSW_2536 | SUNSHINE BAY | NSW | 2536 |
| THURGOONA_NSW_2640 | THURGOONA | NSW | 2640 |
| TOORMINA_NSW_2452 | TOORMINA | NSW | 2452 |
| TULLIMBAR_NSW_2527 | TULLIMBAR | NSW | 2527 |
| TWEED HEADS SOUTH_NSW_2486 | TWEED HEADS SOUTH | NSW | 2486 |
| WEST BALLINA_NSW_2478 | WEST BALLINA | NSW | 2478 |
| WEST BATHURST_NSW_2795 | WEST BATHURST | NSW | 2795 |
| WEST NOWRA_NSW_2541 | WEST NOWRA | NSW | 2541 |
| WINDRADYNE_NSW_2795 | WINDRADYNE | NSW | 2795 |
| WOODBERRY_NSW_2322 | WOODBERRY | NSW | 2322 |

Status:
- Soft gap documented.
- Not blocking because no population CSV was provided.

## AI Context Queue

Function confirmed:
- `public.enqueue_suburb_context_refresh_jobs(p_refresh_month date, p_ai_provider text, p_model text, p_prompt_version text, p_priority integer)`

Jobs enqueued:

| inserted_count | existing_count | total_for_month |
|---:|---:|---:|
| 276 | 0 | 276 |

Parameters used:
- refresh_month: 2026-05-01
- ai_provider: openai
- model: gpt-5-2025-08-07
- prompt_version: suburb_context_facts_v1
- priority: 5

## Postload Validation

Row counts after refresh:

| Table | Count |
|---|---:|
| public.suburbs | 745 |
| public.suburb_import_staging | 41 |
| public.suburb_key_metrics_quarterly | 276 |
| public.suburb_base_scores | 276 |
| public.suburb_population_metrics | 658 |
| public.suburb_context_refresh_jobs | 705 |

Integrity validation:

| Check | Result |
|---|---:|
| base_scores_without_suburb | 0 |
| quarterly_without_suburb | 0 |
| null_suburb_key_rows | 0 |
| null_price_rows | 0 |
| null_rent_rows | 0 |
| quarterly_rows_missing_required_metrics | 0 |
| empty_base_score_rows | 0 |
| base_scores_without_quarterly_source | 0 |

Function readiness:

| Function | Args |
|---|---|
| refresh_base_growth_scores | |
| refresh_suburb_base_scores | |
| run_recommendation_engine | p_run_id uuid |

## Smoke Test

Smoke user:
- `59bd7386-4695-4900-87a7-b4d9c00c5f9d`

Recommendation smoke test:
- result: success
- transaction rolled back

## Final Status

Status: pass_with_warnings

Hard gates:
- passed

Soft warnings:
- 30 `2026-06` metric suburbs are missing population metrics.
- AI context jobs were queued but completion was not checked in this run.

Follow-up actions:
- Add a population metrics CSV later for the 30 missing suburbs.
- Process or monitor AI context refresh jobs.
- Optionally clear `public.suburb_import_staging` after confirming no further import audit is needed.
