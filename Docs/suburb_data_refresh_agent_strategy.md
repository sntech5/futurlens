# Suburb Data Refresh Agent Strategy

Purpose:
- define how to set up an agent-assisted workflow for refreshing new suburb data into Supabase
- reduce manual SQL copy/paste while preserving the no-made-up-data guardrail
- keep market metrics, population metrics, score refreshes, validation, and AI context cache refreshes in the correct order

Primary references:
- [suburb_metrics_csv_ingestion_playbook.md](suburb_metrics_csv_ingestion_playbook.md)
- [prod_data_reload_playbook.md](prod_data_reload_playbook.md)
- [incremental_suburb_key_metrics_refresh_runbook.sql](../sql/incremental_suburb_key_metrics_refresh_runbook.sql)
- [postload_validate_prod.sql](../sql/postload_validate_prod.sql)
- [smoke_recommendation_2min.sql](../sql/smoke_recommendation_2min.sql)
- [no_made_up_data_guardrail.md](no_made_up_data_guardrail.md)

## Recommended Agent Scope

The first version should be an operator-assist agent, not a fully autonomous production writer.

The agent should:
- inspect CSV headers before import
- tell the operator exactly which staging table to truncate
- verify staging row counts after import
- run or provide the correct SQL in sequence
- summarize validation results
- stop on hard failures
- document soft gaps such as missing population coverage

The agent should not:
- invent missing values
- bypass staging tables
- write directly to `public.suburb_base_scores`
- run destructive reset scripts unless the operator explicitly selects a full reload mode
- silently continue after failed integrity checks

## Agent Modes

### 1. Dry Run

Use before any data import.

Inputs:
- market metrics CSV
- optional population metrics CSV
- target quarter period, e.g. `2026-06`

Agent actions:
- validate file presence
- validate expected headers
- check whether target quarter already exists
- produce a refresh plan
- list expected SQL stages

Outputs:
- header compatibility result
- missing/extra column list
- target quarter confirmation
- required manual import instructions

### 2. Incremental Refresh

Use for the normal quarterly or ad hoc addition of suburbs.

Inputs:
- market metrics CSV
- optional population metrics CSV
- target quarter period

Agent actions:
- guide operator to truncate `public.suburb_import_staging`
- guide operator to import market CSV into `public.suburb_import_staging`
- validate staging rows
- run suburb master sync
- run quarterly metrics load
- run base score refresh
- audit population coverage
- optionally guide population staging import/load
- refresh scores again after population load
- enqueue AI context refresh jobs
- run post-load validation
- run recommendation smoke test

Outputs:
- loaded quarterly row count
- refreshed score row count
- missing population count/list
- AI context queue counts
- validation pass/fail summary
- smoke-test summary

### 3. Full Reload

Use only for controlled reset/rebuild events.

Required human gates:
- written confirmation that generated reports/recommendations may be affected
- backup/snapshot confirmation
- explicit approval to run reset scripts

Agent actions:
- follow [prod_data_reload_playbook.md](prod_data_reload_playbook.md)
- refuse to proceed without backup confirmation

## Pipeline Stages

| Stage | Agent responsibility | Hard stop? |
|---|---|---:|
| `preflight` | Capture row counts and FK health before touching staging. | Yes |
| `market_header_check` | Validate CSV headers against `public.suburb_import_staging` contract. | Yes |
| `market_stage_prepare` | Instruct/execute `truncate table public.suburb_import_staging restart identity;`. | Yes |
| `market_stage_import` | Operator imports CSV through Supabase UI or future upload function. | Yes |
| `market_stage_validate` | Check staging row count, required source fields, duplicate keys. | Yes |
| `suburb_master_sync` | Upsert `public.suburbs` from staging source identity fields. | Yes |
| `quarterly_metrics_load` | Run `sql/load_suburb_key_metrics_quarterly_from_staging.sql`. | Yes |
| `base_scores_refresh` | Run `select public.refresh_suburb_base_scores();`. | Yes |
| `population_audit` | Run missing population coverage diagnostics. | No |
| `population_stage_load` | Optional staging/import/load for population metrics. | Yes if selected |
| `ai_context_enqueue` | Run `select * from public.enqueue_suburb_context_refresh_jobs();`. | No |
| `postload_validate` | Run [postload_validate_prod.sql](../sql/postload_validate_prod.sql). | Yes |
| `smoke_test` | Run [smoke_recommendation_2min.sql](../sql/smoke_recommendation_2min.sql). | Recommended |
| `run_summary` | Write an operator-readable refresh summary. | Yes |

