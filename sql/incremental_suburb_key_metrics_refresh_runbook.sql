-- Purpose:
-- Incrementally add or refresh source-backed suburb key metrics without a full
-- domain reset.
--
-- Source playbook:
-- Docs/suburb_metrics_csv_ingestion_playbook.md
-- Docs/prod_data_reload_playbook.md
--
-- Important:
-- Supabase SQL Editor can be awkward with multiple result sets. Run one
-- numbered query block at a time.
--
-- Manual import pauses:
-- - After QUERY 2, import the market metrics CSV into public.suburb_import_staging.
-- - If population data is available, run QUERY 13 and then import the population CSV
--   into public.suburb_population_metrics_staging.
--
-- Current loader behavior:
-- - quarter_period is derived from current_date as the current quarter-end
--   month, e.g. 2026-06 for May 2026.
-- - market metrics never populate population fields.
-- - base_total_score is retired; use strategy-specific totals only.


-- QUERY 1: Preflight snapshot before adding data
-- Expected: staging tables can contain old rows, but capture counts before
-- truncating anything.
select 'suburbs' as table_name, count(*) as row_count from public.suburbs
union all
select 'suburb_import_staging', count(*) from public.suburb_import_staging
union all
select 'suburb_key_metrics_quarterly', count(*) from public.suburb_key_metrics_quarterly
union all
select 'suburb_population_metrics', count(*) from public.suburb_population_metrics
union all
select 'suburb_population_metrics_staging', count(*) from public.suburb_population_metrics_staging
union all
select 'suburb_base_scores', count(*) from public.suburb_base_scores
union all
select 'suburb_context_refresh_jobs', count(*) from public.suburb_context_refresh_jobs
union all
select 'suburb_ai_context_facts', count(*) from public.suburb_ai_context_facts
order by table_name;


-- QUERY 2: Clear market staging before CSV import
-- After this succeeds, import the market metrics CSV into:
-- public.suburb_import_staging
truncate table public.suburb_import_staging restart identity;


-- QUERY 3: Validate market staging after CSV import
-- Expected:
-- - staging_rows > 0
-- - missing_key_parts = 0
-- - missing_required_metric_values = 0, or investigate source rows before load
select
  count(*) as staging_rows,
  count(*) filter (
    where nullif(trim(coalesce(suburb, '')), '') is null
       or nullif(trim(coalesce(state, '')), '') is null
       or nullif(trim(coalesce(post_code, '')), '') is null
  ) as missing_key_parts,
  count(*) filter (
    where nullif(trim(coalesce(typical_value, '')), '') is null
       or nullif(trim(coalesce(gross_rental_yield, '')), '') is null
       or nullif(trim(coalesce(vacancy_rate, '')), '') is null
       or nullif(trim(coalesce(percent_stock_on_market, '')), '') is null
       or nullif(trim(coalesce(days_on_market, '')), '') is null
       or nullif(trim(coalesce(avg_vendor_discount, '')), '') is null
  ) as missing_required_metric_values
from public.suburb_import_staging;


-- QUERY 4: Upsert staged suburbs into suburb master
-- Expected: inserts/updates suburb master keys only; no metric values loaded.
insert into public.suburbs (
  suburb_key,
  suburb_name,
  state,
  postcode
)
select distinct
  upper(trim(suburb)) || '_' || upper(trim(state)) || '_' || trim(post_code) as suburb_key,
  trim(suburb) as suburb_name,
  upper(trim(state)) as state,
  trim(post_code) as postcode
from public.suburb_import_staging
where nullif(trim(coalesce(suburb, '')), '') is not null
  and nullif(trim(coalesce(state, '')), '') is not null
  and nullif(trim(coalesce(post_code, '')), '') is not null
on conflict (suburb_key) do update set
  suburb_name = excluded.suburb_name,
  state = excluded.state,
  postcode = excluded.postcode;


