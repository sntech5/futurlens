-- Purpose:
-- Add source-backed population growth as a meaningful factor in suburb growth
-- ranking while keeping population scoring modular.
--
-- Apply in Supabase SQL Editor after public.suburb_population_metrics exists.
--
-- Model:
-- - population_growth_pct stores a weighted 2-year population momentum value:
--     70% growth_2024_2025_pct + 30% growth_2023_2024_pct
-- - population_growth_vs_state_pct stores suburb momentum minus state benchmark.
-- - state benchmark is population-weighted across loaded source-backed rows
--   for each state.
-- - base_population_growth_score stores the normalized 0-100 score from
--   population_growth_vs_state_pct.
-- - base_growth_score blends:
--     65% market momentum score + 35% population growth score
--
-- Missing population metrics:
-- - missing population rows receive a neutral score of 50
-- - missing values are not invented; population_growth_pct remains null

alter table public.suburb_base_scores
  add column if not exists population_growth_vs_state_pct numeric,
  add column if not exists base_population_growth_score numeric;

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
        when source_rows.population_growth_vs_state_pct is null then 50
        when stats.max_population_growth_vs_state_pct = stats.min_population_growth_vs_state_pct then 50
        else 100
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
    base_population_growth_score = round(scored.population_growth_score::numeric, 3),
    refreshed_at = now()
  from scored
  where t.suburb_key = scored.suburb_key;
end;
$$;

create or replace function public.refresh_base_growth_scores()
returns void
language plpgsql
as $$
declare
  v_weight_dsr numeric := 0.40;
  v_weight_dom numeric := 0.20;
  v_weight_stock numeric := 0.15;
  v_weight_discount numeric := 0.15;
  v_weight_vacancy numeric := 0.10;
  v_weight_market_momentum numeric := 0.65;
  v_weight_population_growth numeric := 0.35;
begin
  perform public.refresh_population_growth_scores();

  with stats as (
    select
      min(base_demand_score) as min_dsr,
      max(base_demand_score) as max_dsr,
      min(days_on_market) as min_dom,
      max(days_on_market) as max_dom,
      min(stock_on_market_pct) as min_stock,
      max(stock_on_market_pct) as max_stock,
      min(vendor_discount_pct) as min_discount,
      max(vendor_discount_pct) as max_discount,
      min(vacancy_rate) as min_vacancy,
      max(vacancy_rate) as max_vacancy
    from public.suburb_base_scores
    where base_demand_score is not null
      and days_on_market is not null
      and stock_on_market_pct is not null
      and vendor_discount_pct is not null
      and vacancy_rate is not null
  ),
  scored as (
    select
      s.suburb_key,
      case
        when stats.max_dsr = stats.min_dsr then 50
        else 100 * (s.base_demand_score - stats.min_dsr) / nullif(stats.max_dsr - stats.min_dsr, 0)
      end as dsr_score,

      case
        when stats.max_dom = stats.min_dom then 50
        else 100 * (stats.max_dom - s.days_on_market) / nullif(stats.max_dom - stats.min_dom, 0)
      end as dom_score,

      case
        when stats.max_stock = stats.min_stock then 50
        else 100 * (stats.max_stock - s.stock_on_market_pct) / nullif(stats.max_stock - stats.min_stock, 0)
      end as stock_score,

      case
        when stats.max_discount = stats.min_discount then 50
        else 100 * (stats.max_discount - s.vendor_discount_pct) / nullif(stats.max_discount - stats.min_discount, 0)
      end as discount_score,

      case
        when stats.max_vacancy = stats.min_vacancy then 50
        else 100 * (stats.max_vacancy - s.vacancy_rate) / nullif(stats.max_vacancy - stats.min_vacancy, 0)
      end as vacancy_score
    from public.suburb_base_scores s
    cross join stats
    where s.base_demand_score is not null
      and s.days_on_market is not null
      and s.stock_on_market_pct is not null
      and s.vendor_discount_pct is not null
      and s.vacancy_rate is not null
  )
  update public.suburb_base_scores t
  set
    base_growth_score =
      round((
        (
          scored.dsr_score * v_weight_dsr +
          scored.dom_score * v_weight_dom +
          scored.stock_score * v_weight_stock +
          scored.discount_score * v_weight_discount +
          scored.vacancy_score * v_weight_vacancy
        ) * v_weight_market_momentum +
        coalesce(t.base_population_growth_score, 50) * v_weight_population_growth
      )::numeric, 3),
    refreshed_at = now()
  from scored
  where t.suburb_key = scored.suburb_key;
end;
$$;
