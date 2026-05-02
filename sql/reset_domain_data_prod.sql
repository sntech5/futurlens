-- Reference: Docs/sql_reference_prod_reload_reset.md
-- Purpose: clear domain data in FK-safe order before production reload.
-- WARNING: destructive. Do NOT run unless backups are complete and writes are frozen.

begin;

-- Child tables first.
truncate table public.recommendations restart identity;
truncate table public.recommendation_runs restart identity;

-- Score/snapshot tables that depend on suburbs.
truncate table public.suburb_base_scores restart identity;
truncate table public.suburb_key_metrics_quarterly restart identity;
truncate table public.suburb_population_metrics restart identity;

-- Import staging.
truncate table public.suburb_import_staging restart identity;
truncate table public.suburb_population_metrics_staging restart identity;

-- Master data table.
truncate table public.suburbs restart identity;

-- Keep user_profiles/auth users intact by default.
-- If you intentionally need profile reset, do it in a separate controlled step.

commit;
