-- Purpose:
-- Diagnose whether growth and yield strategies produce different ranking orders
-- for the same budget and out-of-pocket constraints.
--
-- Safe-ish: writes temporary recommendation_runs/recommendations rows for the
-- configured test profile, then returns the top 10 comparison.
--
-- Adjust v_budget and v_max_oop before running if needed.

do $$
declare
  v_user_profile_id uuid := '59bd7386-4695-4900-87a7-b4d9c00c5f9d';
  v_budget numeric := 900000;
  v_max_oop numeric := 500;
  v_growth_run_id uuid;
  v_yield_run_id uuid;
begin
  insert into public.recommendation_runs (
    user_profile_id,
    created_by,
    input_budget,
    max_out_of_pocket,
    strategy_type
  )
  values (
    v_user_profile_id,
    v_user_profile_id,
    v_budget,
    v_max_oop,
    'growth'
  )
  returning id into v_growth_run_id;

  insert into public.recommendation_runs (
    user_profile_id,
    created_by,
    input_budget,
    max_out_of_pocket,
    strategy_type
  )
  values (
    v_user_profile_id,
    v_user_profile_id,
    v_budget,
    v_max_oop,
    'yield'
  )
  returning id into v_yield_run_id;

  perform public.run_recommendation_engine(v_growth_run_id);
  perform public.run_recommendation_engine(v_yield_run_id);

  raise notice 'growth_run_id=% yield_run_id=%', v_growth_run_id, v_yield_run_id;
end $$;

with latest_runs as (
  select
    strategy_type,
    id as run_id
  from public.recommendation_runs
  where strategy_type in ('growth', 'yield')
  order by created_at desc
  limit 2
),
latest_recommendations as (
  select distinct on (r.strategy_type)
    r.strategy_type,
    rec.top_suburbs
  from latest_runs r
  join public.recommendations rec on rec.recommendation_run_id = r.run_id
  order by r.strategy_type, rec.created_at desc
),
growth_ranked as (
  select
    item.ordinality as rank,
    item.value ->> 'suburb' as suburb_key,
    (item.value ->> 'base_growth_score')::numeric as growth_score,
    (item.value ->> 'base_yield_score')::numeric as yield_score,
    (item.value ->> 'base_total_score')::numeric as total_score
  from latest_recommendations r
  cross join lateral jsonb_array_elements(r.top_suburbs) with ordinality as item(value, ordinality)
  where r.strategy_type = 'growth'
),
yield_ranked as (
  select
    item.ordinality as rank,
    item.value ->> 'suburb' as suburb_key,
    (item.value ->> 'base_growth_score')::numeric as growth_score,
    (item.value ->> 'base_yield_score')::numeric as yield_score,
    (item.value ->> 'base_total_score')::numeric as total_score
  from latest_recommendations r
  cross join lateral jsonb_array_elements(r.top_suburbs) with ordinality as item(value, ordinality)
  where r.strategy_type = 'yield'
)
select
  coalesce(g.rank, y.rank) as rank,
  g.suburb_key as growth_suburb,
  g.growth_score as growth_suburb_growth_score,
  g.yield_score as growth_suburb_yield_score,
  g.total_score as growth_suburb_total_score,
  y.suburb_key as yield_suburb,
  y.growth_score as yield_suburb_growth_score,
  y.yield_score as yield_suburb_yield_score,
  y.total_score as yield_suburb_total_score,
  g.suburb_key is distinct from y.suburb_key as differs_at_rank
from growth_ranked g
full join yield_ranked y on y.rank = g.rank
where coalesce(g.rank, y.rank) <= 10
order by rank;
