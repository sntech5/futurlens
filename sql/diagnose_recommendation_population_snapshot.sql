-- Purpose:
-- Diagnose why a recommendation/report payload shows a different
-- population_2025 from the live source table.
--
-- Safe: read-only checks.
--
-- Supabase SQL Editor note:
-- Run ONE numbered query block at a time. Copy from the numbered comment down
-- to that block's semicolon, then share the result.
--
-- Change 'MILLBANK_QLD_4670' in each query if investigating another suburb.


-- QUERY 1: Live population source value
-- Confirms what the authoritative population table has for the suburb.
select
  'query_1_live_source' as check_name,
  s.suburb_key,
  s.suburb_name,
  s.state,
  s.postcode,
  p.population_2025 as live_population_2025,
  p.updated_at as population_updated_at
from public.suburbs s
left join public.suburb_population_metrics p
  on p.suburb_key = s.suburb_key
where s.suburb_key = 'MILLBANK_QLD_4670';


-- QUERY 2: Current recommendation-engine source projection
-- Confirms what run_recommendation_engine should read before it writes JSON.
select
  'query_2_engine_projection' as check_name,
  s.suburb_key,
  s.median_price,
  s.median_rent_weekly,
  s.gross_yield,
  pop.population_2025 as engine_join_population_2025,
  s.population_growth_pct,
  s.population_growth_vs_state_pct,
  s.base_growth_score,
  s.base_yield_score,
  s.base_total_score,
  s.refreshed_at
from public.suburb_base_scores s
left join public.suburb_population_metrics pop
  on pop.suburb_key = s.suburb_key
where s.suburb_key = 'MILLBANK_QLD_4670';


-- QUERY 3: Recommendation JSON snapshots for this suburb
-- Checks copied values in recommendations.top_suburbs.
-- If payload_population_2025 is 0 while live_population_2025 is positive,
-- the recommendation JSON snapshot is stale or was created by old logic.
with target as (
  select 'MILLBANK_QLD_4670'::text as suburb_key
),
live_source as (
  select
    t.suburb_key,
    p.population_2025 as live_population_2025,
    p.updated_at as population_updated_at
  from target t
  left join public.suburb_population_metrics p on p.suburb_key = t.suburb_key
),
snapshot_rows as (
  select
    r.id as recommendation_id,
    r.recommendation_run_id,
    r.strategy_type,
    r.created_at as recommendation_created_at,
    rr.completed_at as recommendation_run_completed_at,
    item.ordinality as payload_rank,
    item.value ->> 'suburb' as suburb_key,
    item.value ->> 'population_2025' as payload_population_2025
  from public.recommendations r
  left join public.recommendation_runs rr on rr.id = r.recommendation_run_id
  cross join lateral jsonb_array_elements(coalesce(r.top_suburbs, '[]'::jsonb)) with ordinality as item(value, ordinality)
  join target t on item.value ->> 'suburb' = t.suburb_key
)
select
  'query_3_recommendation_snapshot' as check_name,
  sr.recommendation_id,
  sr.recommendation_run_id,
  sr.strategy_type,
  sr.recommendation_created_at,
  sr.recommendation_run_completed_at,
  sr.payload_rank,
  sr.suburb_key,
  sr.payload_population_2025,
  ls.live_population_2025,
  ls.population_updated_at,
  case
    when sr.recommendation_created_at < ls.population_updated_at then 'snapshot_created_before_population_update'
    when sr.payload_population_2025 is null then 'payload_missing_population'
    when sr.payload_population_2025::numeric = ls.live_population_2025 then 'payload_matches_live_source'
    else 'payload_differs_from_live_source'
  end as diagnosis
from snapshot_rows sr
left join live_source ls on ls.suburb_key = sr.suburb_key
order by sr.recommendation_created_at desc
limit 20;


-- QUERY 4: Report suburb JSON snapshots for this suburb
-- Checks copied values in recommendation_report_suburbs.suburb_snapshot.
-- This can remain stale even after recommendation/source data is corrected.
with target as (
  select 'MILLBANK_QLD_4670'::text as suburb_key
),
report_snapshot_rows as (
  select
    rs.report_id,
    rs.suburb_key,
    rs.created_at as report_snapshot_created_at,
    rs.suburb_snapshot ->> 'population_2025' as report_snapshot_population_2025
  from public.recommendation_report_suburbs rs
  join target t on t.suburb_key = rs.suburb_key
)
select
  'query_4_report_snapshot' as check_name,
  rs.report_id,
  rs.suburb_key,
  rs.report_snapshot_created_at,
  rs.report_snapshot_population_2025,
  p.population_2025 as live_population_2025,
  p.updated_at as population_updated_at,
  case
    when rs.report_snapshot_created_at < p.updated_at then 'report_snapshot_created_before_population_update'
    when rs.report_snapshot_population_2025 is null then 'report_snapshot_missing_population'
    when rs.report_snapshot_population_2025::numeric = p.population_2025 then 'report_snapshot_matches_live_source'
    else 'report_snapshot_differs_from_live_source'
  end as diagnosis
from report_snapshot_rows rs
left join public.suburb_population_metrics p on p.suburb_key = rs.suburb_key
order by rs.report_snapshot_created_at desc
limit 20;


-- QUERY 5: Current deployed run_recommendation_engine definition
-- Confirms whether Supabase is actually using the patched function.
-- Look for:
-- - left join public.suburb_population_metrics pop
-- - 'population_2025', pop.population_2025
-- - order by strategy score first, then base_total_score
select
  pg_get_functiondef('public.run_recommendation_engine(uuid)'::regprocedure)
    as current_run_recommendation_engine_definition;


-- QUERY 6: Recommendation run rows behind Millbank snapshots
-- completed_at is null in Query 3, which is suspicious because the patched
-- run_recommendation_engine updates recommendation_runs.completed_at.
-- This checks whether those recommendation rows came from completed runs.
select
  r.id as recommendation_id,
  r.recommendation_run_id,
  r.strategy_type as recommendation_strategy_type,
  r.created_at as recommendation_created_at,
  rr.run_status,
  rr.strategy_type as run_strategy_type,
  rr.input_budget,
  rr.max_out_of_pocket,
  rr.created_at as run_created_at,
  rr.completed_at as run_completed_at
from public.recommendations r
left join public.recommendation_runs rr
  on rr.id = r.recommendation_run_id
where exists (
  select 1
  from jsonb_array_elements(coalesce(r.top_suburbs, '[]'::jsonb)) item(value)
  where item.value ->> 'suburb' = 'MILLBANK_QLD_4670'
)
order by r.created_at desc
limit 20;


-- QUERY 7: RLS and policy check for recommendation tables
-- If run_recommendation_engine is not SECURITY DEFINER, RLS/update policies can
-- allow inserting recommendations while silently preventing the final
-- recommendation_runs status update.
select
  c.relname as table_name,
  c.relrowsecurity as rls_enabled,
  c.relforcerowsecurity as force_rls
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('recommendation_runs', 'recommendations')
order by c.relname;


-- QUERY 8: Policies on recommendation tables
-- Look specifically for UPDATE policies on public.recommendation_runs.
select
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('recommendation_runs', 'recommendations')
order by tablename, policyname;
