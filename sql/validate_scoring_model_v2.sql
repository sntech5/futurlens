-- Purpose:
-- Validate scoring_model_v2 after applying:
-- sql/patch_scoring_model_v2_strategy_totals.sql
--
-- Supabase SQL Editor note:
-- Run one numbered query block at a time.
--
-- Safe: read-only checks.

-- QUERY 1: Confirm required scoring columns exist
select
  column_name,
  data_type
from information_schema.columns
where table_schema = 'public'
  and table_name = 'suburb_base_scores'
  and column_name in (
    'base_population_growth_score',
    'population_growth_vs_state_pct',
    'base_growth_strategy_total_score',
    'base_yield_strategy_total_score',
    'score_confidence',
    'score_explanation_payload'
  )
order by column_name;


-- QUERY 2: Confirm scoring functions are deployed
select
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'refresh_population_growth_scores',
    'refresh_base_growth_scores',
    'refresh_suburb_base_scores',
    'run_recommendation_engine'
  )
order by p.proname;


-- QUERY 3: Check scoring coverage and ranges
select
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


-- QUERY 4: Inspect Eglinton NSW 2795 under scoring_model_v2
select
  suburb_key,
  median_price,
  median_rent_weekly,
  gross_yield,
  vacancy_rate,
  renters_pct,
  stock_on_market_pct,
  days_on_market,
  vendor_discount_pct,
  population_growth_pct,
  population_growth_vs_state_pct,
  base_population_growth_score,
  base_growth_score,
  base_yield_score,
  base_demand_score,
  base_risk_score,
  base_growth_strategy_total_score,
  base_yield_strategy_total_score,
  score_confidence,
  score_explanation_payload -> 'growth_components' as growth_components
from public.suburb_base_scores
where suburb_key = 'EGLINTON_NSW_2795';


-- QUERY 5: Top 20 growth strategy ranking for a sample budget/OOP
with params as (
  select
    700000::numeric as budget,
    100::numeric as max_oop
),
eligible as (
  select
    s.*,
    (((s.median_price * 0.8 * 0.06) / 52) - s.median_rent_weekly) as estimated_oop
  from public.suburb_base_scores s
  cross join params p
  where s.median_price <= p.budget
    and (((s.median_price * 0.8 * 0.06) / 52) - s.median_rent_weekly) <= p.max_oop
)
select
  row_number() over (
    order by
      base_growth_strategy_total_score desc nulls last,
      base_growth_score desc nulls last,
      base_demand_score desc nulls last,
      base_risk_score asc nulls last,
      suburb_key asc
  ) as growth_rank,
  suburb_key,
  median_price,
  gross_yield,
  stock_on_market_pct,
  days_on_market,
  vendor_discount_pct,
  estimated_oop,
  base_growth_score,
  base_yield_score,
  base_demand_score,
  base_risk_score,
  base_growth_strategy_total_score,
  base_yield_strategy_total_score
from eligible
order by
  base_growth_strategy_total_score desc nulls last,
  base_growth_score desc nulls last,
  base_demand_score desc nulls last,
  base_risk_score asc nulls last,
  suburb_key asc
limit 20;


-- QUERY 6: Top 20 yield strategy ranking for a sample budget/OOP
with params as (
  select
    700000::numeric as budget,
    100::numeric as max_oop
),
eligible as (
  select
    s.*,
    (((s.median_price * 0.8 * 0.06) / 52) - s.median_rent_weekly) as estimated_oop
  from public.suburb_base_scores s
  cross join params p
  where s.median_price <= p.budget
    and (((s.median_price * 0.8 * 0.06) / 52) - s.median_rent_weekly) <= p.max_oop
)
select
  row_number() over (
    order by
      base_yield_strategy_total_score desc nulls last,
      base_yield_score desc nulls last,
      base_demand_score desc nulls last,
      base_risk_score asc nulls last,
      suburb_key asc
  ) as yield_rank,
  suburb_key,
  median_price,
  gross_yield,
  stock_on_market_pct,
  days_on_market,
  vendor_discount_pct,
  estimated_oop,
  base_growth_score,
  base_yield_score,
  base_demand_score,
  base_risk_score,
  base_growth_strategy_total_score,
  base_yield_strategy_total_score
from eligible
order by
  base_yield_strategy_total_score desc nulls last,
  base_yield_score desc nulls last,
  base_demand_score desc nulls last,
  base_risk_score asc nulls last,
  suburb_key asc
limit 20;

