-- Purpose:
-- Fully retire public.suburb_base_scores.base_total_score after scoring_model_v2.
--
-- Why:
-- Ranking now uses strategy-specific total scores:
-- - base_growth_strategy_total_score
-- - base_yield_strategy_total_score
--
-- Supabase SQL Editor note:
-- Run one numbered query block at a time.

-- QUERY 1: Preflight - confirm remaining database references before cleanup
select
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as args,
  position('base_total_score' in pg_get_functiondef(p.oid)) > 0 as mentions_base_total_score
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'refresh_suburb_base_scores',
    'refresh_base_growth_scores',
    'run_recommendation_engine'
  )
order by p.proname;


-- QUERY 2: Replace refresh_base_growth_scores without base_total_score
create or replace function public.refresh_base_growth_scores()
returns void
language plpgsql
as $$
declare
  v_model_version text := 'scoring_model_v2';
  v_weight_population_growth numeric := 0.35;
  v_weight_dom numeric := 0.25;
  v_weight_stock numeric := 0.25;
  v_weight_discount numeric := 0.15;
begin
  perform public.refresh_population_growth_scores();

  with stats as (
    select
      min(days_on_market) as min_dom,
      max(days_on_market) as max_dom,
      min(stock_on_market_pct) as min_stock,
      max(stock_on_market_pct) as max_stock,
      min(abs(vendor_discount_pct)) as min_discount_magnitude,
      max(abs(vendor_discount_pct)) as max_discount_magnitude
    from public.suburb_base_scores
    where days_on_market is not null
      and days_on_market > 0
      and stock_on_market_pct is not null
      and vendor_discount_pct is not null
  ),
  scored as (
    select
      s.suburb_key,
      case
        when stats.max_dom = stats.min_dom then 5
        else 10 * (stats.max_dom - s.days_on_market) / nullif(stats.max_dom - stats.min_dom, 0)
      end as dom_score,
      case
        when stats.max_stock = stats.min_stock then 5
        else 10 * (stats.max_stock - s.stock_on_market_pct) / nullif(stats.max_stock - stats.min_stock, 0)
      end as stock_score,
      case
        when stats.max_discount_magnitude = stats.min_discount_magnitude then 5
        else 10
          * (stats.max_discount_magnitude - abs(s.vendor_discount_pct))
          / nullif(stats.max_discount_magnitude - stats.min_discount_magnitude, 0)
      end as discount_score
    from public.suburb_base_scores s
    cross join stats
    where s.days_on_market is not null
      and s.days_on_market > 0
      and s.stock_on_market_pct is not null
      and s.vendor_discount_pct is not null
  ),
  final_scores as (
    select
      t.suburb_key,
      greatest(0, least(10, round((
          coalesce(t.base_population_growth_score, 5) * v_weight_population_growth
        + scored.dom_score * v_weight_dom
        + scored.stock_score * v_weight_stock
        + scored.discount_score * v_weight_discount
      )::numeric, 3))) as growth_score,
      greatest(0, least(10, 10 - coalesce(t.base_risk_score, 10))) as risk_safety_score,
      case
        when t.population_growth_vs_state_pct is null then 'medium'
        else 'high'
      end as confidence,
      scored.dom_score,
      scored.stock_score,
      scored.discount_score
    from public.suburb_base_scores t
    join scored on scored.suburb_key = t.suburb_key
  )
  update public.suburb_base_scores t
  set
    base_growth_score = final_scores.growth_score,
    score_confidence = final_scores.confidence,
    base_growth_strategy_total_score = greatest(0, least(10, round((
        final_scores.growth_score * 0.45
      + coalesce(t.base_demand_score, 0) * 0.25
      + coalesce(t.base_yield_score, 0) * 0.15
      + final_scores.risk_safety_score * 0.15
    )::numeric, 3))),
    base_yield_strategy_total_score = greatest(0, least(10, round((
        coalesce(t.base_yield_score, 0) * 0.40
      + coalesce(t.base_demand_score, 0) * 0.30
      + final_scores.growth_score * 0.15
      + final_scores.risk_safety_score * 0.15
    )::numeric, 3))),
    score_explanation_payload = jsonb_build_object(
      'model_version', v_model_version,
      'source_config', 'supabase/scoring_model_v2.config.json',
      'growth_components', jsonb_build_object(
        'population_growth_score', coalesce(t.base_population_growth_score, 5),
        'days_on_market_score', round(final_scores.dom_score::numeric, 3),
        'stock_on_market_score', round(final_scores.stock_score::numeric, 3),
        'vendor_discount_magnitude_score', round(final_scores.discount_score::numeric, 3),
        'weights', jsonb_build_object(
          'population_growth', v_weight_population_growth,
          'days_on_market', v_weight_dom,
          'stock_on_market', v_weight_stock,
          'vendor_discount_magnitude', v_weight_discount
        )
      ),
      'strategy_total_scores', jsonb_build_object(
        'growth', jsonb_build_object(
          'growth_score', 0.45,
          'demand_score', 0.25,
          'yield_score', 0.15,
          'risk_safety_score', 0.15
        ),
        'yield', jsonb_build_object(
          'yield_score', 0.40,
          'demand_score', 0.30,
          'growth_score', 0.15,
          'risk_safety_score', 0.15
        )
      )
    ),
    refreshed_at = now()
  from final_scores
  where t.suburb_key = final_scores.suburb_key;
