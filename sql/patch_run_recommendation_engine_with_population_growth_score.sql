-- Purpose:
-- Refresh recommendation payload shape after adding
-- suburb_base_scores.base_population_growth_score.
--
-- Context:
-- public.run_recommendation_engine(p_run_id uuid)
--
-- Apply after:
-- - patch_growth_score_with_population_momentum.sql

create or replace function public.run_recommendation_engine(p_run_id uuid)
returns void
language plpgsql
as $$
declare
  v_user_profile_id uuid;
  v_budget numeric;
  v_max_oop numeric;
  v_strategy_type text;
  v_top_suburbs jsonb;
begin
  select
    rr.user_profile_id,
    rr.input_budget,
    rr.max_out_of_pocket,
    rr.strategy_type
  into
    v_user_profile_id,
    v_budget,
    v_max_oop,
    v_strategy_type
  from public.recommendation_runs rr
  where rr.id = p_run_id;

  if v_user_profile_id is null then
    raise exception 'run_recommendation_engine: run_id % not found or invalid', p_run_id;
  end if;

  if v_budget is null or v_max_oop is null or v_strategy_type is null then
    raise exception 'run_recommendation_engine: missing required run inputs for run_id %', p_run_id;
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'suburb', s.suburb_key,
        'price', s.median_price,
        'rent', s.median_rent_weekly,
        'yield', s.gross_yield,
        'estimated_oop', ((s.median_price * 0.8 * 0.06) / 52) - s.median_rent_weekly,
        'state', sub.state,
        'postcode', sub.postcode,
        'median_price', s.median_price,
        'median_rent_weekly', s.median_rent_weekly,
        'gross_yield', s.gross_yield,
        'vacancy_rate', s.vacancy_rate,
        'renters_pct', s.renters_pct,
        'stock_on_market_pct', s.stock_on_market_pct,
        'days_on_market', s.days_on_market,
        'vendor_discount_pct', s.vendor_discount_pct,
        'population_growth_pct', s.population_growth_pct,
        'infrastructure_score', s.infrastructure_score,
        'base_growth_score', s.base_growth_score,
        'base_population_growth_score', s.base_population_growth_score,
        'base_yield_score', s.base_yield_score,
        'base_demand_score', s.base_demand_score,
        'base_risk_score', s.base_risk_score,
        'base_total_score', s.base_total_score,
        'refreshed_at', s.refreshed_at
      )
      order by
        case when v_strategy_type = 'growth' then s.base_growth_score end desc nulls last,
        case when v_strategy_type = 'yield' then s.base_yield_score end desc nulls last,
        s.base_total_score desc nulls last
    ),
    '[]'::jsonb
  )
  into v_top_suburbs
  from public.suburb_base_scores s
  left join public.suburbs sub on sub.suburb_key = s.suburb_key
  where s.median_price <= v_budget
    and (((s.median_price * 0.8 * 0.06) / 52) - s.median_rent_weekly) <= v_max_oop;

  v_top_suburbs := coalesce(v_top_suburbs, '[]'::jsonb);

  insert into public.recommendations (
    recommendation_run_id,
    user_profile_id,
    top_suburbs,
    strategy_type,
    ai_summary
  )
  values (
    p_run_id,
    v_user_profile_id,
    v_top_suburbs,
    v_strategy_type,
    case
      when jsonb_array_length(v_top_suburbs) = 0 then 'No suburbs matched the selected budget and weekly out-of-pocket constraints.'
      else 'AI summary placeholder'
    end
  );

  update public.recommendation_runs
  set run_status = 'completed',
      completed_at = now()
  where id = p_run_id;
end;
$$;
