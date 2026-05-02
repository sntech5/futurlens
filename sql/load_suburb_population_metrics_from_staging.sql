-- Purpose:
-- Load cleaned suburb population metrics from staging into
-- public.suburb_population_metrics.
--
-- No-made-up-data rules:
-- - Loads only rows with suburb_key values that exist in public.suburbs.
-- - Does not invent missing population or growth values.
-- - Converts whole-number decimal text like "2808.0" to integer population.
-- - Keeps ABS source/allocation metadata on the target table defaults.

with cleaned as (
  select
    upper(trim(suburb_key)) as suburb_key,
    nullif(trim(suburb_name), '') as suburb_name,
    upper(nullif(trim(state), '')) as state,
    nullif(trim(postcode), '') as postcode,
    nullif(regexp_replace(coalesce(population_2025, ''), '[^0-9.-]', '', 'g'), '')::numeric as population_2025_numeric,
    nullif(regexp_replace(coalesce(growth_2023_2024_pct, ''), '[^0-9.-]', '', 'g'), '')::numeric as growth_2023_2024_pct,
    nullif(regexp_replace(coalesce(growth_2024_2025_pct, ''), '[^0-9.-]', '', 'g'), '')::numeric as growth_2024_2025_pct,
    coalesce(nullif(trim(source_level), ''), 'SA2_ALLOCATED_TO_SUBURB') as source_level,
    coalesce(nullif(trim(allocation_method), ''), 'RESIDENTIAL_MB_PROPORTIONAL') as allocation_method,
    coalesce(nullif(regexp_replace(coalesce(source_year, ''), '[^0-9]', '', 'g'), '')::integer, 2025) as source_year,
    coalesce(nullif(trim(source_name), ''), 'ABS Regional Population 2024-25, Population estimates by SA2 and above') as source_name
  from public.suburb_population_metrics_staging
),
ready as (
  select
    c.suburb_key,
    coalesce(c.suburb_name, s.suburb_name) as suburb_name,
    coalesce(c.state, s.state) as state,
    coalesce(c.postcode, s.postcode) as postcode,
    round(c.population_2025_numeric)::integer as population_2025,
    c.growth_2023_2024_pct,
    c.growth_2024_2025_pct,
    c.source_level,
    c.allocation_method,
    c.source_year,
    c.source_name
  from cleaned c
  join public.suburbs s on s.suburb_key = c.suburb_key
  where c.suburb_key is not null
)
insert into public.suburb_population_metrics (
  suburb_key,
  suburb_name,
  state,
  postcode,
  population_2025,
  growth_2023_2024_pct,
  growth_2024_2025_pct,
  source_level,
  allocation_method,
  source_year,
  source_name
)
select
  suburb_key,
  suburb_name,
  state,
  postcode,
  population_2025,
  growth_2023_2024_pct,
  growth_2024_2025_pct,
  source_level,
  allocation_method,
  source_year,
  source_name
from ready
on conflict (suburb_key)
do update set
  suburb_name = excluded.suburb_name,
  state = excluded.state,
  postcode = excluded.postcode,
  population_2025 = excluded.population_2025,
  growth_2023_2024_pct = excluded.growth_2023_2024_pct,
  growth_2024_2025_pct = excluded.growth_2024_2025_pct,
  source_level = excluded.source_level,
  allocation_method = excluded.allocation_method,
  source_year = excluded.source_year,
  source_name = excluded.source_name;
