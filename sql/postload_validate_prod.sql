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

-- 2) FK/data integrity checks.
select count(*) as base_scores_without_suburb
from public.suburb_base_scores s
left join public.suburbs m on m.suburb_key = s.suburb_key
where m.suburb_key is null;

select count(*) as quarterly_without_suburb
from public.suburb_key_metrics_quarterly s
left join public.suburbs m on m.suburb_key = s.suburb_key
where m.suburb_key is null;

select count(*) as population_metrics_without_suburb
from public.suburb_population_metrics s
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

select count(*) as population_score_rows_missing_score
from public.suburb_base_scores
where base_population_growth_score is null;

select count(*) as quarterly_rows_missing_required_metrics
from public.suburb_key_metrics_quarterly
where median_price is null
  or median_rent_weekly is null
  or gross_yield is null
  or vacancy_rate is null
  or stock_on_market_pct is null
  or days_on_market is null
  or vendor_discount_pct is null;

-- 4) No-made-up-data guardrails.
select count(*) as empty_base_score_rows
from public.suburb_base_scores
where median_price is null
  and median_rent_weekly is null
  and gross_yield is null
  and vacancy_rate is null
  and stock_on_market_pct is null
  and days_on_market is null;

select count(*) as base_scores_without_quarterly_source
from public.suburb_base_scores s
where not exists (
  select 1
  from public.suburb_key_metrics_quarterly q
  where q.suburb_key = s.suburb_key
);

-- 5) Function readiness smoke query.
select
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'run_recommendation_engine',
    'refresh_suburb_base_scores',
    'refresh_base_growth_scores',
    'refresh_population_growth_scores'
  )
order by p.proname;
