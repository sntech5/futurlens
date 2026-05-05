-- Purpose:
-- Find current quarterly market-metric suburbs that do not yet have source-backed
-- population metrics.
--
-- Use this when preparing a population-metrics backfill CSV for
-- public.suburb_population_metrics_staging.
--
-- Safe: read-only checks.

select
  count(*) as quarterly_without_population
from public.suburb_key_metrics_quarterly q
left join public.suburb_population_metrics p
  on p.suburb_key = q.suburb_key
where p.suburb_key is null;

select
  s.state,
  count(*) as missing_population_count
from public.suburb_key_metrics_quarterly q
join public.suburbs s
  on s.suburb_key = q.suburb_key
left join public.suburb_population_metrics p
  on p.suburb_key = q.suburb_key
where p.suburb_key is null
group by s.state
order by missing_population_count desc, s.state;

select
  q.suburb_key,
  s.suburb_name,
  s.state,
  s.postcode
from public.suburb_key_metrics_quarterly q
join public.suburbs s
  on s.suburb_key = q.suburb_key
left join public.suburb_population_metrics p
  on p.suburb_key = q.suburb_key
where p.suburb_key is null
order by s.state, s.suburb_name, s.postcode;

with missing as (
  select
    q.suburb_key
  from public.suburb_key_metrics_quarterly q
  left join public.suburb_population_metrics p
    on p.suburb_key = q.suburb_key
  where p.suburb_key is null
)
select
  count(*) as missing_found_in_population_staging
from missing m
join public.suburb_population_metrics_staging ps
  on upper(trim(ps.suburb_key)) = m.suburb_key;
