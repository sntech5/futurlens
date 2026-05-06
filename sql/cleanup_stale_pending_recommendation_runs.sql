-- Purpose:
-- Clean stale recommendation test rows created before run_recommendation_engine
-- was patched to run as SECURITY DEFINER.
--
-- Problem signature:
-- - recommendation_runs.run_status = 'pending'
-- - recommendation_runs.completed_at is null
-- - a recommendation row already exists for the run
--
-- That state should not happen after the patch. Fresh runs should complete and
-- include source-backed population_2025 in recommendations.top_suburbs.
--
-- Supabase SQL Editor note:
-- Run ONE numbered query block at a time.


-- QUERY 1: Dry-run summary
-- Shows how many stale pending runs/recommendations are eligible for deletion.
-- Rows linked to recommendation_reports are excluded.
with stale_runs as (
  select rr.id
  from public.recommendation_runs rr
  where rr.run_status = 'pending'
    and rr.completed_at is null
    and exists (
      select 1
      from public.recommendations r
      where r.recommendation_run_id = rr.id
    )
    and not exists (
      select 1
      from public.recommendation_reports rpt
      where rpt.recommendation_run_id = rr.id
    )
),
stale_recommendations as (
  select r.id
  from public.recommendations r
  join stale_runs sr on sr.id = r.recommendation_run_id
)
select
  count(distinct sr.id) as stale_pending_runs_to_delete,
  count(distinct rec.id) as stale_recommendations_to_delete
from stale_runs sr
left join stale_recommendations rec on true;


-- QUERY 2: Dry-run row sample
-- Review this before deleting.
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
join public.recommendation_runs rr
  on rr.id = r.recommendation_run_id
where rr.run_status = 'pending'
  and rr.completed_at is null
  and not exists (
    select 1
    from public.recommendation_reports rpt
    where rpt.recommendation_run_id = rr.id
  )
order by r.created_at desc
limit 100;


-- QUERY 3: Delete stale pending runs and their recommendations
-- This is one atomic statement. It deletes recommendations first, then the
-- now-unreferenced pending runs. Report-linked runs are excluded.
with stale_runs as (
  select rr.id
  from public.recommendation_runs rr
  where rr.run_status = 'pending'
    and rr.completed_at is null
    and exists (
      select 1
      from public.recommendations r
      where r.recommendation_run_id = rr.id
    )
    and not exists (
      select 1
      from public.recommendation_reports rpt
      where rpt.recommendation_run_id = rr.id
    )
),
deleted_recommendations as (
  delete from public.recommendations r
  using stale_runs sr
  where r.recommendation_run_id = sr.id
  returning r.id
),
deleted_runs as (
  delete from public.recommendation_runs rr
  using stale_runs sr
  where rr.id = sr.id
  returning rr.id
)
select
  (select count(*) from deleted_recommendations) as deleted_recommendations,
  (select count(*) from deleted_runs) as deleted_pending_runs;


-- QUERY 4: Post-cleanup validation
-- Expected: stale_pending_runs_remaining = 0.
select
  count(distinct rr.id) as stale_pending_runs_remaining,
  count(distinct r.id) as stale_recommendations_remaining
from public.recommendation_runs rr
join public.recommendations r
  on r.recommendation_run_id = rr.id
where rr.run_status = 'pending'
  and rr.completed_at is null
  and not exists (
    select 1
    from public.recommendation_reports rpt
    where rpt.recommendation_run_id = rr.id
  );
