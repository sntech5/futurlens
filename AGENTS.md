# FuturLens Agent Instructions

This repository uses task-specific agent prompt files under `.agents/`.

## Suburb Data Refresh

When the user asks to run, prepare, validate, or continue a suburb data refresh, first read:

- `.agents/suburb-data-refresh-agent.md`
- `.agents/suburb-data-refresh-checklist.md`
- `Docs/suburb_data_refresh_agent_strategy.md`
- `Docs/suburb_metrics_csv_ingestion_playbook.md`
- `sql/incremental_suburb_key_metrics_refresh_runbook.sql`

Required behavior:

- Start in `dry_run` mode unless the user explicitly says `incremental` or `full_reload`.
- Ask only for the four required setup inputs first:
  - refresh mode
  - target `quarter_period`
  - market metrics CSV path
  - whether a population metrics CSV is available
- Do not move to the next stage until the user confirms the current stage is done.
- Run Supabase SQL instructions one numbered query at a time.
- Never create duplicate suburbs in `public.suburbs`; suburb master rows must be upserted by canonical `suburb_key`.
- Never invent missing data.
- Never load directly into `public.suburb_base_scores`.
- Use staging tables before loading production tables.
- Stop on hard validation failures and document soft gaps.

