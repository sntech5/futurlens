-- Purpose:
-- Diagnose why MILLBANK_QLD_4670 appears at/near the top across strategies.
--
-- Safe: read-only checks.
--
-- Supabase SQL Editor note:
-- Run ONE numbered query block at a time.
--
-- Change the values in the params CTE if testing different app inputs.


-- QUERY 1: Latest completed growth/yield test inputs
-- Confirms the exact criteria that produced the latest recommendation rows.
select
  rr.id as run_id,
  rr.strategy_type,
  rr.input_budget,
  rr.max_out_of_pocket,
  rr.run_status,
  rr.created_at,
  rr.completed_at
from public.recommendation_runs rr
where rr.run_status = 'completed'
  and rr.strategy_type in ('growth', 'yield')
order by rr.created_at desc
limit 10;


-- QUERY 2: Eligible universe for the current test criteria
-- Adjust budget/oop here to match your app inputs.
-- If eligible_count is small, the filter criteria may be forcing the same top suburb.
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
  count(*) as eligible_count,
  min(median_price) as min_price,
  max(median_price) as max_price,
  min(estimated_oop) as min_estimated_oop,
  max(estimated_oop) as max_estimated_oop,
  min(base_growth_score) as min_growth_score,
  max(base_growth_score) as max_growth_score,
  min(base_yield_score) as min_yield_score,
  max(base_yield_score) as max_yield_score,
  count(*) filter (where base_yield_score = 10) as yield_score_capped_at_10_count
from eligible;


-- QUERY 3: Millbank rank under each strategy for the current criteria
-- This tells us whether Millbank is #1 because it truly has the highest
-- strategy score among eligible suburbs.
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
),
ranked as (
  select
    row_number() over (
      order by
        base_growth_score desc nulls last,
        base_total_score desc nulls last,
        base_demand_score desc nulls last,
        base_risk_score asc nulls last,
        suburb_key asc
    ) as growth_rank,
    row_number() over (
      order by
        gross_yield desc nulls last,
        estimated_oop asc nulls last,
        base_total_score desc nulls last,
        base_demand_score desc nulls last,
        base_risk_score asc nulls last,
        suburb_key asc
    ) as yield_rank,
    suburb_key,
    median_price,
    median_rent_weekly,
    gross_yield,
    estimated_oop,
    population_growth_pct,
    population_growth_vs_state_pct,
    base_growth_score,
    base_population_growth_score,
    base_yield_score,
    base_demand_score,
    base_risk_score,
    base_total_score
  from eligible
)
select
  'growth'::text as strategy_type,
  growth_rank as strategy_rank,
  suburb_key,
  median_price,
  median_rent_weekly,
  gross_yield,
  estimated_oop,
  population_growth_pct,
  population_growth_vs_state_pct,
  base_growth_score,
  base_population_growth_score,
  base_yield_score,
  base_demand_score,
  base_risk_score,
  base_total_score
from ranked
where suburb_key = 'MILLBANK_QLD_4670'

union all

select
  'yield'::text as strategy_type,
  yield_rank as strategy_rank,
  suburb_key,
  median_price,
  median_rent_weekly,
  gross_yield,
  estimated_oop,
  population_growth_pct,
  population_growth_vs_state_pct,
  base_growth_score,
  base_population_growth_score,
  base_yield_score,
  base_demand_score,
  base_risk_score,
  base_total_score
from ranked
where suburb_key = 'MILLBANK_QLD_4670'
order by strategy_type;


-- QUERY 4: Top 20 growth ranking for current criteria
-- Compare Millbank's growth score against other eligible suburbs.
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
      base_growth_score desc nulls last,
      base_total_score desc nulls last,
      base_demand_score desc nulls last,
      base_risk_score asc nulls last,
      suburb_key asc
  ) as growth_rank,
  suburb_key,
  median_price,
  median_rent_weekly,
  gross_yield,
  estimated_oop,
  population_growth_vs_state_pct,
  base_growth_score,
  base_population_growth_score,
  base_yield_score,
  base_demand_score,
  base_risk_score,
  base_total_score
from eligible
order by
  base_growth_score desc nulls last,
  base_total_score desc nulls last,
  base_demand_score desc nulls last,
  base_risk_score asc nulls last,
  suburb_key asc
limit 20;


-- QUERY 5: Top 20 yield ranking for current criteria
-- If many suburbs have base_yield_score = 10, the current yield score is too
-- coarse and base_total_score becomes the practical tiebreaker.
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
      base_yield_score desc nulls last,
      base_total_score desc nulls last,
      base_demand_score desc nulls last,
      base_risk_score asc nulls last,
      suburb_key asc
  ) as yield_rank,
  suburb_key,
  median_price,
  median_rent_weekly,
  gross_yield,
  estimated_oop,
  population_growth_vs_state_pct,
  base_growth_score,
  base_population_growth_score,
  base_yield_score,
  base_demand_score,
  base_risk_score,
  base_total_score
from eligible
order by
  base_yield_score desc nulls last,
  base_total_score desc nulls last,
  base_demand_score desc nulls last,
  base_risk_score asc nulls last,
  suburb_key asc
limit 20;


-- QUERY 6: Top 20 by raw gross yield only
-- This checks whether base_yield_score is masking meaningful gross_yield
-- differences because it caps at 10.
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
    order by gross_yield desc nulls last, estimated_oop asc nulls last, suburb_key asc
  ) as raw_yield_rank,
  suburb_key,
  median_price,
  median_rent_weekly,
  gross_yield,
  estimated_oop,
  base_yield_score,
  base_total_score
from eligible
order by gross_yield desc nulls last, estimated_oop asc nulls last, suburb_key asc
limit 20;


-- QUERY 7: Expected top 20 after yield-ranking patch
-- This mirrors the patched run_recommendation_engine yield ordering:
-- gross_yield desc, estimated_oop asc, base_total_score desc.
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
      gross_yield desc nulls last,
      estimated_oop asc nulls last,
      base_total_score desc nulls last,
      base_demand_score desc nulls last,
      base_risk_score asc nulls last,
      suburb_key asc
  ) as expected_yield_rank,
  suburb_key,
  median_price,
  median_rent_weekly,
  gross_yield,
  estimated_oop,
  base_yield_score,
  base_total_score,
  base_demand_score,
  base_risk_score
from eligible
order by
  gross_yield desc nulls last,
  estimated_oop asc nulls last,
  base_total_score desc nulls last,
  base_demand_score desc nulls last,
  base_risk_score asc nulls last,
  suburb_key asc
limit 20;
