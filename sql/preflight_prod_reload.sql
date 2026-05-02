-- Reference: Docs/sql_reference_prod_reload_preflight.md
-- Purpose: preflight checks before resetting/loading production domain data.
-- Safe: read-only checks.

-- 1) Snapshot row counts for key tables.
select 'user_profiles' as table_name, count(*) as row_count from public.user_profiles
union all
select 'suburbs', count(*) from public.suburbs
union all
select 'suburb_import_staging', count(*) from public.suburb_import_staging
union all
select 'suburb_base_scores', count(*) from public.suburb_base_scores
union all
select 'suburb_key_metrics_quarterly', count(*) from public.suburb_key_metrics_quarterly
union all
select 'suburb_population_metrics', count(*) from public.suburb_population_metrics
union all
select 'suburb_population_metrics_staging', count(*) from public.suburb_population_metrics_staging
union all
select 'recommendation_runs', count(*) from public.recommendation_runs
union all
select 'recommendations', count(*) from public.recommendations
order by table_name;

-- 2) Relationship sanity before reset (should be 0; if not, investigate).
select count(*) as base_scores_without_suburb
from public.suburb_base_scores s
left join public.suburbs m on m.suburb_key = s.suburb_key
where m.suburb_key is null;

select count(*) as recommendations_without_run
from public.recommendations r
left join public.recommendation_runs rr on rr.id = r.recommendation_run_id
where rr.id is null;

-- 3) Confirm patched recommendation function exists.
select
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'run_recommendation_engine';
