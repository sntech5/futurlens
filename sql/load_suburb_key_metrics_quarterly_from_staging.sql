-- Purpose:
-- Load verified quarterly market metrics from public.suburb_import_staging into
-- public.suburb_key_metrics_quarterly.
--
-- No-made-up-data rules:
-- - This script only loads rows with the required source metrics present.
-- - median_rent_weekly is derived only when typical_value and gross_rental_yield
--   are both present: weekly rent = median price * gross yield / 52.
-- - Rows without matching public.suburbs records are not loaded.
--
-- Expected staging columns:
-- state, post_code, suburb, avg_vendor_discount, days_on_market,
-- demand_to_supply_ratio, percent_renters_in_market, percent_stock_on_market,
-- statistical_reliability, typical_value, vacancy_rate, gross_rental_yield.

alter table public.suburb_key_metrics_quarterly
  add column if not exists median_price numeric,
  add column if not exists median_rent_weekly numeric,
  add column if not exists gross_yield numeric;

with cleaned as (
  select
    upper(trim(suburb)) || '_' || upper(trim(state)) || '_' || trim(post_code) as suburb_key,
    date_trunc('quarter', current_date)::date as quarter_date,
    nullif(regexp_replace(coalesce(typical_value, ''), '[^0-9.]', '', 'g'), '')::numeric as median_price,
    case
      when nullif(regexp_replace(coalesce(gross_rental_yield, ''), '[^0-9.]', '', 'g'), '')::numeric > 1
        then nullif(regexp_replace(coalesce(gross_rental_yield, ''), '[^0-9.]', '', 'g'), '')::numeric / 100
      else nullif(regexp_replace(coalesce(gross_rental_yield, ''), '[^0-9.]', '', 'g'), '')::numeric
    end as gross_yield,
    nullif(regexp_replace(coalesce(vacancy_rate, ''), '[^0-9.]', '', 'g'), '')::numeric as vacancy_rate,
    nullif(regexp_replace(coalesce(percent_renters_in_market, ''), '[^0-9.]', '', 'g'), '')::numeric as renters_pct,
    nullif(regexp_replace(coalesce(percent_stock_on_market, ''), '[^0-9.]', '', 'g'), '')::numeric as stock_on_market_pct,
    nullif(regexp_replace(coalesce(days_on_market, ''), '[^0-9.]', '', 'g'), '')::numeric as days_on_market,
    nullif(regexp_replace(coalesce(avg_vendor_discount, ''), '[^0-9.-]', '', 'g'), '')::numeric as vendor_discount_pct,
    null::numeric as population_growth_pct,
    null::numeric as infrastructure_score
  from public.suburb_import_staging
),
ready as (
  select
    c.suburb_key,
    c.quarter_date,
    c.median_price,
    round((c.median_price * c.gross_yield / 52)::numeric, 2) as median_rent_weekly,
    c.gross_yield,
    c.vacancy_rate,
    c.renters_pct,
    c.stock_on_market_pct,
    c.days_on_market,
    c.vendor_discount_pct,
    c.population_growth_pct,
    c.infrastructure_score
  from cleaned c
  join public.suburbs s on s.suburb_key = c.suburb_key
  where c.median_price is not null
    and c.median_price > 0
    and c.gross_yield is not null
    and c.gross_yield > 0
    and c.vacancy_rate is not null
    and c.stock_on_market_pct is not null
    and c.days_on_market is not null
    and c.days_on_market > 0
    and c.vendor_discount_pct is not null
)
insert into public.suburb_key_metrics_quarterly (
  suburb_key,
  quarter_date,
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
)
select
  suburb_key,
  quarter_date,
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
from ready
on conflict (suburb_key)
do update set
  quarter_date = excluded.quarter_date,
  median_price = excluded.median_price,
  median_rent_weekly = excluded.median_rent_weekly,
  gross_yield = excluded.gross_yield,
  vacancy_rate = excluded.vacancy_rate,
  renters_pct = excluded.renters_pct,
  stock_on_market_pct = excluded.stock_on_market_pct,
  days_on_market = excluded.days_on_market,
  vendor_discount_pct = excluded.vendor_discount_pct,
  population_growth_pct = excluded.population_growth_pct,
  infrastructure_score = excluded.infrastructure_score;
