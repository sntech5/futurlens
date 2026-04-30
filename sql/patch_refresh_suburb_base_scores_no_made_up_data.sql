-- Purpose:
-- Replace the risky suburb base score refresh pattern with a source-data-only refresh.
--
-- Guardrails:
-- - Do not create suburb_base_scores rows just because a suburb exists in public.suburbs.
-- - Do not overwrite existing non-null metrics with null values from incomplete source rows.
-- - Do not set base_growth_score here; public.refresh_base_growth_scores() is the owner
--   of the current growth-score formula.
-- - Keep base_total_score on a 0-10 scale even though refresh_base_growth_scores()
--   stores base_growth_score on a 0-100 scale.
-- - Use public.suburb_key_metrics_quarterly as the only metric source. The app does not
--   depend on public.suburb_monthly_data.
--
-- Apply in Supabase SQL Editor after confirming the live function is named:
-- public.refresh_suburb_base_scores()

do $$
begin
  if to_regclass('public.suburb_key_metrics_quarterly') is null
     and to_regclass('public.suburb_quarterly_data') is not null then
    alter table public.suburb_quarterly_data rename to suburb_key_metrics_quarterly;
  end if;
end;
$$;

alter table public.suburb_key_metrics_quarterly
  add column if not exists quarter_period text,
  add column if not exists median_price numeric,
  add column if not exists median_rent_weekly numeric,
  add column if not exists gross_yield numeric;

create unique index if not exists suburb_key_metrics_quarterly_suburb_key_period_uidx
on public.suburb_key_metrics_quarterly (suburb_key, quarter_period);

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
    order by suburb_key, quarter_period desc
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
  scored as (
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
      -- gross_yield is stored as a decimal, e.g. 0.045 for 4.5%.
      greatest(0, least(10, gross_yield * 200)) as base_yield_score,
      greatest(0, least(10, round(
        (((1 / nullif(vacancy_rate, 0)) * 0.6) + ((1 / nullif(days_on_market, 0)) * 0.4))::numeric,
        3
      ))) as base_demand_score,
      greatest(0, least(10, stock_on_market_pct * 2)) as base_risk_score
    from source_rows
    where vacancy_rate > 0
      and days_on_market > 0
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
    base_growth_score,
    base_yield_score,
    base_demand_score,
    base_risk_score,
    null::numeric as base_total_score,
    now()
  from scored
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
    refreshed_at = now();

  -- Growth score is intentionally refreshed by the dedicated scoring function.
  perform public.refresh_base_growth_scores();

  -- Recalculate total score only after growth has been refreshed.
  update public.suburb_base_scores
  set base_total_score = round((
      coalesce(base_growth_score / 10, 0) * 0.30
    + coalesce(base_yield_score, 0) * 0.25
    + coalesce(base_demand_score, 0) * 0.30
    - coalesce(base_risk_score, 0) * 0.15
  )::numeric, 3)
  where median_price is not null
    and median_rent_weekly is not null
    and gross_yield is not null
    and vacancy_rate is not null
    and stock_on_market_pct is not null
    and days_on_market is not null
    and vendor_discount_pct is not null;
end;
$$;
