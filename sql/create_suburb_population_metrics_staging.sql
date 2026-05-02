-- Purpose:
-- Temporary import workspace for suburb population metric CSV files.
--
-- Import CSVs here first instead of importing directly into
-- public.suburb_population_metrics. This staging table keeps numeric columns as
-- text so source files with values like "2808.0" can be cleaned before loading
-- into integer/numeric final columns.

create table if not exists public.suburb_population_metrics_staging (
  id text,
  suburb_key text,
  suburb_name text,
  state text,
  postcode text,
  population_2025 text,
  growth_2023_2024_pct text,
  growth_2024_2025_pct text,
  source_level text,
  allocation_method text,
  source_year text,
  source_name text,
  created_at text,
  updated_at text
);

alter table public.suburb_population_metrics_staging
  add column if not exists id text,
  add column if not exists suburb_key text,
  add column if not exists suburb_name text,
  add column if not exists state text,
  add column if not exists postcode text,
  add column if not exists population_2025 text,
  add column if not exists growth_2023_2024_pct text,
  add column if not exists growth_2024_2025_pct text,
  add column if not exists source_level text,
  add column if not exists allocation_method text,
  add column if not exists source_year text,
  add column if not exists source_name text,
  add column if not exists created_at text,
  add column if not exists updated_at text;