end;
$$;


-- QUERY 3: Replace refresh_suburb_base_scores without base_total_score
create or replace function public.refresh_suburb_base_scores()
returns void
language plpgsql
as $$
begin
  insert into public.suburb_base_scores (
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
    infrastructure_score,
    base_growth_score,
    base_yield_score,
    base_demand_score,
    base_risk_score,
    base_growth_strategy_total_score,
    base_yield_strategy_total_score,
    score_confidence,
    score_explanation_payload,
    refreshed_at
  )
  with latest_quarterly as (
    select distinct on (suburb_key)
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
      infrastructure_score
    from public.suburb_key_metrics_quarterly
    where median_price is not null
      and median_rent_weekly is not null
      and gross_yield is not null
      and vacancy_rate is not null
      and stock_on_market_pct is not null
      and days_on_market is not null
      and vendor_discount_pct is not null
    order by suburb_key, quarter_period desc nulls last
  ),
  source_rows as (
    select
      s.suburb_key,
      lq.median_price,
      lq.median_rent_weekly,
      lq.gross_yield,
      lq.vacancy_rate,
      lq.renters_pct,
      lq.stock_on_market_pct,
      lq.days_on_market,
      lq.vendor_discount_pct,
      lq.population_growth_pct,
      lq.infrastructure_score
    from public.suburbs s
    join latest_quarterly lq on lq.suburb_key = s.suburb_key
  ),
  stats as (
    select
      min(vacancy_rate) as min_vacancy,
      max(vacancy_rate) as max_vacancy,
      min(days_on_market) as min_dom,
      max(days_on_market) as max_dom,
      min(renters_pct) as min_renters,
      max(renters_pct) as max_renters,
      min(stock_on_market_pct) as min_stock,
      max(stock_on_market_pct) as max_stock,
      min(abs(vendor_discount_pct)) as min_discount_magnitude,
      max(abs(vendor_discount_pct)) as max_discount_magnitude
    from source_rows
    where vacancy_rate is not null
      and vacancy_rate >= 0
      and days_on_market > 0
      and renters_pct is not null
      and stock_on_market_pct is not null
      and vendor_discount_pct is not null
  ),
  scored as (
    select
      source_rows.suburb_key,
      source_rows.median_price,
      source_rows.median_rent_weekly,
      source_rows.gross_yield,
      source_rows.vacancy_rate,
      source_rows.renters_pct,
      source_rows.stock_on_market_pct,
      source_rows.days_on_market,
      source_rows.vendor_discount_pct,
      source_rows.population_growth_pct,
      source_rows.infrastructure_score,
      case
        when source_rows.gross_yield is null then null
        when source_rows.gross_yield * 100 <= 3.0 then 0
        when source_rows.gross_yield * 100 <= 4.5 then
          ((source_rows.gross_yield * 100 - 3.0) / 1.5) * 5
        when source_rows.gross_yield * 100 <= 5.5 then
          5 + ((source_rows.gross_yield * 100 - 4.5) / 1.0) * 2
        when source_rows.gross_yield * 100 <= 7.0 then
          7 + ((source_rows.gross_yield * 100 - 5.5) / 1.5) * 2
        when source_rows.gross_yield * 100 <= 8.0 then
          9 + ((source_rows.gross_yield * 100 - 7.0) / 1.0) * 1
        else 10
      end as base_yield_score,
      case
        when stats.max_vacancy = stats.min_vacancy then 5
        else 10 * (stats.max_vacancy - source_rows.vacancy_rate) / nullif(stats.max_vacancy - stats.min_vacancy, 0)
      end as demand_vacancy_score,
      case
        when stats.max_dom = stats.min_dom then 5
        else 10 * (stats.max_dom - source_rows.days_on_market) / nullif(stats.max_dom - stats.min_dom, 0)
      end as demand_dom_score,
      case
        when stats.max_renters = stats.min_renters then 5
        else 10 * (source_rows.renters_pct - stats.min_renters) / nullif(stats.max_renters - stats.min_renters, 0)
      end as demand_renters_score,
      case
        when stats.max_stock = stats.min_stock then 5
        else 10 * (stats.max_stock - source_rows.stock_on_market_pct) / nullif(stats.max_stock - stats.min_stock, 0)
      end as demand_stock_score,
      case
        when stats.max_stock = stats.min_stock then 5
        else 10 * (source_rows.stock_on_market_pct - stats.min_stock) / nullif(stats.max_stock - stats.min_stock, 0)
      end as risk_stock_score,
      case
        when stats.max_vacancy = stats.min_vacancy then 5
        else 10 * (source_rows.vacancy_rate - stats.min_vacancy) / nullif(stats.max_vacancy - stats.min_vacancy, 0)
      end as risk_vacancy_score,
      case
        when stats.max_dom = stats.min_dom then 5
        else 10 * (source_rows.days_on_market - stats.min_dom) / nullif(stats.max_dom - stats.min_dom, 0)
      end as risk_dom_score,
      case
        when stats.max_discount_magnitude = stats.min_discount_magnitude then 5
        else 10
          * (abs(source_rows.vendor_discount_pct) - stats.min_discount_magnitude)
          / nullif(stats.max_discount_magnitude - stats.min_discount_magnitude, 0)
      end as risk_discount_score
    from source_rows
    cross join stats
    where source_rows.vacancy_rate is not null
      and source_rows.vacancy_rate >= 0
      and source_rows.days_on_market > 0
      and source_rows.renters_pct is not null
  ),
  final_scores as (
    select
      scored.*,
      greatest(0, least(10, round((
          scored.demand_vacancy_score * 0.40
        + scored.demand_dom_score * 0.30
        + scored.demand_renters_score * 0.15
        + scored.demand_stock_score * 0.15
      )::numeric, 3))) as base_demand_score,
      greatest(0, least(10, round((
          scored.risk_stock_score * 0.30
        + scored.risk_vacancy_score * 0.25
        + scored.risk_dom_score * 0.20
        + scored.risk_discount_score * 0.15
        + 0 * 0.10
      )::numeric, 3))) as base_risk_score
    from scored
  )
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
    infrastructure_score,
    null::numeric as base_growth_score,
    round(greatest(0, least(10, base_yield_score))::numeric, 3) as base_yield_score,
    base_demand_score,
    base_risk_score,
    null::numeric as base_growth_strategy_total_score,
    null::numeric as base_yield_strategy_total_score,
    null::text as score_confidence,
    jsonb_build_object(
      'model_version', 'scoring_model_v2',
      'source_config', 'supabase/scoring_model_v2.config.json',
      'yield_formula', 'piecewise_linear: 3.0%=0, 4.5%=5, 5.5%=7, 7.0%=9, 8.0%+=10',
      'demand_weights', jsonb_build_object(
        'vacancy_rate', 0.40,
        'days_on_market', 0.30,
        'renters_pct', 0.15,
        'stock_on_market_pct', 0.15
      ),
      'risk_weights', jsonb_build_object(
        'stock_on_market_pct', 0.30,
        'vacancy_rate', 0.25,
        'days_on_market', 0.20,
        'vendor_discount_magnitude', 0.15,
        'data_missing_penalty', 0.10
      )
    ) as score_explanation_payload,
    now()
  from final_scores
  on conflict (suburb_key)
  do update set
    median_price = coalesce(excluded.median_price, public.suburb_base_scores.median_price),
    median_rent_weekly = coalesce(excluded.median_rent_weekly, public.suburb_base_scores.median_rent_weekly),
    gross_yield = coalesce(excluded.gross_yield, public.suburb_base_scores.gross_yield),
    vacancy_rate = coalesce(excluded.vacancy_rate, public.suburb_base_scores.vacancy_rate),
    renters_pct = coalesce(excluded.renters_pct, public.suburb_base_scores.renters_pct),
    stock_on_market_pct = coalesce(excluded.stock_on_market_pct, public.suburb_base_scores.stock_on_market_pct),
    days_on_market = coalesce(excluded.days_on_market, public.suburb_base_scores.days_on_market),
    vendor_discount_pct = coalesce(excluded.vendor_discount_pct, public.suburb_base_scores.vendor_discount_pct),
    population_growth_pct = coalesce(excluded.population_growth_pct, public.suburb_base_scores.population_growth_pct),
    infrastructure_score = coalesce(excluded.infrastructure_score, public.suburb_base_scores.infrastructure_score),
    base_yield_score = coalesce(excluded.base_yield_score, public.suburb_base_scores.base_yield_score),
    base_demand_score = coalesce(excluded.base_demand_score, public.suburb_base_scores.base_demand_score),
    base_risk_score = coalesce(excluded.base_risk_score, public.suburb_base_scores.base_risk_score),
    base_growth_strategy_total_score = null,
    base_yield_strategy_total_score = null,
    score_confidence = null,
    score_explanation_payload = excluded.score_explanation_payload,
    refreshed_at = now();

  perform public.refresh_base_growth_scores();
