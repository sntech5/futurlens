-- Purpose:
-- Read-only numeric integrity diagnostics for recommendation/report snapshots.
--
-- Use this before applying fixes when app numbers disagree with source tables.
-- It checks whether population_2025 zeros/missing values are in:
-- - public.suburb_population_metrics source data
-- - current public.suburb_base_scores recommendation source rows
-- - public.recommendations.top_suburbs JSON snapshots
-- - public.recommendation_report_suburbs.suburb_snapshot JSON snapshots
--
-- Safe: read-only checks.

-- 1) Source table health. Expected zero_population_source_rows = 0.
select
  count(*) as population_source_rows,
  count(*) filter (where population_2025 is null) as null_population_source_rows,
  count(*) filter (where population_2025 = 0) as zero_population_source_rows,
  count(*) filter (where population_2025 > 0) as positive_population_source_rows,
  min(population_2025) filter (where population_2025 > 0) as min_positive_population_2025,
  max(population_2025) as max_population_2025
from public.suburb_population_metrics;

-- 2) Current recommendation source rows. These are the rows the engine should
-- read from when creating fresh recommendations.
select
  count(*) as base_score_rows,
  count(*) filter (where p.suburb_key is null) as base_rows_without_population_source,
  count(*) filter (where p.population_2025 is null) as base_rows_with_null_population,
  count(*) filter (where p.population_2025 = 0) as base_rows_with_zero_population,
  count(*) filter (where p.population_2025 > 0) as base_rows_with_positive_population
from public.suburb_base_scores s
left join public.suburb_population_metrics p
  on p.suburb_key = s.suburb_key;

-- 3) Source rows with invalid zero population, if any.
select
  suburb_key,
  suburb_name,
  state,
  postcode,
  population_2025,
  updated_at
from public.suburb_population_metrics
where population_2025 = 0
order by state, suburb_name, postcode;

-- 4) Latest recommendation snapshot health. This checks copied JSON values
-- against the live population source.
with latest_recommendation as (
  select r.*
  from public.recommendations r
  order by r.created_at desc
  limit 1
),
snapshot_items as (
  select
    r.id as recommendation_id,
    r.recommendation_run_id,
    r.strategy_type,
    r.created_at as recommendation_created_at,
    item.ordinality as payload_rank,
    item.value ->> 'suburb' as suburb_key,
    item.value ->> 'population_2025' as payload_population_2025
  from latest_recommendation r
  cross join lateral jsonb_array_elements(coalesce(r.top_suburbs, '[]'::jsonb)) with ordinality as item(value, ordinality)
)
select
  recommendation_id,
  recommendation_run_id,
  strategy_type,
  recommendation_created_at,
  count(*) as payload_suburb_count,
  count(*) filter (where payload_population_2025 is null) as payload_missing_population_count,
  count(*) filter (where payload_population_2025 = '0') as payload_zero_population_count,
  count(*) filter (
    where payload_population_2025 is not null
      and p.population_2025 is not null
      and payload_population_2025::numeric <> p.population_2025
  ) as payload_population_mismatch_count,
  count(*) filter (
    where payload_population_2025 is not null
      and p.population_2025 is not null
      and payload_population_2025::numeric = p.population_2025
  ) as payload_population_match_count
from snapshot_items si
left join public.suburb_population_metrics p
  on p.suburb_key = si.suburb_key
group by
  recommendation_id,
  recommendation_run_id,
  strategy_type,
  recommendation_created_at;

-- 5) Latest recommendation rows that are missing/zero/mismatched.
with latest_recommendation as (
  select r.*
  from public.recommendations r
  order by r.created_at desc
  limit 1
),
snapshot_items as (
  select
    r.id as recommendation_id,
    r.recommendation_run_id,
    r.strategy_type,
    r.created_at as recommendation_created_at,
    item.ordinality as payload_rank,
    item.value ->> 'suburb' as suburb_key,
    item.value ->> 'population_2025' as payload_population_2025
  from latest_recommendation r
  cross join lateral jsonb_array_elements(coalesce(r.top_suburbs, '[]'::jsonb)) with ordinality as item(value, ordinality)
)
select
  si.payload_rank,
  si.suburb_key,
  s.suburb_name,
  s.state,
  s.postcode,
  si.payload_population_2025,
  p.population_2025 as live_population_2025,
  p.updated_at as live_population_updated_at,
  case
    when si.payload_population_2025 is null then 'payload_missing_population'
    when si.payload_population_2025 = '0' and coalesce(p.population_2025, 0) > 0 then 'payload_zero_but_live_positive'
    when p.population_2025 is null then 'live_population_missing'
    when si.payload_population_2025::numeric <> p.population_2025 then 'payload_differs_from_live'
    else 'payload_matches_live'
  end as diagnosis
from snapshot_items si
left join public.suburbs s
  on s.suburb_key = si.suburb_key
left join public.suburb_population_metrics p
  on p.suburb_key = si.suburb_key
where si.payload_population_2025 is null
   or si.payload_population_2025 = '0'
   or p.population_2025 is null
   or si.payload_population_2025::numeric <> p.population_2025
order by si.payload_rank
limit 100;

-- 6) Latest report snapshot health. Reports copy another JSON snapshot, so this
-- can disagree even when recommendation/source data has since been fixed.
with latest_report as (
  select rr.*
  from public.recommendation_reports rr
  order by rr.created_at desc
  limit 1
),
report_items as (
  select
    lr.id as report_id,
    lr.report_code,
    lr.created_at as report_created_at,
    rs.report_rank,
    rs.suburb_key,
    rs.suburb_snapshot ->> 'population_2025' as report_snapshot_population_2025
  from latest_report lr
  join public.recommendation_report_suburbs rs
    on rs.report_id = lr.id
)
select
  report_id,
  report_code,
  report_created_at,
  count(*) as report_suburb_count,
  count(*) filter (where report_snapshot_population_2025 is null) as report_missing_population_count,
  count(*) filter (where report_snapshot_population_2025 = '0') as report_zero_population_count,
  count(*) filter (
    where report_snapshot_population_2025 is not null
      and p.population_2025 is not null
      and report_snapshot_population_2025::numeric <> p.population_2025
  ) as report_population_mismatch_count,
  count(*) filter (
    where report_snapshot_population_2025 is not null
      and p.population_2025 is not null
      and report_snapshot_population_2025::numeric = p.population_2025
  ) as report_population_match_count
from report_items ri
left join public.suburb_population_metrics p
  on p.suburb_key = ri.suburb_key
group by
  report_id,
  report_code,
  report_created_at;

-- 7) Current function definition sanity check. Confirm it joins
-- public.suburb_population_metrics and emits pop.population_2025 directly.
select pg_get_functiondef('public.run_recommendation_engine(uuid)'::regprocedure) as current_run_recommendation_engine_definition;