-- QUERY 5: Confirm all staged suburb keys now exist in suburb master
-- Expected: staged_keys_without_suburb_master = 0
with staged as (
  select distinct
    upper(trim(suburb)) || '_' || upper(trim(state)) || '_' || trim(post_code) as suburb_key
  from public.suburb_import_staging
  where nullif(trim(coalesce(suburb, '')), '') is not null
    and nullif(trim(coalesce(state, '')), '') is not null
    and nullif(trim(coalesce(post_code, '')), '') is not null
)
select count(*) as staged_keys_without_suburb_master
from staged st
left join public.suburbs s on s.suburb_key = st.suburb_key
where s.suburb_key is null;


-- QUERY 6: Ensure quarterly metric columns exist
alter table public.suburb_key_metrics_quarterly
  add column if not exists quarter_period text,
  add column if not exists median_price numeric,
  add column if not exists median_rent_weekly numeric,
  add column if not exists gross_yield numeric;


-- QUERY 7: Ensure quarterly business-key uniqueness exists
create unique index if not exists suburb_key_metrics_quarterly_suburb_key_period_uidx
on public.suburb_key_metrics_quarterly (suburb_key, quarter_period);


-- QUERY 8: Load quarterly market metrics from staging
-- This is the same logic as sql/load_suburb_key_metrics_quarterly_from_staging.sql.
-- It only loads rows with source-backed required metrics and matching suburb keys.
with cleaned as (
  select
    upper(trim(suburb)) || '_' || upper(trim(state)) || '_' || trim(post_code) as suburb_key,
    to_char(date_trunc('quarter', current_date) + interval '2 month', 'YYYY-MM') as quarter_period,
    (date_trunc('quarter', current_date) + interval '3 month - 1 day')::date as quarter_date,
    nullif(regexp_replace(coalesce(typical_value, ''), '[^0-9.]', '', 'g'), '')::numeric as median_price,
    case
      when nullif(regexp_replace(coalesce(gross_rental_yield, ''), '[^0-9.]', '', 'g'), '')::numeric > 1
        then nullif(regexp_replace(coalesce(gross_rental_yield, ''), '[^0-9.]', '', 'g'), '')::numeric / 100
      else nullif(regexp_replace(coalesce(gross_rental_yield, ''), '[^0-9.]', '', 'g'), '')::numeric
    end as gross_yield,
    nullif(regexp_replace(coalesce(vacancy_rate, ''), '[^0-9.]', '', 'g'), '')::numeric as vacancy_rate,
    nullif(regexp_replace(coalesce(percent_renters_in_market, ''), '[^0-9.]', '', 'g'), '')::numeric as renters_pct,
    nullif(regexp_replace(coalesce(percent_stock_on_market, ''), '[^0-9.]', '', 'g'), '')::numeric as stock_on_market_pct,
    nullif(regexp_replace(coalesce(days_on_market, ''), '[^0-9.]', '', 'g'), '')::numeric as days_on_market,
    nullif(regexp_replace(coalesce(avg_vendor_discount, ''), '[^0-9.-]', '', 'g'), '')::numeric as vendor_discount_pct,
    null::numeric as population_growth_pct,
    null::numeric as infrastructure_score
  from public.suburb_import_staging
),
ready as (
  select
    c.suburb_key,
    c.quarter_period,
    c.quarter_date,
    c.median_price,
    round((c.median_price * c.gross_yield / 52)::numeric, 2) as median_rent_weekly,
    c.gross_yield,
    c.vacancy_rate,
    c.renters_pct,
    c.stock_on_market_pct,
    c.days_on_market,
    c.vendor_discount_pct,
    c.population_growth_pct,
    c.infrastructure_score
  from cleaned c
  join public.suburbs s on s.suburb_key = c.suburb_key
  where c.median_price is not null
    and c.median_price > 0
    and c.gross_yield is not null
    and c.gross_yield > 0
    and c.vacancy_rate is not null
    and c.stock_on_market_pct is not null
    and c.days_on_market is not null
    and c.days_on_market > 0
    and c.vendor_discount_pct is not null
)
insert into public.suburb_key_metrics_quarterly (
  suburb_key,
  quarter_period,
  quarter_date,
  median_price,
  median_rent_weekly,
  gross_yield,
  vacancy_rate,
  renters_pct,
  stock_on_market_pct,
  days_on_market,
  vendor_discount_pct,
  population_growth_pct,
  infrastructure_score
)
select
  suburb_key,
  quarter_period,
  quarter_date,
  median_price,
  median_rent_weekly,
  gross_yield,
  vacancy_rate,
  renters_pct,
  stock_on_market_pct,
  days_on_market,
  vendor_discount_pct,
  population_growth_pct,
  infrastructure_score