## Human-in-the-Loop Gates

The agent should ask for confirmation before:
- truncating staging tables
- importing a file over existing staging data
- running any destructive reset
- proceeding when population coverage gaps are above an agreed threshold
- deploying function/schema changes

The agent can proceed without confirmation for:
- read-only diagnostics
- generating SQL snippets
- summarizing validation output
- checking local CSV headers

## Data Contracts

### Market Metrics CSV

Must satisfy the schema in [suburb_metrics_csv_ingestion_playbook.md](suburb_metrics_csv_ingestion_playbook.md).

Required headers:
- `state`
- `post_code`
- `suburb`
- `typical_value`
- `gross_rental_yield`
- `vacancy_rate`
- `percent_stock_on_market`
- `days_on_market`
- `avg_vendor_discount`

Recommended:
- `percent_renters_in_market`

### Population Metrics CSV

Must load through `public.suburb_population_metrics_staging`.

Expected headers:
- `suburb_key`
- `suburb_name`
- `state`
- `postcode`
- `population_2025`
- `growth_2023_2024_pct`
- `growth_2024_2025_pct`

The population loader is intentionally tolerant of values like `2808.0`.

## Failure Policy

Hard failures:
- staging row count is zero after import
- required market headers are missing
- required market metrics are null for rows intended to load
- loaded quarterly rows have no matching suburb master
- base scores exist without quarterly source rows
- validation scripts show FK orphan rows

Soft failures:
- population metrics are missing for some suburbs
- AI context jobs are queued but not completed
- OpenAI context cache is missing for newly added suburbs

Soft failures must be recorded in the refresh summary, but they do not need to block MVP app use if the frontend/report hides unavailable values.

## Suggested Agent Architecture

### Phase 1: Codex/Operator Runbook Agent

This is the lowest-risk starting point.

Capabilities:
- local CSV header inspection
- SQL step generation
- validation result interpretation
- refresh summary creation

The operator still performs:
- Supabase CSV import through UI
- production confirmation gates

### Phase 2: Supabase CLI-Assisted Agent

Add controlled CLI execution where practical.

Capabilities:
- run read-only Supabase SQL checks
- run non-destructive refresh functions
- produce machine-readable summaries

Still keep human approval for:
- staging truncation
- imports
- destructive reset

### Phase 3: Backend Refresh Service

Build a first-class admin-only refresh service.

Components:
- upload endpoint for CSV files
- staging import worker
- validation job table
- refresh run audit table
- downloadable exception reports

Recommended tables:
- `public.data_refresh_runs`
- `public.data_refresh_run_steps`
- `public.data_refresh_exceptions`

This gives traceability beyond chat/operator memory.

## Agent Prompt Contract

Use this as the standing instruction for the refresh agent:

```text
You are the FuturLens suburb data refresh agent.

Your job is to help refresh source-backed suburb data into Supabase.
Follow Docs/suburb_metrics_csv_ingestion_playbook.md and never invent missing data.

Always:
- identify refresh mode: dry_run, incremental, or full_reload
- confirm target quarter_period
- validate CSV headers before import
- use staging tables first
- run validations after each load stage
- stop on hard failures
- document soft gaps
- summarize row counts and exceptions

Never:
- load directly into suburb_base_scores
- create metrics from suburb master rows alone
- overwrite real metrics with nulls from incomplete source files
- run reset scripts without explicit backup and operator approval
```

## First Implementation Backlog

1. Create a local CSV header checker script for market and population files.
2. Add a refresh summary template under `Docs/refresh_runs/`.
3. Create SQL views or functions for pass/fail validation gates.
4. Add a `data_refresh_runs` audit table.
5. Convert the incremental SQL runbook into smaller callable SQL functions.
6. Add an admin-only upload/refresh workflow in the app.

## Success Criteria

A refresh agent run is successful when:
- quarterly market data is loaded for the target quarter
- `public.suburb_base_scores` is refreshed only from source-backed quarterly rows
- recommendation smoke test completes
- post-load validation has no hard failures
- population gaps are listed, not hidden
- AI context refresh jobs are enqueued for all metric suburbs
- the operator receives a concise refresh summary with counts and exceptions
