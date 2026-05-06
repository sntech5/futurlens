-- Purpose:
-- Make the selected investment strategy the primary recommendation ranking.
--
-- Why:
-- The previous recommendation order used base_total_score first and only used
-- the selected strategy score as a tiebreaker. Because total scores rarely tie,
-- growth and yield strategies often returned the same suburb order.
--
-- Ranking after this patch:
-- - growth strategy: base_growth_score desc, then base_total_score desc
-- - yield strategy: gross_yield desc, then estimated_oop asc, then base_total_score desc
--
-- Yield note:
-- base_yield_score is currently capped at 10 once gross_yield reaches 5%.
-- That makes many suburbs tie at 10/10 and causes base_total_score to become
-- the practical ranking driver. For yield strategy, raw gross_yield is the
-- better primary ranking metric until base_yield_score is redesigned.
--
-- Apply in Supabase SQL Editor.

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
  v_top_suburbs jsonb;
  v_updated_run_count integer;
begin
  select
    rr.user_profile_id,
    rr.input_budget,
    rr.max_out_of_pocket,
    lower(trim(rr.strategy_type))
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
        'base_total_score', s.base_total_score,
        'strategy_rank_score',
          case
            when v_strategy_type = 'growth' then s.base_growth_score
            when v_strategy_type = 'yield' then s.gross_yield
          end,
        'refreshed_at', s.refreshed_at
      )
      order by
        case when v_strategy_type = 'growth' then s.base_growth_score end desc nulls last,
        case when v_strategy_type = 'yield' then s.gross_yield end desc nulls last,
        case
          when v_strategy_type = 'yield'
            then (((s.median_price * 0.8 * 0.06) / 52) - s.median_rent_weekly)
        end asc nulls last,
        s.base_total_score desc nulls last,
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
      when v_strategy_type = 'growth' then 'Suburbs are ranked primarily by capital growth score, with overall investment score used as a quality tiebreaker.'
      else 'Suburbs are ranked primarily by rental yield score, with overall investment score used as a quality tiebreaker.'
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