from ready
on conflict (suburb_key, quarter_period)
do update set
  quarter_period = excluded.quarter_period,
  quarter_date = excluded.quarter_date,
  median_price = excluded.median_price,
  median_rent_weekly = excluded.median_rent_weekly,
  gross_yield = excluded.gross_yield,
  vacancy_rate = excluded.vacancy_rate,
  renters_pct = excluded.renters_pct,
  stock_on_market_pct = excluded.stock_on_market_pct,
  days_on_market = excluded.days_on_market,
  vendor_discount_pct = excluded.vendor_discount_pct,
  population_growth_pct = excluded.population_growth_pct,
  infrastructure_score = excluded.infrastructure_score;


-- QUERY 9: Validate loaded rows for this quarter
-- Expected:
-- - staged_valid_rows_loaded_to_quarter should match eligible staged source rows
-- - quarterly_rows_missing_required_metrics = 0
with target as (
  select to_char(date_trunc('quarter', current_date) + interval '2 month', 'YYYY-MM') as quarter_period
),
staged_valid as (
  select distinct
    upper(trim(suburb)) || '_' || upper(trim(state)) || '_' || trim(post_code) as suburb_key
  from public.suburb_import_staging
  where nullif(trim(coalesce(suburb, '')), '') is not null
    and nullif(trim(coalesce(state, '')), '') is not null
    and nullif(trim(coalesce(post_code, '')), '') is not null
    and nullif(trim(coalesce(typical_value, '')), '') is not null
    and nullif(trim(coalesce(gross_rental_yield, '')), '') is not null
    and nullif(trim(coalesce(vacancy_rate, '')), '') is not null
    and nullif(trim(coalesce(percent_stock_on_market, '')), '') is not null
    and nullif(trim(coalesce(days_on_market, '')), '') is not null
    and nullif(trim(coalesce(avg_vendor_discount, '')), '') is not null
),
loaded as (
  select q.*
  from public.suburb_key_metrics_quarterly q
  join target t on t.quarter_period = q.quarter_period
)
select
  (select count(*) from staged_valid) as staged_valid_source_rows,
  (select count(*) from loaded l join staged_valid sv on sv.suburb_key = l.suburb_key) as staged_valid_rows_loaded_to_quarter,
  (select count(*) from loaded where median_price is null
    or median_rent_weekly is null
    or gross_yield is null
    or vacancy_rate is null
    or stock_on_market_pct is null
    or days_on_market is null
    or vendor_discount_pct is null
  ) as quarterly_rows_missing_required_metrics;


-- QUERY 10: Refresh base scores after market load
-- Expected: returns one row with refresh_suburb_base_scores null/void.
select public.refresh_suburb_base_scores();


-- QUERY 11: Audit population coverage after market load
-- Expected:
-- - quarterly_without_population ideally 0.
-- - if non-zero, export QUERY 12 result and backfill only with verified source data.
select
  count(*) as quarterly_without_population
from public.suburb_key_metrics_quarterly q
left join public.suburb_population_metrics p
  on p.suburb_key = q.suburb_key
where p.suburb_key is null;


-- QUERY 12: Missing population suburb list
-- Use this result to prepare a source-backed population CSV if QUERY 11 is non-zero.
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


-- QUERY 13: Check whether existing population staging covers missing suburbs
-- Run this before clearing population staging. If rows are already staged,
-- validate/load them instead of importing another file.
with missing as (
  select q.suburb_key
  from public.suburb_key_metrics_quarterly q
  left join public.suburb_population_metrics p
    on p.suburb_key = q.suburb_key
  where p.suburb_key is null
),
staged_population as (
  select distinct upper(trim(suburb_key)) as suburb_key
  from public.suburb_population_metrics_staging
  where nullif(trim(coalesce(suburb_key, '')), '') is not null
)
select
  count(*) as missing_population_suburbs,
  count(sp.suburb_key) as missing_found_in_population_staging,
  count(*) - count(sp.suburb_key) as missing_not_in_population_staging
