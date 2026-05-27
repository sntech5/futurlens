-- Purpose:
-- Add multi-state filtering to recommendation runs.
--
-- Apply in Supabase SQL Editor before deploying the frontend change.
-- Run one numbered query at a time.
--
-- Behavior:
-- - selected_states is stored on recommendation_runs as text[].
-- - Empty/null selected_states preserves previous all-state behavior.
-- - Non-empty selected_states filters recommendations to matching suburb states.

-- QUERY 1: Add selected_states to recommendation_runs.
alter table public.recommendation_runs
  add column if not exists selected_states text[] not null default '{}';

-- QUERY 2: Replace recommendation engine with selected-state filtering.
create or replace function public.run_recommendation_engine(p_run_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_profile_id uuid;
  v_budget numeric;
  v_max_oop numeric;
  v_strategy_type text;
  v_selected_states text[];
  v_top_suburbs jsonb;
  v_updated_run_count integer;
begin
  select
    rr.user_profile_id,
    rr.input_budget,
    rr.max_out_of_pocket,
    lower(trim(rr.strategy_type)),
    coalesce(rr.selected_states, '{}'::text[])
  into
    v_user_profile_id,
    v_budget,
    v_max_oop,
    v_strategy_type,
    v_selected_states
  from public.recommendation_runs rr
  where rr.id = p_run_id;

  if v_user_profile_id is null then
    raise exception 'run_recommendation_engine: run_id % not found or invalid', p_run_id;
  end if;

  if v_budget is null or v_max_oop is null or v_strategy_type is null then
    raise exception 'run_recommendation_engine: missing required run inputs for run_id %', p_run_id;
  end if;

  if v_strategy_type not in ('growth', 'yield') then
    raise exception 'run_recommendation_engine: unsupported strategy_type % for run_id %', v_strategy_type, p_run_id;
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
        'population_2025', pop.population_2025,
        'population_growth_pct', s.population_growth_pct,
        'population_growth_vs_state_pct', s.population_growth_vs_state_pct,
        'infrastructure_score', s.infrastructure_score,
        'base_growth_score', s.base_growth_score,
        'base_population_growth_score', s.base_population_growth_score,
        'base_yield_score', s.base_yield_score,
        'base_demand_score', s.base_demand_score,
        'base_risk_score', s.base_risk_score,
        'base_growth_strategy_total_score', s.base_growth_strategy_total_score,
        'base_yield_strategy_total_score', s.base_yield_strategy_total_score,
        'selected_strategy_total_score',
          case
            when v_strategy_type = 'growth' then s.base_growth_strategy_total_score
            when v_strategy_type = 'yield' then s.base_yield_strategy_total_score
          end,
        'base_total_score',
          case
            when v_strategy_type = 'growth' then s.base_growth_strategy_total_score
            when v_strategy_type = 'yield' then s.base_yield_strategy_total_score
          end,
        'strategy_rank_score',
          case
            when v_strategy_type = 'growth' then s.base_growth_strategy_total_score
            when v_strategy_type = 'yield' then s.base_yield_strategy_total_score
          end,
        'score_confidence', s.score_confidence,
        'score_explanation_payload', s.score_explanation_payload,
        'refreshed_at', s.refreshed_at
      )
      order by
        case when v_strategy_type = 'growth' then s.base_growth_strategy_total_score end desc nulls last,
        case when v_strategy_type = 'yield' then s.base_yield_strategy_total_score end desc nulls last,
        case when v_strategy_type = 'growth' then s.base_growth_score end desc nulls last,
        case when v_strategy_type = 'yield' then s.base_yield_score end desc nulls last,
        s.base_demand_score desc nulls last,
        s.base_risk_score asc nulls last,
        s.suburb_key asc
    ),
    '[]'::jsonb
  )
  into v_top_suburbs
  from public.suburb_base_scores s
  left join public.suburbs sub on sub.suburb_key = s.suburb_key
  left join public.suburb_population_metrics pop on pop.suburb_key = s.suburb_key
  where s.median_price <= v_budget
    and (((s.median_price * 0.8 * 0.06) / 52) - s.median_rent_weekly) <= v_max_oop
    and (
      cardinality(v_selected_states) = 0
      or upper(sub.state) = any (
        select upper(trim(state_code))
        from unnest(v_selected_states) as selected_state(state_code)
      )
    );

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
      when jsonb_array_length(v_top_suburbs) = 0 then 'No suburbs matched the selected budget, weekly out-of-pocket, and state filters.'
      when v_strategy_type = 'growth' then 'Suburbs are ranked by the growth strategy total score within the selected state filter.'
      else 'Suburbs are ranked by the yield strategy total score within the selected state filter.'
    end
  );

  update public.recommendation_runs
  set run_status = 'completed',
      completed_at = now()
  where id = p_run_id;

  get diagnostics v_updated_run_count = row_count;

  if v_updated_run_count <> 1 then
    raise exception 'run_recommendation_engine: failed to mark run % as completed', p_run_id;
  end if;
end;
$$;
