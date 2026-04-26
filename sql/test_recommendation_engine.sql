-- Reference: Docs/sql_reference_test_recommendation_engine.md
-- Suburb Recommender MVP: function-level assertion tests
-- Run in Supabase SQL Editor against staging first.
-- This script uses a transaction and rolls back at the end.

begin;

do $$
declare
  -- Update this to a valid existing user_profiles.id in your project.
  v_user_profile_id uuid := '59bd7386-4695-4900-87a7-b4d9c00c5f9d';

  -- Scenario A (valid, should produce structured recommendation row).
  v_run_a uuid;
  v_rec_a record;

  -- Scenario B (intentionally restrictive, should return empty array, not NULL).
  v_run_b uuid;
  v_rec_b record;

  -- Ranking diagnostics.
  v_top_growth_score numeric;
  v_top_yield_score numeric;
begin
  -- Guard: ensure test user exists.
  if not exists (
    select 1 from public.user_profiles up where up.id = v_user_profile_id
  ) then
    raise exception 'Test setup failed: user_profiles.id % not found', v_user_profile_id;
  end if;

  -- Guard: ensure source score table has data.
  if not exists (select 1 from public.suburb_base_scores s) then
    raise exception 'Test setup failed: suburb_base_scores is empty';
  end if;

  -- Scenario A: normal run.
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
    900000,
    500,
    'growth'
  )
  returning id into v_run_a;

  perform public.run_recommendation_engine(v_run_a);

  select r.*
  into v_rec_a
  from public.recommendations r
  where r.recommendation_run_id = v_run_a
  order by r.created_at desc
  limit 1;

  if v_rec_a is null then
    raise exception 'FAIL TC-A1: no recommendations row written for run %', v_run_a;
  end if;

  if v_rec_a.top_suburbs is null then
    raise exception 'FAIL TC-A2: top_suburbs is NULL for run %', v_run_a;
  end if;

  if jsonb_typeof(v_rec_a.top_suburbs) <> 'array' then
    raise exception 'FAIL TC-A3: top_suburbs is not a JSON array for run %', v_run_a;
  end if;

  -- Filter assertions from generated payload.
  if exists (
    select 1
    from jsonb_array_elements(v_rec_a.top_suburbs) elem
    where coalesce((elem ->> 'price')::numeric, 0) > 900000
  ) then
    raise exception 'FAIL TC-A4: price filter violated (price > input_budget)';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(v_rec_a.top_suburbs) elem
    where coalesce((elem ->> 'estimated_oop')::numeric, 0) > 500
  ) then
    raise exception 'FAIL TC-A5: OOP filter violated (estimated_oop > max_out_of_pocket)';
  end if;

  -- Payload shape assertions.
  if exists (
    select 1
    from jsonb_array_elements(v_rec_a.top_suburbs) elem
    where not (elem ? 'suburb' and elem ? 'price' and elem ? 'rent' and elem ? 'yield' and elem ? 'estimated_oop')
  ) then
    raise exception 'FAIL TC-A6: one or more top_suburbs objects missing required keys';
  end if;

  -- Optional ranking diagnostic for growth strategy.
  select s.base_growth_score
  into v_top_growth_score
  from jsonb_array_elements(v_rec_a.top_suburbs) with ordinality elem(obj, pos)
  join public.suburb_base_scores s
    on s.suburb_key = elem.obj ->> 'suburb'
  where pos = 1;

  raise notice 'INFO: top growth score for Scenario A is %', v_top_growth_score;

  -- Scenario B: restrictive run; expect no matches but no errors and no NULL top_suburbs.
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
    150000,
    50,
    'yield'
  )
  returning id into v_run_b;

  perform public.run_recommendation_engine(v_run_b);

  select r.*
  into v_rec_b
  from public.recommendations r
  where r.recommendation_run_id = v_run_b
  order by r.created_at desc
  limit 1;

  if v_rec_b is null then
    raise exception 'FAIL TC-B1: no recommendations row written for restrictive run %', v_run_b;
  end if;

  if v_rec_b.top_suburbs is null then
    raise exception 'FAIL TC-B2: top_suburbs is NULL for restrictive run %', v_run_b;
  end if;

  if jsonb_typeof(v_rec_b.top_suburbs) <> 'array' then
    raise exception 'FAIL TC-B3: top_suburbs is not an array for restrictive run %', v_run_b;
  end if;

  raise notice 'INFO: restrictive scenario returned % suburbs',
    jsonb_array_length(v_rec_b.top_suburbs);

  -- Strategy comparison smoke check: same filters, different strategy.
  -- This confirms output is generated and allows manual diffing of top suburb.
  with run_growth as (
    insert into public.recommendation_runs (
      user_profile_id, created_by, input_budget, max_out_of_pocket, strategy_type
    )
    values (v_user_profile_id, v_user_profile_id, 900000, 500, 'growth')
    returning id
  ),
  run_yield as (
    insert into public.recommendation_runs (
      user_profile_id, created_by, input_budget, max_out_of_pocket, strategy_type
    )
    values (v_user_profile_id, v_user_profile_id, 900000, 500, 'yield')
    returning id
  ),
  call_growth as (
    select public.run_recommendation_engine((select id from run_growth)) as ok
  ),
  call_yield as (
    select public.run_recommendation_engine((select id from run_yield)) as ok
  ),
  growth_top as (
    select (jsonb_array_elements(r.top_suburbs) ->> 'suburb') as suburb_key
    from public.recommendations r
    where r.recommendation_run_id = (select id from run_growth)
    order by r.created_at desc
    limit 1
  ),
  yield_top as (
    select (jsonb_array_elements(r.top_suburbs) ->> 'suburb') as suburb_key
    from public.recommendations r
    where r.recommendation_run_id = (select id from run_yield)
    order by r.created_at desc
    limit 1
  )
  select s.base_yield_score
  into v_top_yield_score
  from public.suburb_base_scores s
  where s.suburb_key = (select suburb_key from yield_top);

  raise notice 'INFO: top yield score for yield scenario is %', v_top_yield_score;

  raise notice 'PASS: function-level assertions completed successfully';
end $$;

rollback;