from missing m
left join staged_population sp
  on sp.suburb_key = m.suburb_key;


-- QUERY 14: Split missing population between current import and older quarterly rows
-- This tells you whether the new market CSV introduced the population gap.
with missing as (
  select q.suburb_key
  from public.suburb_key_metrics_quarterly q
  left join public.suburb_population_metrics p
    on p.suburb_key = q.suburb_key
  where p.suburb_key is null
),
staged_market as (
  select distinct
    upper(trim(suburb)) || '_' || upper(trim(state)) || '_' || trim(post_code) as suburb_key
  from public.suburb_import_staging
  where nullif(trim(coalesce(suburb, '')), '') is not null
    and nullif(trim(coalesce(state, '')), '') is not null
    and nullif(trim(coalesce(post_code, '')), '') is not null
)
select
  count(*) as missing_population_suburbs,
  count(sm.suburb_key) as missing_from_current_market_import,
  count(*) - count(sm.suburb_key) as missing_from_existing_quarterly_rows
from missing m
left join staged_market sm
  on sm.suburb_key = m.suburb_key;


-- QUERY 15: Missing population count by state
-- Use this to size the backfill work and document accepted source gaps.
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


-- QUERY 16: Optional - clear population staging before population CSV import
-- Run only when you have a verified population backfill CSV.
-- After this succeeds, import the population CSV into:
-- public.suburb_population_metrics_staging
truncate table public.suburb_population_metrics_staging restart identity;


-- QUERY 17: Optional - validate population staging after CSV import
-- Expected:
-- - staging_rows > 0
-- - staging_rows_without_suburb_master = 0
-- - rows_missing_population_2025 = 0 unless deliberately loading growth-only metadata
select
  count(*) as staging_rows,
  count(*) filter (where nullif(trim(coalesce(ps.suburb_key, '')), '') is null) as rows_missing_suburb_key,
  count(*) filter (where nullif(regexp_replace(coalesce(ps.population_2025, ''), '[^0-9.-]', '', 'g'), '') is null) as rows_missing_population_2025,
  count(*) filter (where s.suburb_key is null) as staging_rows_without_suburb_master
from public.suburb_population_metrics_staging ps
left join public.suburbs s
  on s.suburb_key = upper(trim(ps.suburb_key));


-- QUERY 18: Optional - load population metrics from staging
-- This is the same logic as sql/load_suburb_population_metrics_from_staging.sql.
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


-- QUERY 19: Optional but required after population load - refresh scores again
-- This picks up population momentum in growth and strategy totals.
select public.refresh_suburb_base_scores();


-- QUERY 20: Re-audit population coverage
-- Expected: lower than QUERY 11, ideally 0. Remaining rows are documented source gaps.
select
  count(*) as quarterly_without_population
from public.suburb_key_metrics_quarterly q
left join public.suburb_population_metrics p
  on p.suburb_key = q.suburb_key
where p.suburb_key is null;


-- QUERY 21: Enqueue AI context refresh jobs for the current month
-- Expected: total_for_month should cover all distinct metric suburbs.
select *
from public.enqueue_suburb_context_refresh_jobs();


-- QUERY 22: Validate AI context queue coverage
-- Expected: metric_suburbs = queued_context_suburbs for the current month.
select
  count(distinct q.suburb_key) as metric_suburbs,
  count(distinct j.suburb_key) as queued_context_suburbs
from public.suburb_key_metrics_quarterly q
left join public.suburb_context_refresh_jobs j
  on j.suburb_key = q.suburb_key
  and j.refresh_month = date_trunc('month', current_date)::date;


-- QUERY 23: AI context job status snapshot
-- Pending/failed jobs are a soft gate, but record the status after enqueue.
-- This filters to the default job identity used by QUERY 21 so counts line up
-- with total_for_month.
select
  status,
  count(*) as job_count
