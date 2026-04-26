-- Reference: Docs/sql_reference_prod_reload_postload_validate.md
-- Purpose: verify post-load integrity, constraints, and recommendation readiness.
-- Safe: read-only checks.

-- 1) Row count snapshot after load.
select 'suburbs' as table_name, count(*) as row_count from public.suburbs
union all
select 'suburb_import_staging', count(*) from public.suburb_import_staging
union all
select 'suburb_base_scores', count(*) from public.suburb_base_scores
union all
select 'suburb_monthly_data', count(*) from public.suburb_monthly_data
union all
select 'suburb_quarterly_data', count(*) from public.suburb_quarterly_data
union all
select 'recommendation_runs', count(*) from public.recommendation_runs
union all
select 'recommendations', count(*) from public.recommendations
order by table_name;

-- 2) FK/data integrity checks.
select count(*) as base_scores_without_suburb
from public.suburb_base_scores s
left join public.suburbs m on m.suburb_key = s.suburb_key
where m.suburb_key is null;

select count(*) as monthly_without_suburb
from public.suburb_monthly_data s
left join public.suburbs m on m.suburb_key = s.suburb_key
where m.suburb_key is null;

select count(*) as quarterly_without_suburb
from public.suburb_quarterly_data s
left join public.suburbs m on m.suburb_key = s.suburb_key
where m.suburb_key is null;

-- 3) Critical null checks in base scores.
select count(*) as null_suburb_key_rows
from public.suburb_base_scores
where suburb_key is null;

select count(*) as null_price_rows
from public.suburb_base_scores
where median_price is null;

select count(*) as null_rent_rows
from public.suburb_base_scores
where median_rent_weekly is null;

-- 4) Function readiness smoke query.
select
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('run_recommendation_engine', 'refresh_base_growth_scores')
order by p.proname;

