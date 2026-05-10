-- Purpose:
-- Implement scoring_model_v2 from first principles.
--
-- Source of truth:
-- supabase/scoring_model_v2.config.json
-- Docs/scoring_model_v2_first_principles.md
--
-- Supabase SQL Editor note:
-- This file is intentionally split into numbered query blocks. Run one block at
-- a time if your SQL editor does not handle multi-statement scripts reliably.
--
-- Runtime note:
-- Postgres does not read supabase/scoring_model_v2.config.json at runtime.
-- If the JSON changes, update/redeploy these SQL functions so the database
-- executes the new formula.

-- QUERY 1: Add scoring_model_v2 output columns
alter table public.suburb_base_scores
  add column if not exists population_growth_vs_state_pct numeric,
  add column if not exists base_population_growth_score numeric,
  add column if not exists base_growth_strategy_total_score numeric,
  add column if not exists base_yield_strategy_total_score numeric,
  add column if not exists score_confidence text,
  add column if not exists score_explanation_payload jsonb;


-- QUERY 2: Refresh source-backed population momentum score on a 0-10 scale
create or replace function public.refresh_population_growth_scores()
returns void
language plpgsql
as $$
begin
  with population_source as (
    select
      pm.suburb_key,
      upper(pm.state) as state,
      pm.population_2025,
      (
        pm.growth_2024_2025_pct * 0.70
        + pm.growth_2023_2024_pct * 0.30
      )::numeric as population_momentum_pct
    from public.suburb_population_metrics pm
    where pm.growth_2024_2025_pct is not null
      and pm.growth_2023_2024_pct is not null
  ),
  state_benchmarks as (
    select
      state,
      coalesce(
        sum(population_momentum_pct * population_2025) / nullif(sum(population_2025), 0),
        avg(population_momentum_pct)
      ) as state_population_momentum_pct
    from population_source
    group by state
  ),
  source_rows as (
    select
      s.suburb_key,
      population_source.population_momentum_pct,
      state_benchmarks.state_population_momentum_pct,
      (
        population_source.population_momentum_pct
        - state_benchmarks.state_population_momentum_pct
      )::numeric as population_growth_vs_state_pct
    from public.suburb_base_scores s
    left join population_source
      on population_source.suburb_key = s.suburb_key
    left join public.suburbs sub
      on sub.suburb_key = s.suburb_key
    left join state_benchmarks
      on state_benchmarks.state = coalesce(population_source.state, upper(sub.state))
  ),
  stats as (
    select
      min(population_growth_vs_state_pct) as min_population_growth_vs_state_pct,
      max(population_growth_vs_state_pct) as max_population_growth_vs_state_pct
    from source_rows
    where population_growth_vs_state_pct is not null
  ),
  scored as (
    select
      source_rows.suburb_key,
      source_rows.population_momentum_pct,
      source_rows.population_growth_vs_state_pct,
      case
        when source_rows.population_growth_vs_state_pct is null then 5
        when stats.max_population_growth_vs_state_pct = stats.min_population_growth_vs_state_pct then 5
        else 10
          * (source_rows.population_growth_vs_state_pct - stats.min_population_growth_vs_state_pct)
          / nullif(stats.max_population_growth_vs_state_pct - stats.min_population_growth_vs_state_pct, 0)
      end as population_growth_score
    from source_rows
    cross join stats
  )
  update public.suburb_base_scores t
  set
    population_growth_pct = scored.population_momentum_pct,
    population_growth_vs_state_pct = scored.population_growth_vs_state_pct,
    base_population_growth_score = round(greatest(0, least(10, scored.population_growth_score))::numeric, 3),
    refreshed_at = now()
  from scored
  where t.suburb_key = scored.suburb_key;
end;
$$;

-- QUERY 3: Refresh growth score and strategy-specific total scores
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
      - coalesce(t.base_risk_score, 0) * 0.15
    )::numeric, 3))),
    base_yield_strategy_total_score = greatest(0, least(10, round((
        coalesce(t.base_yield_score, 0) * 0.40
      + coalesce(t.base_demand_score, 0) * 0.30
      + final_scores.growth_score * 0.15
      - coalesce(t.base_risk_score, 0) * 0.15
    )::numeric, 3))),
    base_total_score = null,
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
          'risk_score', -0.15
        ),
        'yield', jsonb_build_object(
          'yield_score', 0.40,
          'demand_score', 0.30,
          'growth_score', 0.15,
          'risk_score', -0.15
        )
      )
    ),
    refreshed_at = now()
  from final_scores
  where t.suburb_key = final_scores.suburb_key;
end;
$$;

-- QUERY 4: Refresh base scores from latest quarterly metrics using scoring_model_v2
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
    base_total_score,
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

      greatest(0, least(10, ((source_rows.gross_yield * 100) - 3.0) / 5.0 * 10)) as base_yield_score,

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
    round(base_yield_score::numeric, 3) as base_yield_score,
    base_demand_score,
    base_risk_score,
    null::numeric as base_total_score,
    null::numeric as base_growth_strategy_total_score,
    null::numeric as base_yield_strategy_total_score,
    null::text as score_confidence,
    jsonb_build_object(
      'model_version', 'scoring_model_v2',
      'source_config', 'supabase/scoring_model_v2.config.json',
      'yield_formula', 'clamp((gross_yield_pct - 3.0) / (8.0 - 3.0) * 10, 0, 10)',
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
    base_total_score = null,
    base_growth_strategy_total_score = null,
    base_yield_strategy_total_score = null,
    score_confidence = null,
    score_explanation_payload = excluded.score_explanation_payload,
    refreshed_at = now();

  perform public.refresh_base_growth_scores();
end;
$$;


-- QUERY 5: Rank recommendations by strategy-specific total scores
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
        -- Backward compatibility for the current frontend/report path. The
        -- generic base_total_score is now strategy-specific in recommendation
        -- payloads and should be renamed in frontend/report code next.
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


-- QUERY 6: Execute scoring_model_v2 refresh
-- Run this after QUERY 1 through QUERY 5 have completed successfully.
select public.refresh_suburb_base_scores();
