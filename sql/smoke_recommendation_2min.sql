-- Reference: Docs/sql_reference_smoke_recommendation_2min.md
-- 2-minute smoke test for recommendation flow
-- Run in Supabase SQL Editor.
-- Safe: runs in a transaction and rolls back.

begin;

do $$
declare
  -- Update if needed.
  v_user_profile_id uuid := '59bd7386-4695-4900-87a7-b4d9c00c5f9d';
  v_run_normal uuid;
  v_run_restrictive uuid;
  v_rec_normal jsonb;
  v_rec_restrictive jsonb;
begin
  if not exists (select 1 from public.user_profiles where id = v_user_profile_id) then
    raise exception 'Smoke setup failed: user_profile_id % not found', v_user_profile_id;
  end if;

  -- Scenario 1: Normal run should produce an array (possibly non-empty).
  insert into public.recommendation_runs (
    user_profile_id, created_by, input_budget, max_out_of_pocket, strategy_type
  )
  values (
    v_user_profile_id, v_user_profile_id, 900000, 500, 'growth'
  )
  returning id into v_run_normal;

  perform public.run_recommendation_engine(v_run_normal);

  select r.top_suburbs
  into v_rec_normal
  from public.recommendations r
  where r.recommendation_run_id = v_run_normal
  order by r.created_at desc
  limit 1;

  if v_rec_normal is null or jsonb_typeof(v_rec_normal) <> 'array' then
    raise exception 'Smoke FAIL S1: normal run top_suburbs missing or not array';
  end if;

  raise notice 'Smoke PASS S1: normal run array length = %', jsonb_array_length(v_rec_normal);

  -- Scenario 2: Restrictive run should still produce [] and never NULL.
  insert into public.recommendation_runs (
    user_profile_id, created_by, input_budget, max_out_of_pocket, strategy_type
  )
  values (
    v_user_profile_id, v_user_profile_id, 150000, 50, 'yield'
  )
  returning id into v_run_restrictive;

  perform public.run_recommendation_engine(v_run_restrictive);

  select r.top_suburbs
  into v_rec_restrictive
  from public.recommendations r
  where r.recommendation_run_id = v_run_restrictive
  order by r.created_at desc
  limit 1;

  if v_rec_restrictive is null or jsonb_typeof(v_rec_restrictive) <> 'array' then
    raise exception 'Smoke FAIL S2: restrictive run top_suburbs missing or not array';
  end if;

  raise notice 'Smoke PASS S2: restrictive run array length = %', jsonb_array_length(v_rec_restrictive);

  -- Scenario 3: Basic payload key shape check on first normal suburb (if any).
  if jsonb_array_length(v_rec_normal) > 0 then
    if not (
      (v_rec_normal -> 0) ? 'suburb' and
      (v_rec_normal -> 0) ? 'price' and
      (v_rec_normal -> 0) ? 'rent' and
      (v_rec_normal -> 0) ? 'yield' and
      (v_rec_normal -> 0) ? 'estimated_oop'
    ) then
      raise exception 'Smoke FAIL S3: expected keys missing in first suburb object';
    end if;
    raise notice 'Smoke PASS S3: payload keys present';
  else
    raise notice 'Smoke INFO S3: skipped key check because normal run returned 0 suburbs';
  end if;

  raise notice 'Smoke PASS: recommendation flow sanity checks completed';
end $$;

rollback;