end;
$$;


-- QUERY 4: Replace run_recommendation_engine without base_total_score payload
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
        'base_growth_strategy_total_score', s.base_growth_strategy_total_score,
        'base_yield_strategy_total_score', s.base_yield_strategy_total_score,
        'selected_strategy_total_score',
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
      when v_strategy_type = 'growth' then 'Suburbs are ranked by the growth strategy total score.'
      else 'Suburbs are ranked by the yield strategy total score.'
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


-- QUERY 5: Drop the retired database column
alter table public.suburb_base_scores
  drop column if exists base_total_score;


-- QUERY 6: Post-drop validation - column should be gone
select
  column_name,
  data_type
from information_schema.columns
where table_schema = 'public'
  and table_name = 'suburb_base_scores'
  and column_name in (
    'base_total_score',
    'base_growth_strategy_total_score',
    'base_yield_strategy_total_score'
  )
order by column_name;


-- QUERY 7: Post-drop validation - active functions should no longer mention base_total_score
select
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as args,
  position('base_total_score' in pg_get_functiondef(p.oid)) > 0 as mentions_base_total_score
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'refresh_suburb_base_scores',
    'refresh_base_growth_scores',
    'run_recommendation_engine'
  )
order by p.proname;


-- QUERY 8: Refresh scores after cleanup
select public.refresh_suburb_base_scores();