from public.suburb_context_refresh_jobs
where refresh_month = date_trunc('month', current_date)::date
  and prompt_version = 'suburb_context_facts_v1'
  and ai_provider = 'gemini'
  and model = 'gemini-2.5-flash-lite'
group by status
order by status;


-- QUERY 24: Hard post-load integrity gates
-- Expected all hard gate counts = 0.
select 'quarterly_without_suburb' as gate, count(*) as issue_count
from public.suburb_key_metrics_quarterly q
left join public.suburbs s on s.suburb_key = q.suburb_key
where s.suburb_key is null
union all
select 'population_metrics_without_suburb', count(*)
from public.suburb_population_metrics p
left join public.suburbs s on s.suburb_key = p.suburb_key
where s.suburb_key is null
union all
select 'base_scores_without_suburb', count(*)
from public.suburb_base_scores b
left join public.suburbs s on s.suburb_key = b.suburb_key
where s.suburb_key is null
union all
select 'base_scores_without_quarterly_source', count(*)
from public.suburb_base_scores b
where not exists (
  select 1
  from public.suburb_key_metrics_quarterly q
  where q.suburb_key = b.suburb_key
)
union all
select 'quarterly_suburbs_without_base_score', count(*)
from (
  select distinct suburb_key
  from public.suburb_key_metrics_quarterly
  where suburb_key is not null
) q
left join public.suburb_base_scores b
  on b.suburb_key = q.suburb_key
where b.suburb_key is null
union all
select 'quarterly_rows_missing_required_metrics', count(*)
from public.suburb_key_metrics_quarterly
where median_price is null
  or median_rent_weekly is null
  or gross_yield is null
  or vacancy_rate is null
  or stock_on_market_pct is null
  or days_on_market is null
  or vendor_discount_pct is null
union all
select 'quarterly_rows_missing_scoring_metrics', count(*)
from public.suburb_key_metrics_quarterly
where renters_pct is null
union all
select 'empty_base_score_rows', count(*)
from public.suburb_base_scores
where median_price is null
  and median_rent_weekly is null
  and gross_yield is null
  and vacancy_rate is null
  and stock_on_market_pct is null
  and days_on_market is null
union all
select 'missing_growth_strategy_total', count(*)
from public.suburb_base_scores
where base_growth_strategy_total_score is null
union all
select 'missing_yield_strategy_total', count(*)
from public.suburb_base_scores
where base_yield_strategy_total_score is null
order by gate;


-- QUERY 25: Scoring model v2 range and column validation
-- Expected:
-- - base_total_score_present = false
-- - scored_suburbs > 0
-- - missing score counts = 0
-- - min/max values remain within 0..10
select
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'suburb_base_scores'
      and column_name = 'base_total_score'
  ) as base_total_score_present,
  count(*) as scored_suburbs,
  count(*) filter (where base_growth_score is null) as missing_growth_score,
  count(*) filter (where base_yield_score is null) as missing_yield_score,
  count(*) filter (where base_demand_score is null) as missing_demand_score,
  count(*) filter (where base_risk_score is null) as missing_risk_score,
  count(*) filter (where base_growth_strategy_total_score is null) as missing_growth_strategy_total,
  count(*) filter (where base_yield_strategy_total_score is null) as missing_yield_strategy_total,
  min(base_growth_score) as min_growth_score,
  max(base_growth_score) as max_growth_score,
  min(base_yield_score) as min_yield_score,
  max(base_yield_score) as max_yield_score,
  min(base_demand_score) as min_demand_score,
  max(base_demand_score) as max_demand_score,
  min(base_risk_score) as min_risk_score,
  max(base_risk_score) as max_risk_score,
  min(base_growth_strategy_total_score) as min_growth_strategy_total,
  max(base_growth_strategy_total_score) as max_growth_strategy_total,
  min(base_yield_strategy_total_score) as min_yield_strategy_total,
  max(base_yield_strategy_total_score) as max_yield_strategy_total
from public.suburb_base_scores;


-- QUERY 26: Recommendation function readiness
-- Expected: all functions listed once; run_recommendation_engine has p_run_id uuid.
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
    'refresh_population_growth_scores',
    'enqueue_suburb_context_refresh_jobs'
  )
order by p.proname;
