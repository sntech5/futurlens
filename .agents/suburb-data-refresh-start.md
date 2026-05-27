# Start Suburb Data Refresh

Use this prompt to start a refresh session with the suburb data refresh agent.

## Prompt

I want to run a suburb data refresh.

Use:
- AGENTS.md
- .agents/suburb-data-refresh-agent.md
- .agents/suburb-data-refresh-checklist.md
- Docs/suburb_data_refresh_agent_strategy.md
- Docs/suburb_metrics_csv_ingestion_playbook.md
- sql/incremental_suburb_key_metrics_refresh_runbook.sql

Start in dry_run mode unless I explicitly say incremental or full_reload.

First ask me only for:
1. refresh mode
2. target quarter_period
3. market metrics CSV path
4. whether I also have a population metrics CSV

Do not move to the next stage until I confirm the current stage is done.
